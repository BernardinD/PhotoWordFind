import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:PhotoWordFind/social_icons.dart';
import 'package:PhotoWordFind/utils/cloud_utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:validators/validators.dart';

class SubKeys{
  static String get OCR => "ocr";
  static String get SnapUsername => "snap";
  static String get InstaUsername => "insta";
  static String get AddedOnSnap => "addedOnSnap";
  static String get AddedOnInsta => "addedOnInsta";
  static String get SnapDate => "dateAddedOnSnap";
  static String get InstaDate => "dateAddedOnInsta";
  static String get PreviousUsernames => "previousUsernames";

}

class StorageUtils {
  static Future<SharedPreferences> _getStorageInstance({required bool reload}) async {
    var ret = await SharedPreferences.getInstance();
    if (reload) ret.reload();

    return ret;
  }

  static Map<String, dynamic> convertValueToMap(String value) {
    late Map<String, dynamic> _map;
    try {
      if(value == null) throw FormatException("value was null. Creating empty fresh mapping");
      _map = json.decode(value);
    } on FormatException catch (e) {
      // Assumes this is an OCR that doesn't exist on this phone yet and was created BEFORE format change
      _map = {};
    }
    Map<String, dynamic> map = {
      SubKeys.OCR:           _map[SubKeys.OCR] ?? value,
      SubKeys.SnapUsername:  _map[SubKeys.SnapUsername] ?? "",
      SubKeys.InstaUsername: _map[SubKeys.InstaUsername] ?? "",
      SubKeys.AddedOnSnap:   _map[SubKeys.AddedOnSnap] ?? false,
      SubKeys.AddedOnInsta:  _map[SubKeys.AddedOnInsta] ?? false,
      SubKeys.SnapDate:      _map[SubKeys.SnapDate]  != null && _map[SubKeys.SnapDate].isNotEmpty  ? DateTime.parse(_map[SubKeys.SnapDate]).toIso8601String()  : "",
      SubKeys.InstaDate:     _map[SubKeys.InstaDate] != null && _map[SubKeys.InstaDate].isNotEmpty ? DateTime.parse(_map[SubKeys.InstaDate  ]).toIso8601String() : "",
      SubKeys.PreviousUsernames:     _map[SubKeys.PreviousUsernames] ?? <String, List<String>>{
        SubKeys.SnapUsername: <String>[],
        SubKeys.InstaUsername: <String>[],
      }
    };
    return map;
  }

  static Future syncLocalAndCloud() async {

    await _getStorageInstance(reload: true);

    // Save to cloud
    // TODO: Put this inside a timer that saves a few seconds after a save call
    if (await CloudUtils.isSignedin()) {
      await CloudUtils.updateCloudJson();
    }
  }

  static Future save(String storageKey,
      {String? ocrResult,
      required bool backup,
      bool reload = false,
      bool? overridingUsername,
      String? snap,
      String? insta,
      bool? snapAdded,
      bool? instaAdded,
      DateTime? snapAddedDate,
      DateTime? instaAddedDate}) async {
    if ((snap != null || insta != null) && overridingUsername == null){
      throw Exception("Must declare if username is being overwritten");
    }
    else if(overridingUsername != null && overridingUsername && snap == null && insta == null){
      throw Exception("Missing username to overwrite");
    }
    Map<String, dynamic> map = (await get(storageKey, reload: false, asMap: true)) as Map<String, dynamic>;

    if (overridingUsername != null && overridingUsername) {
      final List<String?>? previousSnapUsernames  = map[SubKeys.PreviousUsernames][SubKeys.SnapUsername].cast<String>();
      final List<String?>? previousInstaUsernames = map[SubKeys.PreviousUsernames][SubKeys.InstaUsername].cast<String>();
      String? currentSnap = map[SubKeys.SnapUsername], currentInsta = map[SubKeys.InstaUsername];

      if (snap != null && !previousSnapUsernames!.contains(currentSnap)) {
        previousSnapUsernames.add(currentSnap);
      }
      if (insta != null && !previousInstaUsernames!.contains(currentInsta)) {
        previousInstaUsernames.add(currentInsta);
      }
    }
    if (ocrResult          != null) map[SubKeys.OCR]             = ocrResult;
    if (snap               != null) map[SubKeys.SnapUsername]    = snap;
    if (insta              != null) map[SubKeys.InstaUsername]   = insta;
    if (snapAdded          != null) map[SubKeys.AddedOnSnap]     = snapAdded;
    if (instaAdded         != null) map[SubKeys.AddedOnInsta]    = instaAdded;
    if (snapAddedDate      != null) map[SubKeys.SnapDate]        = snapAddedDate.toIso8601String();
    if (instaAddedDate     != null) map[SubKeys.InstaDate]       = instaAddedDate.toIso8601String();


    String rawJson = jsonEncode(map);
    if (storageKey != null)
      (await _getStorageInstance(reload: reload)).setString(storageKey, rawJson);

    // Save to cloud
    // TODO: Put this inside a timer that saves a few seconds after a save call
    if (backup && await CloudUtils.isSignedin()) {
      await CloudUtils.updateCloudJson();
    }
  }

  static Future get(String key,
      {required bool reload, bool snap = false, bool insta = false, bool snapAdded = false, bool instaAdded = false, snapDate = false, instaDate = false, bool asMap = false}) async {
    String rawJson = (await _getStorageInstance(reload: reload)).getString(key)!;

    Map<String, dynamic> map = convertValueToMap(rawJson);

    if      (asMap)      { return map; }
    else if (snap)       { return map[ SubKeys.SnapUsername  ]; }
    else if (insta)      { return map[ SubKeys.InstaUsername ]; }
    else if (snapAdded)  { return map[ SubKeys.AddedOnSnap   ] ??  false; }
    else if (snapDate)   { return map[ SubKeys.SnapDate      ]; }
    else if (instaDate)  { return map[ SubKeys.InstaDate     ]; }
    else if (instaAdded) { return map[ SubKeys.AddedOnInsta  ] ??  false; }
    else                 { return map[ SubKeys.OCR           ]; }
  }

  static Future merge(Map<String, String> cloud) async {
    debugPrint("Entering merge()...");

    int i = 0;
    for (String key in cloud.keys) {
      String? localValue = (await get(key, reload: false)) as String?;
      if (localValue == null) {
        save(key, ocrResult: cloud[key], backup: false);
        debugPrint("Saving...");
      } else {
        // Print whether cloud value and Storage values match
        // debugPrint("String ($key) matches: ${(value == cloud[key])}");

        if (localValue != cloud[key] && isJSON(localValue)) {
          throw Exception("Cloud and local copies don't match: [$key] \n local: $localValue \n cloud: ${cloud[key]}");
        }
      }
    }
    debugPrint("Leaving merge()...");
  }

  static Future<Map<String, String?>> toMap() async {
    var store = await _getStorageInstance(reload: true);
    Map<String, String?> ret = Map();

    for (String key in store.getKeys()) {
      ret[key] = store.getString(key);
    }

    return ret;
  }
}
