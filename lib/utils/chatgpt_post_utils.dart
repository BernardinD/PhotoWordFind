import 'package:flutter/foundation.dart';
import 'package:PhotoWordFind/models/contactEntry.dart';
import 'package:PhotoWordFind/utils/storage_utils.dart';
import 'package:timezone/timezone.dart' as tz;

/// Applies post-processing to the ChatGPT [response] before merging it
/// into [entry]. This avoids overwriting sensitive information and ensures
/// new sections are appended without duplication.
ContactEntry postProcessChatGptResult(
  ContactEntry entry, Map<String, dynamic> response,
  {bool save = true, bool allowNameAgeUpdate = false}) {
  // Avoid overriding an existing location
  if (entry.location != null && response[SubKeys.Location] != null) {
    response.remove(SubKeys.Location);
  }

  // Validate timezone identifier if present
  if (response[SubKeys.Location] is Map) {
    try {
      tz.getLocation(response[SubKeys.Location]["timezone"]);
    } catch (e) {
      debugPrint(
          '❌ Failed to validate time zone: ${response[SubKeys.Location]["timezone"]}');
      throw '❌ Message: $e';
    }
  }

  // Merge sections if both contain data
  if (entry.sections != null && response[SubKeys.Sections] != null) {
    List<Map<String, String>> originalSections = entry.sections!
        .map((item) => Map<String, String>.from(item as Map))
        .toList();
    List<Map<String, String>> newSections = (response[SubKeys.Sections] as List)
        .map((item) => Map<String, String>.from(item as Map))
        .toList();

    for (var newSection in newSections) {
      originalSections.removeWhere(
          (originalSection) => originalSection['title'] == newSection['title']);
    }

    response[SubKeys.Sections].addAll(originalSections);
  }

  // If this isn't a new import, don't let post-processing overwrite name/age
  // unless a one-time override is explicitly allowed (e.g., from Redo OCR).
  if (entry.isNewImport != true && allowNameAgeUpdate != true) {
    response.remove(SubKeys.Name);
    response.remove(SubKeys.Age);
  }

  entry.mergeFromJson(response, save);
  return entry;
}
