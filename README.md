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
- Sleek, card-based control bar adapts its height with the screen and keeps search,
  filter and sorting tools neatly arranged

### Todos
- [ ] Add photos to gallery in batches (requires async functionality)
- [x] Minimize code into services approach
- [x] Give selection text background color and highlight color
- [ ] Change Snap detection to checking all text on one line
- [x] Create GalleryCell object
- [x] Save original image used in GalleryCell object inside the object so that it can be used when `redoing` and the image doesn't get reloaded/re-adjusted
- [ ] Test closing details dialog opened from popup menu (blocked by failing widget tests)

## Find Operation
The legacy interface includes a **Find** command which scans a directory of images using OCR. The logic lives in `lib/utils/operations_utils.dart` and processes each file through `ocrParallel`, adding results to the gallery once text extraction is finished. The new interface does not yet trigger this operation directly.
