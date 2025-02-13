import 'dart:io';
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

class ContactEntry extends _ContactEntry with _$ContactEntry {
  ContactEntry(
      {required this.identifier,
      required this.imagePath,
      required this.dateFound,
      required Map<String, dynamic> json})
      : super(
          extractedText: json[SubKeys.OCR] ?? json.toString(),
          name: json[SubKeys.Name],
          age: json[SubKeys.Age] is int ? json[SubKeys.Age] : null,
          location: json[SubKeys.Location] != null
              ? Location(
                  rawLocation: json[SubKeys.Location]['name'],
                  timezone: json[SubKeys.Location]['timezone'] as String?,
                )
              : null,
          snapUsername: json[SubKeys.SnapUsername],
          instaUsername: json[SubKeys.InstaUsername],
          discordUsername: json[SubKeys.DiscordUsername],
          dateAddedOnSnap: json[SubKeys.SnapDate] != null &&
                  json[SubKeys.SnapDate].isNotEmpty
              ? DateTime.parse(json[SubKeys.SnapDate])
              : null,
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
                        key,
                        ObservableList<String>.of(
                            (value as List<dynamic>).cast<String>())),
                  ) ??
                  <String, ObservableList<String>>{
                    SubKeys.SnapUsername: ObservableList<String>(),
                    SubKeys.InstaUsername: ObservableList<String>(),
                  }),
          notes: json[SubKeys.Notes],
          socialMediaHandles: ObservableMap.of(
              (json[SubKeys.SocialMediaHandles] as Map<String, dynamic>?)
                      ?.map((key, value) => MapEntry(key, value as String?)) ??
                  {}),
          sections: ObservableList.of((json[SubKeys.Sections] as List<dynamic>?)
                  ?.map((map) => ObservableMap<String, String>.of(
                      (map as Map<String, dynamic>).cast<String, String>())) ??
              []),
        ) {
    _setupAutoSave();
  }

  @JsonKey(includeFromJson: false)
  final String identifier;
  @JsonKey(includeFromJson: false)
  final String imagePath;
  @JsonKey(includeFromJson: false)
  final DateTime dateFound;

  factory ContactEntry.fromJson(
      String storageKey, String imagePath, Map<String, dynamic> json) {
    return ContactEntry(
        identifier: storageKey,
        imagePath: imagePath,
        dateFound: File(imagePath).lastModifiedSync(),
        json: json);
  }
  void _setupAutoSave() {
    reaction((_) => toJson(), (_) => _saveToPreferences());
  }

  Future<void> _saveToPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(identifier, jsonEncode(toJson()));
  }

  static Future<ContactEntry?> loadFromPreferences(String identifier) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(identifier);
    if (jsonString == null) return null;

    final Map<String, dynamic> json = jsonDecode(jsonString);
    return ContactEntry.fromJson(identifier, identifier, json);
  }
}

abstract class _ContactEntry with Store {
  // _ContactEntry();

  @observable
  @JsonKey(disallowNullValue: true)
  String extractedText;

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
  @JsonKey(disallowNullValue: true)
  bool addedOnSnap;

  @observable
  @JsonKey(disallowNullValue: true)
  bool addedOnInsta;

  @observable
  @JsonKey(disallowNullValue: true)
  bool addedOnDiscord;

  @observable
  @JsonKey(
      fromJson: fromJsonObservableMapOfLists,
      toJson: toJsonObservableMapOfLists)
  ObservableMap<String, ObservableList<String>>? previousHandles;

  @observable
  String? notes;

  // New chatGPT responses
  @JsonKey(required: true, disallowNullValue: true)
  final String? name;

  @JsonKey(required: true, disallowNullValue: true)
  final int? age;

  @JsonKey(required: true, disallowNullValue: true)
  final Location? location;

  @observable
  @JsonKey(
      fromJson: fromJsonObservableMapOfStrings,
      toJson: toJsonObservableMapOfStrings)
  ObservableMap<String, String?>? socialMediaHandles;

  @observable
  @JsonKey(
      fromJson: fromJsonObservableListOfMaps,
      toJson: toJsonObservableListOfMaps)
  ObservableList<ObservableMap<String, String>>? sections;

  _ContactEntry({
    required this.extractedText,
    required this.name,
    required this.age,
    required this.location,
    required this.addedOnSnap,
    required this.addedOnInsta,
    required this.addedOnDiscord,
    this.snapUsername,
    this.instaUsername,
    this.discordUsername,
    this.dateAddedOnSnap,
    this.dateAddedOnInsta,
    this.dateAddedOnDiscord,
    this.previousHandles,
    this.notes,
    this.sections,
    this.socialMediaHandles,
  }) {
    this.previousHandles = ObservableMap.of(previousHandles ?? {});
    this.sections = ObservableList.of(sections ?? []);
  }

  Map<String, dynamic> toJson() {
    return {
      "extractedText": extractedText,
      "snapUsername": snapUsername,
      "instaUsername": instaUsername,
      "discordUsername": discordUsername,
      "dateAddedOnSnap": dateAddedOnSnap?.toIso8601String(),
      "dateAddedOnInsta": dateAddedOnInsta?.toIso8601String(),
      "dateAddedOnDiscord": dateAddedOnDiscord?.toIso8601String(),
      "addedOnSnap": addedOnSnap,
      "addedOnInsta": addedOnInsta,
      "addedOnDiscord": addedOnDiscord,
      "previousHandles":
          previousHandles != null ? Map.from(previousHandles!) : null,
      "notes": notes,
      "socialMediaHandles": socialMediaHandles,
      "sections": sections,
      "name": name,
      "age": age,
      "location": location?.toJson(),
    };
  }
}
