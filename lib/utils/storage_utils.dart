import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Only needed for migrateSharedPrefsToHive
import 'package:path/path.dart' as path;

import 'package:PhotoWordFind/models/contactEntry.dart';
import 'package:PhotoWordFind/utils/cloud_utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';
import 'package:validators/validators.dart';
import 'package:geocoding/geocoding.dart' as geo;

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
  static String get State => "state";
  // ignore: non_constant_identifier_names
  static String get Name => "name";
  // ignore: non_constant_identifier_names
  static String get Age => "age";
  // ignore: non_constant_identifier_names
  static String get Location => "location";
  // ignore: non_constant_identifier_names
  static String get Notes => "notes";
  // Verification dates: presence of a date indicates verified
  // for the respective platform.
  // Kept separate from "added" fields which indicate platform friend/follow state.
  static String get VerifiedSnapDate => "verifiedOnSnapDate";
  static String get VerifiedInstaDate => "verifiedOnInstaDate";
  static String get VerifiedDiscordDate => "verifiedOnDiscordDate";
}

class StorageUtils {
  static Map<String, String> filePaths = {};
  static bool enableLegacyImagePathSearch = false;
  // Reserved SharedPreferences keys that are app settings rather than contact entries.
  static const Set<String> reservedPrefKeys = {
    'use_new_ui_candidate',
    'last_selected_state',
    'import_directory',
    'migrated_verification_dates_v1',
  };

  // --- Debounced save coalescing (per-entry) ---
  // Removed: per-entry Hive debounce. Hive writes are fast and safe to call
  // directly; call sites can avoid awaiting if they don't need confirmation.

  // --- Debounced cloud sync (global) ---
  // If any save() requests backup=true, queue a single cloud update after a
  // short delay; subsequent requests extend the delay.
  static Timer? _cloudDebounceTimer;
  static const Duration _cloudDebounceDuration = Duration(seconds: 2);

  static Future<void> init() async {
    filePaths = (await readJson()).cast<String, String>();
    await initHive();
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

  /// Reads the JSON data from the file, using the in-memory cache if available.
  static Future<Map<String, dynamic>> readJson() async {
    // If filePaths is already loaded, return it directly
    if (filePaths.isNotEmpty) {
      return filePaths;
    }
    try {
      final file = await _localFile;
      String jsonString = await file.readAsString();
      filePaths = jsonDecode(jsonString).cast<String, String>();
      return filePaths;
    } catch (e) {
      // If encountering an error, return an empty map and reset filePaths
      debugPrint("Error reading JSON file: $e");
      filePaths = {};
      return {};
    }
  }

  /// Reset image paths json from the new UI design.
  /// This will delete the current file and create a new one
  /// Be careful with this as it will remove all saved image paths
  static Future<void> resetImagePaths() async {
    filePaths = {};
    await writeJson(filePaths);
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
      if ((_map['imagePath'] as String?)?.isNotEmpty ?? false)
        'imagePath': _map['imagePath'],
    };
    return map;
  }

  static Future syncLocalAndCloud() async {
    // Save to cloud
    // Note: prefer using the debounced cloud scheduling in save() where
    // appropriate. This method remains for explicit, immediate sync needs.
    if (await CloudUtils.isSignedin()) {
      await CloudUtils.updateCloudJson();
    }
  }

  /// Save a value of a key to Hive with the option to save to Google Drive as well.
  /// Note: I still need to determine if this function is still needed and
  /// being used. I expect that with the new saving function of auto saving
  /// with the Contact Entry this save function is no longer needed.
  static Future<void> save(
    ContactEntry entry, {
    bool reload = false,
  }) async {
  // Immediate Hive write; rely on Hive internals for batching/safety.
  final String id = entry.identifier;
  final String rawJson = jsonEncode(entry.toJson());
  final box = Hive.box('contacts');
  await box.put(id, rawJson);

  // Schedule a global debounced cloud sync after local save requests.
    _cloudDebounceTimer?.cancel();
    _cloudDebounceTimer = Timer(_cloudDebounceDuration, () async {
      _cloudDebounceTimer = null;
      if (await CloudUtils.isSignedin()) {
        await CloudUtils.updateCloudJson();
      }
    });
  }

