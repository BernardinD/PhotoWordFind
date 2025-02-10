import 'dart:io';
import 'package:mobx/mobx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:PhotoWordFind/models/location.dart';
import 'package:PhotoWordFind/utils/storage_utils.dart';

part 'contactEntry.g.dart';

class ContactEntry = _ContactEntry with _$ContactEntry;

class _ContactEntry with Store {
  final String identifier;
  final String imagePath;
  final DateTime dateFound;

  @observable
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
  bool addedOnSnap;

  @observable
  bool addedOnInsta;

  @observable
  bool addedOnDiscord;

  @observable
  ObservableMap<String, List<String>>? previousHandles;

  @observable
  String? notes;

  // New chatGPT responses
  @observable
  ObservableMap<String, String>? socialMediaHandles;

  @observable
  ObservableList<Map<String, String>>? sections;

  final String? name;
  final int? age;
  final Location? location;

  _ContactEntry({
    required this.identifier,
    required this.imagePath,
    required this.extractedText,
    required this.dateFound,
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
    _setupAutoSave();
  }

  void _setupAutoSave() {
    reaction((_) => toJson(), (_) => _saveToPreferences());
  }

  Map<String, dynamic> toJson() {
    return {
      "identifier": identifier,
      "imagePath": imagePath,
      "dateFound": dateFound.toIso8601String(),
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
      "previousHandles": previousHandles != null ? Map.from(previousHandles!) : null,
      "notes": notes,
      "socialMediaHandles": socialMediaHandles,
      "sections": sections,
      "name": name,
      "age": age,
      "location": location?.toJson(),
    };
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
    return ContactEntry.fromJson(identifier, "", json);
  }

  factory _ContactEntry.fromJson(
      String storageKey, String imagePath, Map<String, dynamic> json) {
    return ContactEntry(
      identifier: storageKey,
      imagePath: imagePath,
      extractedText: json[SubKeys.OCR] ?? json.toString(),
      dateFound: File(imagePath).lastModifiedSync(),
      name: json[SubKeys.Name],
      age: json[SubKeys.Age],
      location: json[SubKeys.Location] != null
          ? Location(
              rawLocation: json[SubKeys.Location]['name'],
              timezone: json[SubKeys.Location]['timezone'] as String?,
            )
          : null,
      snapUsername: json[SubKeys.SnapUsername],
      instaUsername: json[SubKeys.InstaUsername],
      discordUsername: json[SubKeys.DiscordUsername],
      dateAddedOnSnap:
          json[SubKeys.SnapDate] != null && json[SubKeys.SnapDate].isNotEmpty
              ? DateTime.parse(json[SubKeys.SnapDate])
              : null,
      dateAddedOnInsta:
          json[SubKeys.InstaDate] != null && json[SubKeys.InstaDate].isNotEmpty
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
                (key, value) => MapEntry(key, List<String>.from(value)),
              ) ??
              <String, List<String>>{
                SubKeys.SnapUsername: <String>[],
                SubKeys.InstaUsername: <String>[],
              }),
      notes: json[SubKeys.Notes],
      socialMediaHandles:
          ObservableMap.of(json[SubKeys.SocialMediaHandles] ?? {}),
      sections: ObservableList.of(json[SubKeys.Sections] ?? []),
    );
  }
}
