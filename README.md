# PhotoWordFind
Flutter app for finding pictures that contain a searched word in a group of photos

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
prepended to your user `PATH` without affecting other JDK versions. The
path is written to `android/gradle.properties` as `org.gradle.java.home` using
escaped Windows separators so Gradle can locate the JDK automatically. Every
Firebase CLI command includes `--project=pwfapp-f314d`, so no `firebase use`
state is required. It prints progress messages for each step—including when
downloading the keystore, parsing the Firebase Functions config value and
registering the SHA‑1 fingerprint with Firebase app
`1:1082599556322:android:66fb03c1d8192758440abb` if missing—and finally writes a
`.bootstrap_complete` file in the repository root and opens the Windows Developer
Mode settings for convenience. Because Gradle executes from the `android`
subdirectory it looks for this flag relative to the parent
directory and runs the script automatically when it is absent.
