import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:mobx/mobx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:json_annotation/json_annotation.dart';
import 'package:PhotoWordFind/models/location.dart';
import 'package:PhotoWordFind/utils/storage_utils.dart';

part 'contactEntry.g.dart';

ObservableMap<String, List<String>>? fromJsonObservableMapOfLists(
    Map<String, List<String>>? json) {
  if (json == null) {
    return null; // Handle the null input case, returning null
  }
  return ObservableMap<String, List<String>>.of(
      json); // Return the converted ObservableMap
}

Map<String, List<String>>? toJsonObservableMapOfLists(
    ObservableMap<String, List<String>>? object) {
  if (object == null) {
    return null; // Handle the null input case, returning null
  }
  return Map<String, List<String>>.of(
      object); // Convert ObservableMap to regular Map
}

ObservableMap<String, String>? fromJsonObservableMapOfStrings(
    Map<String, String>? json) {
  if (json == null) {
    return null; // Handle the null input case, returning null
  }
  return ObservableMap<String, String>.of(
      json); // Return the converted ObservableMap
}

Map<String, String?>? toJsonObservableMapOfStrings(
    ObservableMap<String, String?>? object) {
  if (object == null) {
    return null; // Handle the null input case, returning null
  }
  return Map<String, String?>.of(
      object); // Convert ObservableMap to regular Map
}

ObservableList<Map<String, String?>>? fromJsonObservableListOfMaps(
    List<Map<String, String?>>? json) {
  if (json == null) {
    return null; // Handle the null input case, returning null
  }
  return ObservableList<Map<String, String?>>.of(
      json); // Return the converted ObservableList
}

List<Map<String, String>>? toJsonObservableListOfMaps(
    ObservableList<Map<String, String>>? object) {
  if (object == null) {
    return null; // Handle the null input case, returning null
  }
  return List<Map<String, String>>.of(
      object); // Convert ObservableList to regular List
}

typedef FieldUpdater<T> = void Function(T model, dynamic value);
final Map<String, FieldUpdater<_ContactEntry>> fieldUpdaters = {
  SubKeys.Sections: (model, value) {
    if (value is List && value.isNotEmpty) {
      final listOfMaps = value.map((item) {
        if (item is Map) {
          final safeMap = item.map(
            (ky, vl) => MapEntry(
              ky.toString(),
              vl?.toString() ?? "",
            ),
          );
          return ObservableMap<String, String>.of(safeMap);
        }
        return ObservableMap<String, String>();
      }).toList();
      model.sections = ObservableList.of(listOfMaps);
    } else {
      model.sections = null;
    }
  },
  SubKeys.Location: (model, value) {
    if (value is Map) {
      model.location = Location(
        rawLocation: value['name'],
        timezone: value['timezone'] as String?,
      );
    } else {
      model.location = null;
    }
  },
  SubKeys.SocialMediaHandles: (model, value) => model.socialMediaHandles =
      value != null
          ? ObservableMap.of((value as Map<String, dynamic>)
              .map((key, value) => MapEntry(key, value as String?)))
          : null,
};

class ContactEntry extends _ContactEntry with _$ContactEntry {
  ContactEntry(
      {required this.identifier,
      required String imagePath,
      required this.dateFound,
      required Map<String, dynamic> json})
      : super(
          imagePath: imagePath,
          ocr: json[SubKeys.OCR],
          name: (json[SubKeys.Name] as String?)?.isNotEmpty ?? false
              ? json[SubKeys.Name]
              : null,
          age: json[SubKeys.Age] is int ? json[SubKeys.Age] : null,
          dateAddedOnSnap: json[SubKeys.SnapDate] != null &&
                  json[SubKeys.SnapDate].isNotEmpty
              ? DateTime.parse(json[SubKeys.SnapDate])
              : null,
          instaUsername: json[SubKeys.InstaUsername],
          discordUsername: json[SubKeys.DiscordUsername],
          snapUsername: json[SubKeys.SnapUsername],
          dateAddedOnInsta: json[SubKeys.InstaDate] != null &&
                  json[SubKeys.InstaDate].isNotEmpty
              ? DateTime.parse(json[SubKeys.InstaDate])
              : null,
          dateAddedOnDiscord: json[SubKeys.DiscordDate] != null &&
                  json[SubKeys.DiscordDate].isNotEmpty
              ? DateTime.parse(json[SubKeys.DiscordDate])
              : null,
          addedOnSnap: json[SubKeys.AddedOnSnap] ?? false,
          addedOnInsta: json[SubKeys.AddedOnInsta] ?? false,
          addedOnDiscord: json[SubKeys.AddedOnDiscord] ?? false,
          previousHandles: ObservableMap.of(
              (json[SubKeys.PreviousUsernames] as Map<String, dynamic>?)?.map(
                    (key, value) => MapEntry(
                      key, value != null
                        ? ObservableList<String>.of((value as List<dynamic>).nonNulls.cast<String>())
                        : ObservableList<String>()),
                  ) ??
                  <String, ObservableList<String>>{
                    SubKeys.SnapUsername: ObservableList<String>(),
                    SubKeys.InstaUsername: ObservableList<String>(),
                  }),
          notes: json[SubKeys.Notes],
        ) {
    _setupAutoSave();
  }
  final String identifier;
  final DateTime dateFound;

