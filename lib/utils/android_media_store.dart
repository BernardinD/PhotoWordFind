import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';

/// Android-only helpers for interacting with MediaStore so the system Gallery
/// reflects changes (moves) immediately. On non-Android platforms these
/// methods are no-ops and return null.
class AndroidMediaStoreHelper {
  /// Moves an existing image at [srcAbsPath] into the album/folder represented
  /// by [destAbsDir] using MediaStore insert semantics. Returns the new
  /// absolute file path if successful, or null on failure.
  ///
  /// Strategy:
  /// - Request PhotoManager permission.
  /// - Save the existing file into MediaStore with a [relativePath]
  ///   derived from [destAbsDir]. This creates a new asset visible to Gallery.
  /// - If that succeeds, delete the original file and return the new path.
  static Future<String?> moveImageTo(String srcAbsPath, String destAbsDir) async {
    if (!Platform.isAndroid) return null;

    try {
      final ps = await PhotoManager.requestPermissionExtend();
      if (!ps.isAuth) return null;

      final String fileName = p.basename(srcAbsPath);
      final String relativePath = _toRelativePath(destAbsDir);

      // Save into target album without re-encoding by using the path variant.
  final entity = await PhotoManager.editor.saveImageWithPath(
        srcAbsPath,
        title: fileName,
        relativePath: relativePath,
      );

      final newFile = await entity.file;
      if (newFile == null) return null;

      // Best-effort deletion of the source file after successful import.
      try {
        final src = File(srcAbsPath);
        if (await src.exists()) {
          await src.delete();
        }
      } catch (e) {
        debugPrint('AndroidMediaStoreHelper: failed deleting original: $e');
      }

      return newFile.path;
    } catch (e, s) {
      debugPrint('AndroidMediaStoreHelper.moveImageTo error: $e\n$s');
      return null;
    }
  }

  /// Convert an absolute directory like `/storage/emulated/0/DCIM/Comb`
  /// to a MediaStore relative path like `DCIM/Comb`.
  static String _toRelativePath(String destAbsDir) {
    // Common primary external storage root.
    const candidates = [
      '/storage/emulated/0/',
      '/sdcard/',
    ];
  for (final root in candidates) {
      if (destAbsDir.startsWith(root)) {
    return destAbsDir.substring(root.length).replaceAll('\\', '/');
      }
    }
    // Fallback: strip leading slash if present.
  return destAbsDir.replaceFirst(RegExp(r'^/'), '').replaceAll('\\', '/');
  }
}
