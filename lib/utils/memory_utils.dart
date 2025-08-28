import 'package:flutter/painting.dart';

/// Small helpers to reduce memory pressure without changing visuals.
class MemoryUtils {
  /// Clears decoded image caches. Safe to call on pause/background.
  static void trimImageCaches() {
    try {
      final cache = PaintingBinding.instance.imageCache;
      cache.clear();
      cache.clearLiveImages();
    } catch (_) {
      // No-op if binding not ready.
    }
  }
}