  /// TODO: Revisit this and its use of Async, which restricts us to
  /// using a future as a return type. I'm hoping we can remove this restriction in the future,
  /// after investigating what can be simplified and/or initialized at the beginning
  static Future<ContactEntry?> get(String key) async {
    final box = Hive.box('contacts');
    String? rawJson = box.get(key);
    Map<String, dynamic>? map;

    // Decoding the map using new format and old format conversion
    try {
      if (rawJson == null) {
        throw ("Raw JSON is null for key: $key, will use old conversion format"
            "to create a boilplate empty map");
      }
      // If conversion fails, try decoding directly
      map = json.decode(rawJson);
    } catch (e) {
      debugPrint("Error converting value to map for key $key: $e");
      map = convertValueToMap(rawJson);
      debugPrint("Used old conversion format for key: $key");
    }
    // If map is null from old conversion format, return null
    if (map == null) return null;

    ContactEntry entry;
    if (map.containsKey('imagePath') && map['imagePath'] != null) {
      entry = ContactEntry.fromJson2(key, map);
    } else {
      // Always check filePaths cache first
      String? imagePath = filePaths[key];
      if (imagePath == null) {
        if (enableLegacyImagePathSearch) {
          // Only do the expensive directory scan if the flag is enabled
          List<String> dirs = [
            "Buzz buzz",
            "Honey",
            "Strings",
            "Stale",
            "Comb",
            "Delete"
          ];
          String testFilePath;
          for (final dir in dirs) {
            testFilePath = "/storage/emulated/0/DCIM/$dir/$key.jpg";
            if (File(testFilePath).existsSync()) {
              filePaths[key] = testFilePath;
              imagePath = testFilePath;
              debugPrint("Found image path: $imagePath for identifier: $key");
              await StorageUtils.writeJson(filePaths);
              break;
            }
          }
        }
        if (imagePath == null) {
          debugPrint("No image found for identifier: $key");
          return null;
        }
      }
      entry = ContactEntry.fromJson(key, imagePath, map);
    }

    if (entry.state == null || entry.state!.isEmpty) {
      entry.state = path.basename(path.dirname(entry.imagePath));
      await save(entry);
    }

    return entry;
  }

  static Future merge(Map<String, String> cloud) async {
    debugPrint("Entering merge()...");
    final box = Hive.box('contacts');
    // await box.clear();
    await migrateSharedPrefsToHive();

    // Enable legacy path searching when merging old cloud data
    bool _originalLegacySearch = enableLegacyImagePathSearch;
    enableLegacyImagePathSearch = true;

    List<Exception> mismatches = [];
    for (String key in cloud.keys) {
      String? localValueStr = box.get(key);
      if (localValueStr == null) {
        var returned = convertValueToMap(cloud[key], enforceMapOutput: true);
        if (returned != null &&
            returned.containsKey('imagePath') &&
            returned['imagePath'] != null) {
          final entry = ContactEntry.fromJson2(key, returned);
          await save(entry);
          debugPrint("Saving new format...");
        } else {
          await box.put(key, cloud[key]);
          // Use `get` to load and convert the entry so it now includes
          // an imagePath before saving in the newer format
          final entry = await get(key);
          if (entry != null) {
            await save(entry);
          }
        }
      } else {
        if (localValueStr != cloud[key] && isJSON(localValueStr)) {
          mismatches.add(Exception(
              '''Cloud and local copies don't match: [$key]\n               local: $localValueStr\n               cloud: ${cloud[key]}'''));
        }
      }
    }

    enableLegacyImagePathSearch = _originalLegacySearch;
    debugPrint("Leaving merge()...");
    if (mismatches.isNotEmpty) {
      throw Exception(mismatches);
    }
  }

