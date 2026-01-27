# Cloud Sync Notes

- Cloud flushes are enqueued via Workmanager (lib/utils/background_tasks.dart). Each enqueue sets a pending-flush timestamp in SharedPreferences so the app knows a Drive upload is still in flight.
- On app launch, CloudUtils.firstSignIn() defers getCloudJson() while that isCloudFlushPending() flag is true to avoid importing stale Drive JSON after a quick relaunch.
- When the Workmanager task finishes (success or failure), it clears the flag via CloudUtils.clearCloudFlushPending(). Only then should we treat Drive as up-to-date and run the mismatch/merge logic.
- Future multi-device "cloud is source of truth" work will need per-entry versioning/conflict resolution, but this marker-based protection should remain in place so quick relaunches don’t overwrite newer local edits with old cloud data.