  factory ContactEntry.fromJson(
      String storageKey, String imagePath, Map<String, dynamic> json,
      {bool save = false}) {
    var instance = ContactEntry(
        identifier: storageKey,
        imagePath: imagePath,
        dateFound: File(imagePath).lastModifiedSync(),
        json: json);

    instance.mergeFromJson(json, save);

    return instance;
  }

  void mergeFromJson(Map<String, dynamic> json_, bool save) {
    _suppressAutoSave = false;

    json_.forEach((key, value) {
      final updater = fieldUpdaters[key];
      if (updater != null) {
        updater(this, value);
      }
    });
    extractedText = extractedText ?? ocr;
    snapUsername = socialMediaHandles?[SubKeys.SnapUsername] ?? snapUsername;
    instaUsername = socialMediaHandles?[SubKeys.InstaUsername] ?? instaUsername;
    discordUsername =
        socialMediaHandles?[SubKeys.DiscordUsername] ?? discordUsername;

    _suppressAutoSave = true;
    if (save) {
      _saveToPreferences();
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'imagePath': imagePath,
      SubKeys.OCR: ocr,
      SubKeys.SnapUsername: snapUsername,
      SubKeys.InstaUsername: instaUsername,
      SubKeys.DiscordUsername: discordUsername,
      SubKeys.AddedOnSnap: addedOnSnap,
      SubKeys.AddedOnInsta: addedOnInsta,
      SubKeys.AddedOnDiscord: addedOnDiscord,
      SubKeys.SnapDate: dateAddedOnSnap?.toIso8601String(),
      SubKeys.InstaDate: dateAddedOnInsta?.toIso8601String(),
      SubKeys.DiscordDate: dateAddedOnDiscord?.toIso8601String(),
      SubKeys.PreviousUsernames: previousHandles?.isNotEmpty ?? false
          ? Map.from(previousHandles!
              .map((key, value) => MapEntry(key, value.toList())))
          : null,
      SubKeys.Notes: notes,
      SubKeys.SocialMediaHandles: socialMediaHandles?.isNotEmpty ?? false
          ? Map.from(socialMediaHandles!)
          : null,
      SubKeys.Sections: sections?.isNotEmpty ?? false
          ? sections!.toList().map(Map.from).toList()
          : null,
      SubKeys.Name: name,
      SubKeys.Age: age,
      SubKeys.Location: location?.toJson(),
    };
  }

  void _setupAutoSave() {
    reaction((_) => toJson(),
        (_) => !_suppressAutoSave ? _saveToPreferences() : null);
  }

  Future<void> _saveToPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(identifier, jsonEncode(toJson()));
  }

  static Future<ContactEntry?> loadFromPreferences(String identifier,
      {bool reload = false}) async {
    // if (_localPrefs == null) {
    //   await _localPrefs;
    // }

    // SharedPreferences localPrefs = (await _localPrefs)!;

    // if(reload) await localPrefs.reload();

    final jsonString = StorageUtils.instance.getString(identifier);
    if (jsonString == null) return null;

    final Map<String, dynamic> json = jsonDecode(jsonString);

    Map<String, String> filePaths =
        (await StorageUtils.readJson()).cast<String, String>();

    String? imagePath =
        StorageUtils.filePaths[identifier] ?? filePaths[identifier];

    if (imagePath == null) {
      debugPrint("The save didn't work: $identifier");
      return null;
      List<String> dirs = ["Buzz buzz", "Honey", "Strings", "Stale", "Comb", "Delete"];
      String testFilePath;
      
      for (final _dir in dirs) {
        testFilePath = "/storage/emulated/0/DCIM/$_dir/$identifier.jpg";
        if (File(testFilePath).existsSync()) {
          filePaths[identifier] = testFilePath;
          imagePath = testFilePath;
          debugPrint(
              "Found image path: $imagePath for identifier: $identifier");
          await StorageUtils.writeJson(filePaths);
          break;
        }
      }
      if (imagePath == null) {
        debugPrint("No image found for identifier: $identifier");
        return null;
      }
    }

    return ContactEntry.fromJson(identifier, imagePath, json);
  }
}

/// This class represents the data parsed from each image and has an update tracking
/// on each fail as to allow for syncing the sharedPreferences (presistent data)
/// with the update values. Also, each field is able to be nullable as to account
/// for failed transcribing and still wanting to display the image in the UI
/// for reprocessing or optical feedback to the user.
abstract class _ContactEntry with Store {
  // _ContactEntry();

