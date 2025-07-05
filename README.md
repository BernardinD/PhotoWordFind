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
1. Request access to the private file share or repository containing `debug.keystore.enc` from a project maintainer.
2. Download the encrypted file and decrypt it with:
   ```bash
   gpg --decrypt debug.keystore.enc > android/app/debug.keystore
   ```
   The passphrase is stored in the team password manager.
3. Verify the file's checksum if one is provided.

### Recommended storage
Keep the encrypted keystore in a private location that supports access controls and versioning (for example a private Git repository or internal cloud storage bucket). Avoid emailing or directly copying the raw file between machines. Instead, share the encrypted file and passphrase separately using a password manager.
