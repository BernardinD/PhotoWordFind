import 'package:flutter/foundation.dart';
import 'package:PhotoWordFind/models/contactEntry.dart';
import 'package:PhotoWordFind/utils/storage_utils.dart';
import 'package:timezone/timezone.dart' as tz;

/// Remove an incoming handle update for a platform if the existing handle has
/// already been verified.
///
/// This sanitizes [response] by removing:
/// - the top-level [handleKey] (e.g., SubKeys.SnapUsername), and
/// - the same key within the nested SocialMediaHandles map (if present).
///
/// No-op when [isVerified] is false.
void stripVerifiedHandle({
  required Map<String, dynamic> response,
  required String handleKey,
  required bool isVerified,
}) {
  if (!isVerified) return;
  response.remove(handleKey);
  final sm = response[SubKeys.SocialMediaHandles];
  if (sm is Map) {
    sm.remove(handleKey);
  }
}

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

  // Do not overwrite verified handles. If a platform has been verified, strip
  // any incoming username for that platform from both the top-level keys and
  // from the aggregated SocialMediaHandles map.
  stripVerifiedHandle(
    response: response,
    handleKey: SubKeys.SnapUsername,
    isVerified: entry.verifiedOnSnapAt != null,
  );
  stripVerifiedHandle(
    response: response,
    handleKey: SubKeys.InstaUsername,
    isVerified: entry.verifiedOnInstaAt != null,
  );
  stripVerifiedHandle(
    response: response,
    handleKey: SubKeys.DiscordUsername,
    isVerified: entry.verifiedOnDiscordAt != null,
  );

  entry.mergeFromJson(response, save);
  return entry;
}
