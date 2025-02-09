import 'dart:io';

import 'package:PhotoWordFind/models/location.dart';
import 'package:PhotoWordFind/utils/storage_utils.dart';

class ContactEntry {
  final String identifier;
  final String imagePath;
  final DateTime dateFound;
  String extractedText;
  String? snapUsername;
  String? instaUsername;
  String? discordUsername;
  DateTime? dateAddedOnSnap;
  DateTime? dateAddedOnInsta;
  DateTime? dateAddedOnDiscord;
  bool addedOnSnap;
  bool addedOnInsta;
  bool addedOnDiscord;
  Map<String, List<String>>? previousHandles;
  String? notes;
  // New chatGPT responses
  Map<String, String>? socialMediaHandles;
  List<Map<String, String>>? sections;
  final String name;
  final int? age;
  final Location? location;

  ContactEntry({
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
  });

  factory ContactEntry.fromJson(String storageKey, String imagePath, Map<String, dynamic> json) {
    Map<String, dynamic> map = {
      SubKeys.Location: json[SubKeys.Location],
    };
    return ContactEntry(
      imagePath: imagePath,
      extractedText: json[SubKeys.OCR] ?? json.toString(),
      identifier: storageKey,
      dateFound: File(imagePath).lastModifiedSync(),
      name: json[SubKeys.Name],
      age: json[SubKeys.Age],
      location: Location(
          rawLocation: json[SubKeys.Location]['name'],
          timezone: json[SubKeys.Location]['timezone'] as String?),
      // socialMediaHandles: json[SubKeys.SocialMediaHandles],
      snapUsername: json[SubKeys.SnapUsername],
      instaUsername: json[SubKeys.InstaUsername],
      discordUsername: json[SubKeys.DiscordUsername],
      dateAddedOnSnap: json[SubKeys.SnapDate] != null && json[SubKeys.SnapDate].isNotEmpty 
        ? DateTime.parse(json[SubKeys.SnapDate]) : null,
      dateAddedOnInsta: json[SubKeys.InstaDate] != null && json[SubKeys.InstaDate].isNotEmpty 
        ? DateTime.parse(json[SubKeys.InstaDate]) : null,
      dateAddedOnDiscord: json[SubKeys.DiscordDate] != null && json[SubKeys.DiscordDate].isNotEmpty 
        ? DateTime.parse(json[SubKeys.DiscordDate]) : null,
      addedOnSnap: json[SubKeys.AddedOnSnap] ?? false,
      addedOnInsta: json[SubKeys.AddedOnInsta] ?? false,
      addedOnDiscord: json[SubKeys.AddedOnDiscord] ?? false,
      previousHandles: (json[SubKeys.PreviousUsernames] as Map<String,dynamic>?)?.cast<String, List<String>>() ??
          <String, List<String>>{
            SubKeys.SnapUsername: <String>[],
            SubKeys.InstaUsername: <String>[],
          },
      notes: json[SubKeys.Notes],
      // sections: json[SubKeys.Sections],

    );
  }
}