  // Variable used for disabling auto updating of persistence
  bool _suppressAutoSave = true;

  /// Holds all the transcribed data. For other entries this will be the ocr.
  /// And for newer ones this will be all the values of "sections" for now.
  /// In the future will possible be just "my bio" or removed all togeter
  /// in place of image overlaying.
  @observable
  String? extractedText;

  String imagePath;

  /// The ocr scanned from images BEFORE switching over to chatGPT approach.
  final String? ocr;

  @observable
  String? snapUsername;

  @observable
  String? instaUsername;

  @observable
  String? discordUsername;

  @observable
  DateTime? dateAddedOnSnap;

  @observable
  DateTime? dateAddedOnInsta;

  @observable
  DateTime? dateAddedOnDiscord;

  @observable
  bool addedOnSnap;

  @observable
  bool addedOnInsta;

  @observable
  bool addedOnDiscord;

  @observable
  @JsonKey(
      fromJson: fromJsonObservableMapOfLists,
      toJson: toJsonObservableMapOfLists)
  ObservableMap<String, ObservableList<String>>? previousHandles;

  /// Stored text of user notes and reminders for this person
  @observable
  String? notes;

  // New chatGPT responses
  final String? name;

  final int? age;

  Location? location;

  /// The chatGPT response of the handles seen in the sent image. All though
  /// there are specific entries for each common handle type, this entry is
  /// kept as to make it much easier to combine maps of the pre-existing map
  /// and all new reiteration for this image.
  @observable
  ObservableMap<String, String?>? socialMediaHandles;

  @observable
  ObservableList<ObservableMap<String, String>>? sections;

  @action
  updateSnapchat(String snapchat) {
    _suppressAutoSave = false;
    if (snapUsername != null) {
      previousHandles?[SubKeys.SnapUsername]?.add(snapchat);
      snapUsername = snapchat;
    }
    _suppressAutoSave = true;
  }

  @action
  updateInstagram(String instagram) {
    _suppressAutoSave = false;
    if (instaUsername != null) {
      previousHandles?[SubKeys.InstaUsername]?.add(instagram);
      instaUsername = instagram;
    }
    _suppressAutoSave = true;
  }

  @action
  updateDiscord(String discord) {
    _suppressAutoSave = false;
    if (discordUsername != null) {
      previousHandles?[SubKeys.DiscordUsername]?.add(discord);
      discordUsername = discord;
    }
    _suppressAutoSave = true;
  }

  @action
  addSnapchat() {
    // Avoid repeated calls for each field
    _suppressAutoSave = false;
    dateAddedOnSnap = DateTime.now();
    _suppressAutoSave = true;

    addedOnSnap = true;
  }

  @action
  addInstagram() {
    // Avoid repeated calls for each field
    _suppressAutoSave = false;
    dateAddedOnInsta = DateTime.now();
    _suppressAutoSave = true;

    addedOnInsta = true;
  }

  @action
  addDiscord() {
    // Avoid repeated calls for each field
    _suppressAutoSave = false;
    dateAddedOnDiscord = DateTime.now();
    _suppressAutoSave = true;

    addedOnDiscord = true;
  }

  @action
  resetSnapchatAdd() {
    // Avoid repeated calls for each field
    _suppressAutoSave = false;
    dateAddedOnSnap = DateTime.now();
    _suppressAutoSave = true;

    addedOnSnap = false;
  }

  @action
  resetInstagramAdd() {
    // Avoid repeated calls for each field
    _suppressAutoSave = false;
    dateAddedOnInsta = DateTime.now();
    _suppressAutoSave = true;

    addedOnInsta = false;
  }

  @action
  resetDiscordAdd() {
    // Avoid repeated calls for each field
    _suppressAutoSave = false;
    dateAddedOnDiscord = DateTime.now();
    _suppressAutoSave = true;

    addedOnDiscord = false;
  }

  _ContactEntry({
    required this.name,
    required this.age,
    required this.ocr,
    required this.imagePath,

    /// If this exists it will be accounted for from the beginning and shouldn't need to be updated
    // this.extractedText,
    this.addedOnSnap = false,
    this.addedOnInsta = false,
    this.addedOnDiscord = false,
    this.snapUsername,
    this.instaUsername,
    this.discordUsername,
    this.dateAddedOnSnap,
    this.dateAddedOnInsta,
    this.dateAddedOnDiscord,
    this.previousHandles,
    this.notes,
    // this.sections,
    // this.socialMediaHandles,
    // this.location,
  }) {
    this.previousHandles = ObservableMap.of(previousHandles ?? {});
    // this.sections = ObservableList.of(sections ?? []);
  }
}
