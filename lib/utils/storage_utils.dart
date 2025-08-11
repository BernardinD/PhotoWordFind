import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:PhotoWordFind/utils/cloud_utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:validators/validators.dart';

class SubKeys {
  // ignore: non_constant_identifier_names
  static String get OCR => "ocr";
  // ignore: non_constant_identifier_names
  static String get SnapUsername => "snap";
  // ignore: non_constant_identifier_names
  static String get InstaUsername => "insta";
  // ignore: non_constant_identifier_names
  static String get DiscordUsername => "discord";
  // ignore: non_constant_identifier_names
  static String get AddedOnSnap => "addedOnSnap";
  // ignore: non_constant_identifier_names
  static String get AddedOnInsta => "addedOnInsta";
  // ignore: non_constant_identifier_names
  static String get AddedOnDiscord => "addedOnDiscord";
  // ignore: non_constant_identifier_names
  static String get SnapDate => "dateAddedOnSnap";
  // ignore: non_constant_identifier_names
  static String get InstaDate => "dateAddedOnInsta";
  // ignore: non_constant_identifier_names
  static String get DiscordDate => "dateAddedOnDiscord";
  // ignore: non_constant_identifier_names
  static String get PreviousUsernames => "previousUsernames";
  // ignore: non_constant_identifier_names
  static String get SocialMediaHandles => "social_media_handles";
  // ignore: non_constant_identifier_names
  static String get Sections => "sections";
  // ignore: non_constant_identifier_names
  static String get Name => "name";
  // ignore: non_constant_identifier_names
  static String get Age => "age";
  // ignore: non_constant_identifier_names
  static String get Location => "location";
  // ignore: non_constant_identifier_names
  static String get Notes => "notes";
}

class StorageUtils {
  static Future<SharedPreferences> _getStorageInstance({required bool reload}) async {
    var ret = await SharedPreferences.getInstance();
    if (reload) ret.reload();

    return ret;
  }