  static Future<Map<String, String?>> toMap() async {
    final box = Hive.box('contacts');
    Map<String, String?> ret = {};
    for (var key in box.keys.whereType<String>()) {
      ret[key] = box.get(key);
    }
    return ret;
  }

  /// Returns all keys from the contacts Hive box without fetching values.
  static List<String> getKeys() {
    final box = Hive.box('contacts');
    return box.keys.whereType<String>().toList();
  }

  /// Get size of Contacts box
  static int getSize() {
    final box = Hive.box('contacts');
    return box.length;
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
      } on geo.NoResultFoundException {
        debugPrint("Inputted an invalid location: \\${map[SubKeys.Location]}");
      }
      map[SubKeys.Location] = {
        'name': map[SubKeys.Location],
        'lat': lat,
        'long': long,
      };
    }

    return map[SubKeys.Location];
  }

  /// Initialize Hive and open the contacts box
  static Future<void> initHive() async {
    await Hive.initFlutter();
    await Hive.openBox('contacts');
  }

  /// One-time migration: populate verification dates from existing platform
  /// "added" dates. Prior to separating concepts, "added" was often used as
  /// a proxy for verification. To preserve that signal, copy any existing
  /// dateAddedOn* into verifiedOn*At when verification is currently null.
  /// Returns the number of entries updated. Safe to call on every startup; it
  /// runs once and is idempotent via a SharedPreferences flag.
  static Future<int> migrateVerificationDatesIfNeeded() async {
    const String flagKey = 'migrated_verification_dates_v1';
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(flagKey) == true) return 0;

    int updated = 0;
    final keys = getKeys();
    for (final key in keys) {
      try {
        final entry = await get(key);
        if (entry == null) continue;
        bool changed = false;

        if (entry.verifiedOnSnapAt == null && entry.dateAddedOnSnap != null) {
          entry.verifiedOnSnapAt = entry.dateAddedOnSnap;
          changed = true;
        }
        if (entry.verifiedOnInstaAt == null && entry.dateAddedOnInsta != null) {
          entry.verifiedOnInstaAt = entry.dateAddedOnInsta;
          changed = true;
        }
        if (entry.verifiedOnDiscordAt == null && entry.dateAddedOnDiscord != null) {
          entry.verifiedOnDiscordAt = entry.dateAddedOnDiscord;
          changed = true;
        }

        if (changed) {
          updated++;
          await save(entry);
        }
      } catch (e) {
        debugPrint('Verification migration skipped key $key due to error: $e');
      }
    }

    await prefs.setBool(flagKey, true);
    return updated;
  }

  /// Migrate all SharedPreferences contact entries to Hive
  static Future<void> migrateSharedPrefsToHive() async {
    final box = Hive.box('contacts');
    final prefs = await SharedPreferences.getInstance();
    for (String key in prefs.getKeys()) {
  if (reservedPrefKeys.contains(key)) {
        debugPrint('Skipping reserved preference key during migration: $key');
        continue;
      }
      final value = prefs.getString(key);
      if (value != null) {
        // Store as String for now; can parse to Map if needed
        await box.put(key, value);

        // Use this to retrieve the image path if needed
        final entry = await StorageUtils.get(key);
        if (entry != null) {
          StorageUtils.save(entry);
        }
      }
    }
    // Validation: compare key counts in both stores
    final migratedKeys = box.keys.whereType<String>();
  // Only compare counts for non-reserved keys
  final nonReservedCount = prefs.getKeys().where((k) => !reservedPrefKeys.contains(k)).length;
  if (migratedKeys.length == nonReservedCount) {
      debugPrint('Migration to Hive complete. Key counts match.');
    } else {
      debugPrint(
      'Migration: mismatch in key counts. SharedPrefs(non-reserved): \\${nonReservedCount}, Hive: \\${migratedKeys.length}');
    }
  }
}
