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
The debug keystore is stored in Google Secret Manager so that every machine can
use the same signing key. You must be authenticated with the Google Cloud SDK
and have access to the `photowordfind-debug-keystore` secret.

Fetch the file with:
```bash
gcloud secrets versions access latest --secret=photowordfind-debug-keystore \
  > android/app/debug.keystore
```

The `scripts/bootstrap.ps1` script installs `gcloud`, signs in to your Google
account, downloads the keystore, and registers its fingerprint with Firebase
automatically on Windows.

### Recommended storage
Keep the keystore in Secret Manager so it can be fetched securely from any
development machine. Avoid copying the raw file between PCs; instead rely on the
commands above or the bootstrap script.

## Bootstrap setup
On Windows, run the included PowerShell script to install the Google Cloud SDK
and required JDK before retrieving the debug keystore. You must pass
`-ExecutionPolicy Bypass -File` so PowerShell allows the script to run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\bootstrap.ps1
```

The script sets the project to `pwfapp-f314d`, ensures Eclipse Temurin JDK 17 is
installed and makes its path persistent for future terminals without altering
existing JDK setups. The JDK location is stored in the `PWF_JAVA_HOME`
environment variable and added to your user `PATH`. The current session's
`JAVA_HOME` is set accordingly so Gradle can find `keytool`. It then registers the keystore's SHA‑1
fingerprint with the Firebase app
`1:1082599556322:android:66fb03c1d8192758440abb` if it has not already been
added. It also writes a `.bootstrap_complete` file in the project root. The
Android build checks for this file and runs the script automatically when
missing.