  static Map<String, dynamic>? convertValueToMap(String? value,
      {bool enforceMapOutput = false}) {
    Map<String, dynamic> _map;
    try {
      if (value == null)
        throw FormatException("value was null. Creating empty fresh mapping");
      _map = json.decode(value);
    } on FormatException catch (e) {
      log(e.message);
      if (!enforceMapOutput) {
        return null;
      }

      // Assumes this is an OCR that doesn't exist on this phone yet and was created BEFORE format change
      _map = {};
    }
    // Compatibility: detect new UI ContactEntry shape and normalize.
    bool looksLikeNewContact = _map.containsKey('extractedText') || _map.containsKey('imagePath');
    if (looksLikeNewContact) {
      // Map probable new field names to legacy keys if legacy not present.
      _map[SubKeys.OCR] = _map[SubKeys.OCR] ?? _map['extractedText'];
      _map[SubKeys.SnapUsername] = _map[SubKeys.SnapUsername] ?? _map['snapUsername'];
      _map[SubKeys.InstaUsername] = _map[SubKeys.InstaUsername] ?? _map['instaUsername'];
      _map[SubKeys.DiscordUsername] = _map[SubKeys.DiscordUsername] ?? _map['discordUsername'];
      _map[SubKeys.AddedOnSnap] = _map[SubKeys.AddedOnSnap] ?? _map['addedOnSnap'];
      _map[SubKeys.AddedOnInsta] = _map[SubKeys.AddedOnInsta] ?? _map['addedOnInsta'];
      _map[SubKeys.AddedOnDiscord] = _map[SubKeys.AddedOnDiscord] ?? _map['addedOnDiscord'];
      _map[SubKeys.SnapDate] = _map[SubKeys.SnapDate] ?? _map['dateAddedOnSnap'];
      _map[SubKeys.InstaDate] = _map[SubKeys.InstaDate] ?? _map['dateAddedOnInsta'];
      _map[SubKeys.DiscordDate] = _map[SubKeys.DiscordDate] ?? _map['dateAddedOnDiscord'];
      _map[SubKeys.Sections] = _map[SubKeys.Sections] ?? _map['sections'];
      _map[SubKeys.Name] = _map[SubKeys.Name] ?? _map['name'];
      _map[SubKeys.Age] = _map[SubKeys.Age] ?? _map['age'];
      _map[SubKeys.Location] = _map[SubKeys.Location] ?? _map['location'];
      _map[SubKeys.Notes] = _map[SubKeys.Notes] ?? _map['notes'];
      // Social media handles may already be grouped; if not, synthesize the map.
      if (_map[SubKeys.SocialMediaHandles] == null) {
        _map[SubKeys.SocialMediaHandles] = {
          SubKeys.SnapUsername: _map[SubKeys.SnapUsername] ?? '',
          SubKeys.InstaUsername: _map[SubKeys.InstaUsername] ?? '',
          SubKeys.DiscordUsername: _map[SubKeys.DiscordUsername] ?? '',
        };
      }
    }
    Map<String, dynamic> map = {
      SubKeys.OCR:             _map[SubKeys.OCR] ?? value,
      SubKeys.SnapUsername:    _map[SubKeys.SnapUsername] ?? "",
      SubKeys.InstaUsername:   _map[SubKeys.InstaUsername] ?? "",
      SubKeys.DiscordUsername: _map[SubKeys.DiscordUsername] ?? "",
      SubKeys.AddedOnSnap:     _map[SubKeys.AddedOnSnap] ?? false,
      SubKeys.AddedOnInsta:    _map[SubKeys.AddedOnInsta] ?? false,
      SubKeys.AddedOnDiscord:  _map[SubKeys.AddedOnDiscord] ?? false,
      SubKeys.SnapDate:        _map[SubKeys.SnapDate]    != null && _map[SubKeys.SnapDate].toString().isNotEmpty    ? DateTime.tryParse(_map[SubKeys.SnapDate])?.toIso8601String()  ?? '' : "",
      SubKeys.InstaDate:       _map[SubKeys.InstaDate]   != null && _map[SubKeys.InstaDate].toString().isNotEmpty   ? DateTime.tryParse(_map[SubKeys.InstaDate  ])?.toIso8601String() ?? '' : "",
      SubKeys.DiscordDate:     _map[SubKeys.DiscordDate] != null && _map[SubKeys.DiscordDate].toString().isNotEmpty ? DateTime.tryParse(_map[SubKeys.DiscordDate  ])?.toIso8601String() ?? '' : "",
      SubKeys.PreviousUsernames: _map[SubKeys.PreviousUsernames] ?? <String, List<String>>{
        SubKeys.SnapUsername: <String>[],
        SubKeys.InstaUsername: <String>[],
      },
      SubKeys.Notes: _map[SubKeys.Notes],
      // New values from chat GPT
      SubKeys.SocialMediaHandles: _map[SubKeys.SocialMediaHandles],
      SubKeys.Sections: _map[SubKeys.Sections],
      SubKeys.Name: _map[SubKeys.Name],
      SubKeys.Age: _map[SubKeys.Age],
      SubKeys.Location: _map[SubKeys.Location],
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

  /// Save a value of a key to internal store with the option to save to Google
  /// Drive as well.
  /// [overridingUsername] is a signal of whether to archive the current username
  static Future save(String storageKey,
      {String? ocrResult,
      required bool backup,
      bool reload = false,
      bool? overridingUsername,
      String? snap,
      String? insta,
      String? discord,
      bool? snapAdded,
      bool? instaAdded,
      bool? discordAdded,
      DateTime? snapAddedDate,
      DateTime? instaAddedDate,
      DateTime? discordAddedDate,
      String? notes,
      Map<String, dynamic>? asMap}) async {
    if ((snap != null || insta != null || discord != null) &&
        overridingUsername == null) {
      throw Exception("Must declare if username is being overwritten");
    } else if (overridingUsername != null &&
        overridingUsername &&
        snap == null &&
        insta == null &&
        discord == null) {
      throw Exception("Missing username to overwrite");
    }
    Map<String, dynamic>? map =
        (await get(storageKey, reload: false, asMap: true))
            as Map<String, dynamic>?;

    map ??= convertValueToMap("", enforceMapOutput: true)!;

    // Todo: If Map is sent in concat with current saved values
    // ...

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
    if (asMap              != null) map.addAll(asMap);
    if (ocrResult          != null) map[SubKeys.OCR]             = ocrResult;
    if (snap               != null) map[SubKeys.SocialMediaHandles][SubKeys.SnapUsername]    = snap;
    if (insta              != null) map[SubKeys.SocialMediaHandles][SubKeys.InstaUsername]   = insta;
    if (discord            != null) map[SubKeys.SocialMediaHandles][SubKeys.DiscordUsername] = discord;
    if (snapAdded          != null) map[SubKeys.AddedOnSnap]     = snapAdded;
    if (instaAdded         != null) map[SubKeys.AddedOnInsta]    = instaAdded;
    if (discordAdded       != null) map[SubKeys.AddedOnDiscord]  = discordAdded;
    if (snapAddedDate      != null) map[SubKeys.SnapDate]        = snapAddedDate.toIso8601String();
    if (instaAddedDate     != null) map[SubKeys.InstaDate]       = instaAddedDate.toIso8601String();
    if (discordAddedDate   != null) map[SubKeys.DiscordDate]     = discordAddedDate.toIso8601String();
    if (notes              != null) map[SubKeys.Notes]                 = notes;

    String rawJson = jsonEncode(map);
    (await _getStorageInstance(reload: reload)).setString(storageKey, rawJson);

    // Save to cloud
    // TODO: Put this inside a timer that saves a few seconds after a save call
    if (backup && await CloudUtils.isSignedin()) {
      await CloudUtils.updateCloudJson();
    }
  }

  static Future get(String key,
      {required bool reload,
      bool snap = false,
      bool insta = false,
      bool discord = false,
      bool snapAdded = false,
      bool instaAdded = false,
      bool discordAdded = false,
      bool snapDate = false,
      bool instaDate = false,
      bool discordDate = false,
      bool notes = false,
      bool asMap = false}) async {
    
    final box = Hive.box('contacts');
    String? rawJson = box.get(key);

    Map<String, dynamic>? map = convertValueToMap(rawJson);

    if(map == null) return null;

    if      (asMap)        { return map; }
    else if (snap)         { return map[SubKeys.SocialMediaHandles]?[ SubKeys.SnapUsername    ] ?? map[ SubKeys.SnapUsername    ]; }
    else if (insta)        { return map[SubKeys.SocialMediaHandles]?[ SubKeys.InstaUsername   ] ?? map[ SubKeys.InstaUsername   ]; }
    else if (discord)      { return map[SubKeys.SocialMediaHandles]?[ SubKeys.DiscordUsername ] ?? map[ SubKeys.DiscordUsername ]; }
    else if (snapAdded)    { return map[ SubKeys.AddedOnSnap    ] ??  false; }
    else if (instaAdded)   { return map[ SubKeys.AddedOnInsta   ] ??  false; }
    else if (discordAdded) { return map[ SubKeys.AddedOnDiscord ] ??  false; }
    else if (snapDate)     { return map[ SubKeys.SnapDate      ]; }
    else if (instaDate)    { return map[ SubKeys.InstaDate     ]; }
    else if (discordDate)  { return map[ SubKeys.DiscordDate   ]; }
    else if (notes)        { return map[ SubKeys.Notes         ]; }
    else                   { return map[ SubKeys.OCR           ]; }
  }

  static Future merge(Map<String, String> cloud) async {
    debugPrint("Entering merge()...");

    List<Exception> mismatches = [];
    for (String key in cloud.keys) {
      String? localValue = (await get(key, reload: false)) as String?;
      // Assuming that if it isn't saved locally then it must be just an OCR before the format change
      if (localValue == null) {
        var returned = convertValueToMap(cloud[key], enforceMapOutput: true);
        save(key, asMap: returned, backup: false);
        debugPrint("Saving...");
      } else {
        // Print whether cloud value and Storage values match
        // debugPrint("String ($key) matches: ${(value == cloud[key])}");

        if (localValue != cloud[key] && isJSON(localValue)) {
          mismatches.add(Exception(
              "Cloud and local copies don't match: [$key] \n local: $localValue \n cloud: ${cloud[key]}"));
        }
      }
    }
    debugPrint("Leaving merge()...");
    if (mismatches.isNotEmpty) {
      throw Exception(mismatches);
    }
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
