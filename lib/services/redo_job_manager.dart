import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:PhotoWordFind/models/contactEntry.dart';
import 'package:PhotoWordFind/services/chat_gpt_service.dart';
import 'package:PhotoWordFind/utils/chatgpt_post_utils.dart';
import 'package:PhotoWordFind/utils/storage_utils.dart';

enum RedoType { full, crop }

class RedoJob {
  final String id;
  final ContactEntry entry;
  final File imageFile; // original or cropped temp
  final bool allowNameAgeUpdate;
  final RedoType type;
  final DateTime enqueuedAt;

  RedoJob({
    required this.id,
    required this.entry,
    required this.imageFile,
    required this.allowNameAgeUpdate,
    required this.type,
    DateTime? enqueuedAt,
  }) : enqueuedAt = enqueuedAt ?? DateTime.now();
}

class RedoJobStatus {
  final bool processing;
  final double? progress; // reserved for future use
  final String? message;
  const RedoJobStatus({required this.processing, this.progress, this.message});

  RedoJobStatus copyWith({bool? processing, double? progress, String? message}) =>
      RedoJobStatus(
        processing: processing ?? this.processing,
        progress: progress ?? this.progress,
        message: message ?? this.message,
      );
}

class RedoJobManager {
  RedoJobManager._internal();
  static final RedoJobManager instance = RedoJobManager._internal();

  // Map of entry.identifier -> status
  final ValueNotifier<Map<String, RedoJobStatus>> statuses = ValueNotifier({});
  // Global summary for quick UI indicator
  final ValueNotifier<RedoJobsSummary> summary =
      ValueNotifier<RedoJobsSummary>(const RedoJobsSummary(active: 0, queued: 0, failed: 0));

  final List<RedoJob> _queue = <RedoJob>[];
  int _inFlight = 0;
  int maxConcurrent = 2;
  // Track entries already active or queued to dedupe
  final Set<String> _activeOrQueuedIds = <String>{};
  // Remember last job per entry for quick retry
  final Map<String, RedoJob> _lastJobs = <String, RedoJob>{};

  bool isProcessing(String identifier) {
    return statuses.value[identifier]?.processing == true;
  }

  void _setStatus(String identifier, RedoJobStatus status) {
    final map = Map<String, RedoJobStatus>.from(statuses.value);
    map[identifier] = status;
    statuses.value = map;
    _updateSummary();
  }

  void _clearStatus(String identifier) {
    final map = Map<String, RedoJobStatus>.from(statuses.value);
    map.remove(identifier);
    statuses.value = map;
    _updateSummary();
  }

  void enqueueFull({
    required ContactEntry entry,
    required File imageFile,
    bool allowNameAgeUpdate = false,
  }) {
    if (_activeOrQueuedIds.contains(entry.identifier)) {
      // Already queued/processing; no-op to dedupe
      return;
    }
    final job = RedoJob(
      id: '${entry.identifier}-full-${DateTime.now().millisecondsSinceEpoch}',
      entry: entry,
      imageFile: imageFile,
      allowNameAgeUpdate: allowNameAgeUpdate,
      type: RedoType.full,
    );
    _enqueue(job);
  }

  void enqueueCrop({
    required ContactEntry entry,
    required File croppedImageFile,
    bool allowNameAgeUpdate = false,
  }) {
    if (_activeOrQueuedIds.contains(entry.identifier)) {
      // Already queued/processing; no-op to dedupe
      try { if (croppedImageFile.existsSync()) { croppedImageFile.deleteSync(); } } catch (_) {}
      return;
    }
    final job = RedoJob(
      id: '${entry.identifier}-crop-${DateTime.now().millisecondsSinceEpoch}',
      entry: entry,
      imageFile: croppedImageFile,
      allowNameAgeUpdate: allowNameAgeUpdate,
      type: RedoType.crop,
    );
    _enqueue(job);
  }

  void _enqueue(RedoJob job) {
    _queue.add(job);
    _lastJobs[job.entry.identifier] = job;
    _activeOrQueuedIds.add(job.entry.identifier);
    // Mark as queued (not yet processing) so tiles don't show spinner, but summary can show queued count.
    _setStatus(job.entry.identifier, const RedoJobStatus(processing: false, message: 'Queued'));
    _updateSummary();
    _tryStartNext();
  }

  void _tryStartNext() {
    if (_inFlight >= maxConcurrent) return;
    if (_queue.isEmpty) return;

    final job = _queue.removeAt(0);
    _inFlight++;
    // Mark as processing
    _setStatus(job.entry.identifier, const RedoJobStatus(processing: true));

    _process(job).whenComplete(() {
      _inFlight--;
      _tryStartNext();
    });
  }

  Future<void> _process(RedoJob job) async {
    try {
      final response = await ChatGPTService.processImage(imageFile: job.imageFile);
      if (response != null) {
        // Merge safely into entry and save
        postProcessChatGptResult(job.entry, response, save: false, allowNameAgeUpdate: job.allowNameAgeUpdate);
        await StorageUtils.save(job.entry);
      }
    } catch (e) {
      // Keep failure status for UI retry
      _setStatus(job.entry.identifier, RedoJobStatus(processing: false, message: 'Failed'));
      // Do not delete cropped temp on failure; allow retry to reuse it
      return;
    } finally {
      final st = statuses.value[job.entry.identifier];
      final failed = st != null && (st.message?.isNotEmpty ?? false) && st.processing == false;
      if (!failed) {
        // Success path: clear status and cleanup
        _clearStatus(job.entry.identifier);
        if (job.type == RedoType.crop) {
          try { if (job.imageFile.existsSync()) { job.imageFile.deleteSync(); } } catch (_) {}
        }
      }
      // Allow future enqueues
      _activeOrQueuedIds.remove(job.entry.identifier);
      _updateSummary();
    }
  }

  // Retry the last job for an identifier, if known
  void retry(String identifier) {
    final last = _lastJobs[identifier];
    if (last == null) return;
    if (_activeOrQueuedIds.contains(identifier)) return;
    if (last.type == RedoType.full) {
      enqueueFull(
        entry: last.entry,
        imageFile: File(last.entry.imagePath),
        allowNameAgeUpdate: last.allowNameAgeUpdate,
      );
    } else {
      // Ensure the cropped file still exists; if not, give up silently
      if (last.imageFile.existsSync()) {
        enqueueCrop(
          entry: last.entry,
          croppedImageFile: last.imageFile,
          allowNameAgeUpdate: last.allowNameAgeUpdate,
        );
      }
    }
  }

  void _updateSummary() {
  final failed = statuses.value.values.where((s) => !s.processing && (s.message == 'Failed')).length;
    summary.value = RedoJobsSummary(active: _inFlight, queued: _queue.length, failed: failed);
  }
}

class RedoJobsSummary {
  final int active;
  final int queued;
  final int failed;
  const RedoJobsSummary({required this.active, required this.queued, required this.failed});
}
