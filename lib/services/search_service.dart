import 'dart:io';

import 'package:path/path.dart' as path;

import '../models/contactEntry.dart';
import 'chat_gpt_service.dart';

class SearchService {
  /// Returns a list of entries that match the [query].
  ///
  /// The search is performed over several fields including the filename,
  /// identifier, usernames, social media handles and the extracted text.
  static List<ContactEntry> searchEntries(
      List<ContactEntry> entries, String query) {
    if (query.isEmpty) return List<ContactEntry>.from(entries);
    final q = query.toLowerCase();

    return entries.where((entry) {
      final buffer = StringBuffer();

      // Filename
      buffer.write(path.basename(entry.imagePath));
      buffer.write(' ');

      // Identifier
      buffer.write(entry.identifier);
      buffer.write(' ');

      // Usernames
      if (entry.snapUsername != null) buffer.write('${entry.snapUsername} ');
      if (entry.instaUsername != null) buffer.write('${entry.instaUsername} ');
      if (entry.discordUsername != null)
        buffer.write('${entry.discordUsername} ');

      // Social media handles values
      if (entry.socialMediaHandles != null) {
        for (final value in entry.socialMediaHandles!.values) {
          if (value != null && value.isNotEmpty) {
            buffer.write('$value ');
          }
        }
      }

      // Extracted text or OCR
      final text = entry.extractedText ?? entry.ocr;
      if (text != null) buffer.write(text);

      final searchTarget = buffer.toString().toLowerCase();
      return searchTarget.contains(q);
    }).toList();
  }

  /// Ensures entries have OCR/extracted text before searching. Any entry
  /// missing both `extractedText` and `ocr` will be processed via
  /// [ChatGPTService.processImage]. The returned list is filtered using
  /// [searchEntries].
  static Future<List<ContactEntry>> searchEntriesWithOcr(
      List<ContactEntry> entries, String query) async {
    for (final entry in entries) {
      if (query.isNotEmpty && entry.extractedText == null && entry.ocr == null) {
        final result =
            await ChatGPTService.processImage(imageFile: File(entry.imagePath));
        if (result != null) {
          entry.mergeFromJson(result, true);
        }
      }
    }
    return searchEntries(entries, query);
  }
}
