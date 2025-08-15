# PhotoWordFind
Flutter app for finding pictures that contain a searched word in a group of photos

## Overview (Legacy vs New UI)
The project now ships with two gallery experiences that can be switched live at runtime:

- Legacy UI ("classic") – the original directory‑driven workflow with explicit Find / Display operations and a ProgressDialog overlay.
- New Experimental UI – a modern, card/page based gallery fed from persisted ContactEntry objects, with incremental search, filtering, state tags, and pull‑to‑refresh for cloud sync.

A single flattened `MaterialApp` (see `MyRootWidget` in `main.dart`) hosts both. A SharedPreferences flag (`use_new_ui_candidate`) records the chosen UI. Switching can be initiated from:

1. The AppBar swap icon in either UI.
2. The Settings screen toggle (Interface section) in the new UI.

Both triggers present a confirmation dialog and then call `UiMode.switchTo(bool useNew)`, which updates the preference and tells the root widget to rebuild immediately. Because the rebuild disposes the *previous* screen tree, any dialog / async callback must avoid using a stale `BuildContext` after switching (all recent dialogs now pop using their *dialog* context to prevent exceptions).

## Current Architecture
| Layer | Purpose | Key Artifacts |
|-------|---------|---------------|
| Root Shell | Single `MaterialApp` with dynamic `home` choosing legacy or new UI | `MyRootWidget`, `UiMode` |
| Legacy Utility Shell | Static services used only by legacy UI (progress, gallery mutation) | `LegacyAppShell` (replaces old nested `MyApp`) |
| Data Persistence | Contact entries + metadata | Hive / `StorageUtils` + `ContactEntry` |
| Preferences | Lightweight flags & last state / directory | `SharedPreferences` (`use_new_ui_candidate`, `_last_selected_state`, import dir) |
| Cloud Sync | Google Drive JSON backup | `CloudUtils` (`getCloudJson`, `updateCloudJson`, `firstSignIn`) |
| OCR & AI | Text extraction + enrichment | Local OCR (tesseract‐based) + `ChatGPTService` + `postProcessChatGptResult` |
| Search | Unified token string for fast filtering | `SearchService.searchEntriesWithOcr` |
| UI State Tags | Semantic grouping of images / contacts | Directory names → state strings (Buzz buzz, Honey, Strings, Stale, Comb) |

### Flattened App (Removal of Nested MaterialApp)
Earlier versions instantiated a second `MaterialApp` inside a legacy `MyApp` widget. This caused theme / navigator duplication and dialog context issues. The refactor removed the wrapper; `LegacyAppShell` now exposes only static utilities (`ProgressDialog`, `gallery`, `updateFrame`) and `updateFrame` is nullable to avoid early calls when the legacy UI has not yet built.

### Progress & Frame Updates
- Legacy UI: Relies on a global `ProgressDialog` via `LegacyAppShell.pr` and callback updates (`LegacyAppShell.updateFrame?.call`).
- New UI: Avoids global progress dialog; instead uses local SnackBars, pull‑to‑refresh indicators, and (optionally) `CloudUtils.progressCallback` for cloud operations. If needed, a thin adapter can map that callback into a `SnackBar` / inline banner.

### Cloud Sync Workflow
1. On startup `initializeApp()` triggers `CloudUtils.firstSignIn()` which attempts sign‑in and downloads the Drive JSON file (contains serialized contact data / file path map for the experimental UI).
2. `CloudUtils.getCloudJson()` merges remote JSON into local Hive via `StorageUtils.merge` then (optionally) triggers a UI refresh through `LegacyAppShell.updateFrame?.call` (no‑op if legacy UI not mounted).
3. Manual sync (`_forceSync` in new UI) calls `updateCloudJson()` with a timeout, surfaces status via SnackBars, and stamps `_lastSyncTime` for display in Settings.

### Reserved Preference Keys & Migration
`StorageUtils.migrateSharedPrefsToHive` filters out reserved preference keys (e.g., `use_new_ui_candidate`) so preferences are not misinterpreted as contact entries. Add any new internal preference keys to the reserved list when introducing them.

### Search vs Legacy Find
The legacy **Find** operation runs OCR across a directory only when invoked, while the new UI:
- Continuously maintains a searchable index (filename, identifier, handles, extracted text, prior OCR fields) through `SearchService`.
- Ensures missing OCR content is lazily populated when a search term first references an entry without cached text.

### State Tags
Original folder names are mapped to a `state` field (e.g., "Buzz buzz", "Honey", "Strings", "Stale", "Comb"). The UI filter in the new gallery lets users view subsets by these tags; the last chosen tag persists across sessions.

### Live UI Switching Caveats
- Do not hold references to widgets across a switch.
- Avoid using a dialog's parent screen context after the switch; always `Navigator.pop(dialogCtx, result)` using the builder's `dialogCtx`.
- Global mutable singletons (e.g. progress dialog) must be reinitialized with a fresh context after switching; the code now recreates the ProgressDialog on legacy init and null‑checks it elsewhere.

### Adding New Cross‑UI Features
1. Add pure functionality inside `utils/` or a new service class.
2. Expose optional progress through `CloudUtils.progressCallback` / a new callback rather than invoking UI elements directly.
3. Have each UI decide how (or whether) to surface progress.

### Testing Considerations
- Widget tests that open dialogs from the new gallery require consistent use of the root navigator; ensure `navigatorKey` is passed from `MyRootWidget` only (avoid multiple `MaterialApp`s to keep semantics stable).
- When writing tests that flip UI modes, set the preference (`use_new_ui_candidate`) before pumping `MyRootWidget` to start directly in a target UI for speed.

