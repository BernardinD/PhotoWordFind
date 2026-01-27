import 'dart:io';

import 'package:PhotoWordFind/utils/cloud_utils.dart';
import 'package:PhotoWordFind/utils/storage_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

const String kCloudFlushTask = 'cloud_flush_now';

/// Initializes background task handling (Android only).
Future<void> initBackgroundTasks() async {
  if (!Platform.isAndroid) return;
  try {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: !kReleaseMode,
    );
    debugPrint('[bg-task] Workmanager initialized');
  } catch (e, s) {
    debugPrint('Workmanager init failed: $e\n$s');
  }
}

/// Schedules a one-off cloud flush in the background (Android only).
Future<void> enqueueCloudFlushTask() async {
  if (!Platform.isAndroid) return;
  try {
    await Workmanager().registerOneOffTask(
      kCloudFlushTask,
      kCloudFlushTask,
      existingWorkPolicy: ExistingWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.connected),
    );
    debugPrint('[bg-task] enqueued cloud flush');
  } catch (e, s) {
    debugPrint('Failed to enqueue cloud flush task: $e\n$s');
  }
}

/// Entry point for background tasks. Annotated to survive tree-shaking.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    debugPrint('[bg-task] start task: $task');
    if (task == kCloudFlushTask) {
      try {
        await StorageUtils.init();
        final signedIn = await CloudUtils.isSignedin();
        debugPrint('[bg-task] signed in: $signedIn');
        if (!signedIn) {
          debugPrint(
              '[bg-task] skipping cloud flush because account is signed out.');
          return true;
        }
        await CloudUtils.updateCloudJson();
        debugPrint('[bg-task] cloud flush success');
        return true;
      } catch (e, s) {
        debugPrint('Cloud flush task failed: $e\n$s');
        return false;
      }
    }
    debugPrint('[bg-task] task ignored: $task');
    return true;
  });
}
