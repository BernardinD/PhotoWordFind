import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PhotoWordFind/utils/cloud_utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:validators/validators.dart';

class StorageUtils {
  static Future<SharedPreferences> _getStorageInstance({@required bool reload}) async {
    var ret = await SharedPreferences.getInstance();
    if (reload) ret.reload();

    return ret;
  }

  static Map<String, dynamic> convertValueToMap(String value) {
    Map<String, dynamic> _map;
    try {
      _map = json.decode(value);
    } on FormatException catch (e) {
      // Assumes this is an OCR that doesn't exist on this phone yet and was created BEFORE format change
      _map = {};
    }
    Map<String, dynamic> map = {
      "ocr": _map["ocr"] ?? value,
      "snap": _map["snap"] ?? "",
      "insta": _map["insta"] ?? "",
      "addedOnSnap": _map["addedOnSnap"] ?? false,
      "addedOnInsta": _map["addedOnInsta"] ?? false,
      "dateAddedOnSnap":  _map["dateAddedOnSnap"]  != null && _map["dateAddedOnSnap"].isNotEmpty  ? DateTime.parse(_map["dateAddedOnSnap"]).toIso8601String()  : "",
      "dateAddedOnInsta": _map["dateAddedOnInsta"] != null && _map["dateAddedOnInsta"].isNotEmpty ? DateTime.parse(_map["dateAddedOnInsta"]).toIso8601String() : "",
    };
    return map;
  }

  static Future save(String key,
      {String ocrResult,
      @required bool backup,
      String snap = "",
      bool snapAdded, DateTime snapAddedDate}) async {
    Map<String, dynamic> map = await get(key, reload: false, asMap: true);
    if (ocrResult     != null) map['ocr']             = ocrResult;
    if (snap          != null) map['snap']            = snap;
    if (snapAdded     != null) map['addedOnSnap']     = snapAdded;
    if (snapAddedDate != null) map['dateAddedOnSnap'] = snapAddedDate.toIso8601String();

    String rawJson = jsonEncode(map);
    (await _getStorageInstance(reload: false)).setString(key, rawJson);

    // Save to cloud
    // TODO: Put this inside a timer that saves a few seconds after a save call
    if (backup && await CloudUtils.isSignedin()) {
      await CloudUtils.updateCloudJson();
    }
  }

  static Future get(String key,
      {@required bool reload, bool snap = false, bool asMap = false, bool snapAdded = false}) async {
    String rawJson = (await _getStorageInstance(reload: reload)).getString(key);

    Map<String, dynamic> map = convertValueToMap(rawJson);;
    // try {
    //   map = json.decode(rawJson);
    // } on FormatException catch (e) {
    //   // Assumes this is an OCR that doesn't exist on this phone yet and was created BEFORE format change
    //   map = await convertValueToMap(rawJson);
    // }

    if (asMap) {
      return map;
    } else if (snap) {
      return map['snap'];
    } else if(snapAdded) {
      return map['addedOnSnap']??false;
    } else {
      return map['ocr'];
    }
    // return rawJson;
  }

  static Future merge(Map<String, String> cloud) async {
    debugPrint("Entering merge()...");

    int i = 0;
    for (String key in cloud.keys) {
      String localValue = await get(key, reload: false);
      if (localValue == null) {
        save(key, ocrResult: cloud[key], backup: false);
        debugPrint("Saving...");
      } else {
        // Print whether cloud value and Storage values match
        // debugPrint("String ($key) matches: ${(value == cloud[key])}");

        if (localValue != cloud[key] && isJSON(localValue)) {
          throw Exception("Cloud and local copies don't match");
        }
      }
    }
    debugPrint("Leaving merge()...");
  }

  static Future<Map<String, String>> toMap() async {
    var store = await _getStorageInstance(reload: true);
    Map<String, String> ret = Map();

    for (String key in store.getKeys()) {
      ret[key] = store.getString(key);
    }

    return ret;
  }
}
