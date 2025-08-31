import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_scanner/media_scanner.dart' as ms;

class MediaScanUtils {
  /// Ask Android's MediaScanner to scan [paths]. No-op on non-Android.
  static Future<void> scanPaths(Iterable<String> paths) async {
    if (!Platform.isAndroid) return;
    try {
      for (final p in paths) {
        await ms.MediaScanner.loadMedia(path: p);
      }
    } catch (e, s) {
      debugPrint('MediaScanUtils.scanPaths error: $e\n$s');
    }
  }
}
