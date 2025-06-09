import 'package:path/path.dart' as path;

import '../models/contactEntry.dart';

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
}
