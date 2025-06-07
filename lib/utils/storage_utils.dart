import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:collection/collection.dart';

import 'package:PhotoWordFind/models/contactEntry.dart';
import 'package:PhotoWordFind/utils/cloud_utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:validators/validators.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

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

  /// Currently testing out using these. haven't determined if I will keep them
  /// to use instead of/with _getStorageInstance.

  static SharedPreferences get instance => _prefs;

  static late Map<String, String> filePaths;
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    filePaths = (await readJson()).cast<String, String>();
  }

  
  /// Gets the local file where JSON data will be stored.
  static Future<File> get _localFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/test_saving_paths.json');
  }


  /// Writes the JSON data to a file.
  static Future<File> writeJson(Map<String, dynamic> json) async {
    final file = await _localFile;
    String jsonString = jsonEncode(json);
    return file.writeAsString(jsonString);
  }

  /// Reads the JSON data from the file.
  static Future<Map<String, dynamic>> readJson() async {
    try {
      final file = await _localFile;
      String jsonString = await file.readAsString();
      return jsonDecode(jsonString);
    } catch (e) {
      // If encountering an error, return an empty map.
      debugPrint("Error reading JSON file: $e");
      return {};
    }
  }

  /// Reset image paths json
  /// This will delete the current file and create a new one
  /// Be careful with this as it will remove all saved image paths
  static Future<void> resetImagePaths() async {
    filePaths = {};
    await writeJson(filePaths);
  }

  static Future<SharedPreferences> _getStorageInstance(
      {required bool reload}) async {
    var ret = instance;
    if (reload) ret.reload();

    return ret;
  }

  static Map<String, dynamic>? convertValueToMap(String? value,
      {bool enforceMapOutput = false}) {
    Map<String, dynamic> _map;
    try {
      if (value == null) {
        throw FormatException("value was null. Creating empty fresh mapping");
      }
      _map = json.decode(value);
    } on FormatException catch (e) {
      log(e.message);
      if (!enforceMapOutput) {
        return null;
      }

      // Assumes this is an OCR that doesn't exist on this phone yet and was created BEFORE format change
      _map = {};
    }
    Map<String, dynamic> map = {
      SubKeys.OCR: _map[SubKeys.OCR] ?? value,
      SubKeys.SnapUsername: _map[SubKeys.SnapUsername],
      SubKeys.InstaUsername: _map[SubKeys.InstaUsername],
      SubKeys.DiscordUsername: _map[SubKeys.DiscordUsername],
      SubKeys.AddedOnSnap: _map[SubKeys.AddedOnSnap] ?? false,
      SubKeys.AddedOnInsta: _map[SubKeys.AddedOnInsta] ?? false,
      SubKeys.AddedOnDiscord: _map[SubKeys.AddedOnDiscord] ?? false,
      SubKeys.SnapDate:
          _map[SubKeys.SnapDate] != null && _map[SubKeys.SnapDate].isNotEmpty
              ? DateTime.parse(_map[SubKeys.SnapDate])
              : null,
      SubKeys.InstaDate:
          _map[SubKeys.InstaDate] != null && _map[SubKeys.InstaDate].isNotEmpty
              ? DateTime.parse(_map[SubKeys.InstaDate])
              : null,
      SubKeys.DiscordDate: _map[SubKeys.DiscordDate] != null &&
              _map[SubKeys.DiscordDate].isNotEmpty
          ? DateTime.parse(_map[SubKeys.DiscordDate])
          : null,
      SubKeys.PreviousUsernames: _map[SubKeys.PreviousUsernames] ??
          <String, List<String>>{
            SubKeys.SnapUsername: <String>[],
            SubKeys.InstaUsername: <String>[],
          },
      SubKeys.Notes: _map[SubKeys.Notes],
      // New values from chat GPT
      SubKeys.SocialMediaHandles: _map[SubKeys.SocialMediaHandles],
      SubKeys.Sections: ((_map[SubKeys.Sections] as List?)?.isNotEmpty ?? false)
          ? _map[SubKeys.Sections]
          : null,
      SubKeys.Name: (_map[SubKeys.Name] as String?)?.isNotEmpty ?? false
          ? _map[SubKeys.Name]
          : null,
      SubKeys.Age: (_map[SubKeys.Age] is int) ? _map[SubKeys.Age] : null,
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

    // Code used to convert locations
    // if (map[SubKeys.Location] != null && !(map[SubKeys.Location] is Map)) {
    //   // Get coordinates from location string
    //   double? lat = null, long = null;
    //   try {
    //     if ((map[SubKeys.Location] as String?)!.isNotEmpty) {
    //       List<geo.Location> locations = await geo
    //           .locationFromAddress(map[SubKeys.Location])
    //           .timeout(Duration(seconds: 5));
    //       if (locations.isEmpty) throw "Could not determine a location";

    //       var loc = locations.first;
    //       lat = loc.latitude;
    //       long = loc.longitude;
    //     }
    //   } on geo.NoResultFoundException catch (e) {
    //   } finally {
    //     debugPrint(
    //         "Failed location determination from file: $storageKey: ${map[SubKeys.Location]}");
    //   }
    //   map[SubKeys.Location] = {
    //     'name': map[SubKeys.Location],
    //     'lat': lat,
    //     'long': long,
    //   };
    // }
    // if (map[SubKeys.Location] != null && map[SubKeys.Location] is Map) {
    //   Map<String, dynamic> location =
    //       map[SubKeys.Location] as Map<String, dynamic>;
    //   if (location['name'] != null && (location['name'] as String).isEmpty) {
    //     location['name'] = null;
    //   }
    // }

    // Todo: If Map is sent in concat with current saved values
    // ...

    if (overridingUsername != null && overridingUsername) {
      final List<String?>? previousSnapUsernames =
          map[SubKeys.PreviousUsernames][SubKeys.SnapUsername].cast<String>();
      final List<String?>? previousInstaUsernames =
          map[SubKeys.PreviousUsernames][SubKeys.InstaUsername].cast<String>();
      String? currentSnap = map[SubKeys.SnapUsername],
          currentInsta = map[SubKeys.InstaUsername];

      if (snap != null && !previousSnapUsernames!.contains(currentSnap)) {
        previousSnapUsernames.add(currentSnap);
      }
      if (insta != null && !previousInstaUsernames!.contains(currentInsta)) {
        previousInstaUsernames.add(currentInsta);
      }
    }
    if (asMap != null) map.addAll(asMap);
    if (ocrResult != null) map[SubKeys.OCR] = ocrResult;
    if (snap != null)
      map[SubKeys.SocialMediaHandles][SubKeys.SnapUsername] = snap;
    if (insta != null)
      map[SubKeys.SocialMediaHandles][SubKeys.InstaUsername] = insta;
    if (discord != null)
      map[SubKeys.SocialMediaHandles][SubKeys.DiscordUsername] = discord;
    if (snapAdded != null) map[SubKeys.AddedOnSnap] = snapAdded;
    if (instaAdded != null) map[SubKeys.AddedOnInsta] = instaAdded;
    if (discordAdded != null) map[SubKeys.AddedOnDiscord] = discordAdded;
    if (snapAddedDate != null)
      map[SubKeys.SnapDate] = snapAddedDate.toIso8601String();
    if (instaAddedDate != null)
      map[SubKeys.InstaDate] = instaAddedDate.toIso8601String();
    if (discordAddedDate != null)
      map[SubKeys.DiscordDate] = discordAddedDate.toIso8601String();
    if (notes != null) map[SubKeys.Notes] = notes;

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
    ContactEntry? entry = await ContactEntry.loadFromPreferences(key);
    SharedPreferences prefs = (await _getStorageInstance(reload: reload));
    String? rawJson = prefs.getString(key);

    Map<String, dynamic>? map = convertValueToMap(rawJson);

    if (entry == null) return null;

    if (asMap) {
      return map;
    } else if (snap) {
      return entry.snapUsername;
    } else if (insta) {
      return entry.instaUsername;
    } else if (discord) {
      return entry.discordUsername;
    } else if (snapAdded) {
      return entry.addedOnSnap;
    } else if (instaAdded) {
      return entry.addedOnInsta;
    } else if (discordAdded) {
      return entry.addedOnDiscord;
    } else if (snapDate) {
      return entry.dateAddedOnSnap;
    } else if (instaDate) {
      return entry.dateAddedOnInsta;
    } else if (discordDate) {
      return entry.dateAddedOnDiscord;
    } else if (notes) {
      return entry.notes;
    } else {
      return entry.extractedText;
    }
  }

  static Future merge(Map<String, String> cloud) async {
    debugPrint("Entering merge()...");

    List<Exception> mismatches = [];
    for (String key in cloud.keys) {
      String? localValueStr = (await get(key, reload: false)) as String?;

      // ContactEntry? contact = await ContactEntry.loadFromPreferences(key);
      // var contactAsMap = contact?.toJson();
      // Map? localValue = (await get(key, reload: false, asMap: true)) as Map?;

      // if (DeepCollectionEquality.unordered().equals(localValue, contactAsMap)) {
      // } else {
      //   debugPrint('''$key was not equal.
      //   contact: $contactAsMap
        
      //   control: $localValue
        
      //   raw: $localValueStr
      //   ''');
      // }

      // Assuming that if it isn't saved locally then it must be just an OCR before the format change
      if (localValueStr == null) {
        var returned = convertValueToMap(cloud[key], enforceMapOutput: true);
        save(key, asMap: returned, backup: false);
        debugPrint("Saving...");
      } else {
        // Print whether cloud value and Storage values match
        // debugPrint("String ($key) matches: ${(value == cloud[key])}");

        if (localValueStr != cloud[key] && isJSON(localValueStr)) {
          mismatches.add(Exception('''Cloud and local copies don't match: [$key]
               local: $localValueStr
               cloud: ${cloud[key]}'''));
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

  /// Takes in a map of contact values and updates the location to {name, lat, long} equivalent if
  /// location exists in the map. If it is null then nothing happens
  static Future<Map<String, dynamic>> getCoordinatesOfLocation(
      dynamic map) async {
    if (map[SubKeys.Location] != null && !(map[SubKeys.Location] is Map)) {
      // Get coordinates from location string
      double? lat = null, long = null;
      try {
        if ((map[SubKeys.Location] as String?)!.isNotEmpty) {
          List<geo.Location> locations = await geo
              .locationFromAddress(map[SubKeys.Location] as String)
              .timeout(Duration(seconds: 5));
          if (locations.isEmpty) throw "Could not determine a location";

          var loc = locations.first;
          lat = loc.latitude;
          long = loc.longitude;
        }
      } on geo.NoResultFoundException catch (e) {
        debugPrint("Inputted an invalid location: ${map[SubKeys.Location]}");
      }
      map[SubKeys.Location] = {
        'name': map[SubKeys.Location],
        'lat': lat,
        'long': long,
      };
    }

    return map[SubKeys.Location];
  }
}