### Future Enhancements (Complement to Todos)
- Unified progress surface bridging both UIs (in-app banner service rather than dialog).
- Incremental background OCR for newly imported images (update index without manual refresh).
- Replace global statics (`LegacyAppShell`) with a scoped provider once migration from legacy UI nears completion.
- Drive delta sync (upload only changed records, download only diff) to reduce bandwidth.

## Dual UI Switching Quick Reference
Action | Where | Result
------ | ----- | ------
Swap icon | Legacy & New AppBars | Immediate confirmation then mode flip
Settings toggle | New UI > Settings > Interface | Confirmation then mode flip
Programmatic | `await UiMode.switchTo(true/false);` | Persists preference & rebuilds root

If you introduce another UI, extend `UiMode` or add an enum; for now the boolean flag keeps code simple.

## Search
The experimental gallery uses a new `SearchService` which builds a search string from each entry's filename, identifier, usernames, social media handles, and extracted text (from either `extractedText` or older `ocr` fields). Typing in the search box filters the gallery using this service. When a search term is entered, any entry missing extracted text is automatically processed through the OCR service so its content can be searched next time.

## Features
- Sorting by name, date or file size
- Filtering by stored state tag (migrated from the image's original folder name)
- Searching filenames, usernames and extracted text
- Long-press selection of entries with a contextual action menu
- Tap an image tile to view it full size and read all extracted text
- The gallery remembers your last selected state filter across sessions
- A counter shows which image is currently visible out of the filtered list
- Quick actions to open Snapchat/Instagram/Discord profiles and mark them as unfriended with a timestamped note
- Separate flows for quick unfriending when there's no response versus when a chat went poorly

The app can't confirm whether a friend request was ever accepted. When removing someone you may also need to clear the "added" flag for that platform so the username can be reused later.

### Todos
- [ ] Add photos to gallery in batches (requires async functionality)
- [ ] Switch ChatGPT requests in the new UI from sequential to asynchronous so each request starts immediately; the app's ChatGPT service handles rate limiting
- [x] Minimize code into services approach
- [x] Give selection text background color and highlight color
- [ ] Change Snap detection to checking all text on one line
- [x] Create GalleryCell object
- [x] Save original image used in GalleryCell object inside the object so that it can be used when `redoing` and the image doesn't get reloaded/re-adjusted
- [ ] Test closing details dialog opened from popup menu (blocked by failing widget tests)
- [ ] Update minimum Flutter version supported by the app to include the patch that prevents focus loss when toggling Android voice input
- [ ] Fix the directory/state name typo "Strings" to be "Stings" and update any references

## Find Operation
The legacy interface includes a **Find** command which scans a directory of images using OCR. The logic lives in `lib/utils/operations_utils.dart` and processes each file through `ocrParallel`, adding results to the gallery once text extraction is finished. The new interface does not yet trigger this operation directly.

## Shared Debug Keystore
To avoid Android uninstalling the app when switching development machines, all builds are signed with the same debug keystore. Copy the team's keystore to `android/app/debug.keystore` before running the app so installations from different PCs share the same signature.

### Retrieving the keystore
The debug keystore is stored in Firebase Functions config as a Base64 string so
each machine can retrieve the same signing key. You must be authenticated with
the Firebase CLI and have access to the `photowordfind.keystore` config value.

Fetch the file with:
```bash
firebase functions:config:get photowordfind.keystore --project=pwfapp-f314d \
  | tr -d '"' | base64 --decode > android/app/debug.keystore
```

The `scripts/bootstrap.ps1` script installs the Firebase CLI using `winget`,
signs in, downloads the keystore from this config value, and registers its
fingerprint with Firebase automatically on Windows.

### Recommended storage
Keep the keystore in your Firebase project's function config so it can be
fetched securely from any development machine. Avoid copying the raw file
between PCs; instead rely on the commands above or the bootstrap script.

## Bootstrap setup
On Windows, run the included PowerShell script to install the Firebase CLI via
`winget` and the required JDK before retrieving the debug keystore. Set the
execution policy for the current process and then run the script with
`-ExecutionPolicy Bypass -File`:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
powershell -ExecutionPolicy Bypass -File ./scripts/bootstrap.ps1
```

The script installs Eclipse Temurin JDK 17 and Android Studio via `winget`,
refreshing the current `PATH` after each installation so new commands are
available immediately. Android platform-tools are installed as well so `adb`
works without extra steps. The JDK location is persisted in `PWF_JAVA_HOME` and
prepended to your user `PATH` without affecting other JDK versions. The script
creates a `.jdk` junction in the repository root pointing to this path and
`android/gradle.properties` always contains `org.gradle.java.home=../.jdk`, so
Gradle can locate the JDK without modifying the file per-machine. Every
Firebase CLI command includes `--project=pwfapp-f314d`, so no `firebase use`
state is required. It prints progress messages for each step—including when
downloading the keystore, parsing the Firebase Functions config value and
registering the SHA‑1 fingerprint with Firebase app
`1:1082599556322:android:66fb03c1d8192758440abb` if missing—and finally writes a
`.bootstrap_complete` file in the repository root and opens the Windows Developer
Mode settings for convenience. Because Gradle executes from the `android`
subdirectory it looks for this flag relative to the parent
directory and runs the script automatically when it is absent.

### Google Sign-In Setup
For Google Sign-In to work, you'll need to create OAuth 2.0 credentials:
1. Visit the [Google Cloud Console](https://console.cloud.google.com/apis/credentials?project=pwfapp-f314d)
2. Create an OAuth 2.0 Client ID for Android with package name `com.example.PhotoWordFind`
3. Add the SHA-1 fingerprint displayed by the bootstrap script
4. Configure the OAuth consent screen if prompted

The bootstrap script provides the exact SHA-1 fingerprint and setup instructions.
