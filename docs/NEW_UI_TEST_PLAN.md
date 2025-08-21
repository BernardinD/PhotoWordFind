# New UI Test Plan

Scope: This document lists smoke, functional, and regression tests to run for the New UI only. Legacy UI is out of scope.

Environments
- Platforms: Android (primary), iOS (sanity), Windows/macOS desktop (optional if supported)
- OS: Android 10+; iOS 14+
- Network: Online and Offline
- Permissions: Storage/Photos granted and denied cases

Test Data and Setup
- Ensure `assets/tessdata/eng.traineddata` is present
- Have a few local images with and without recognizable text
- Prepare at least one image that includes social usernames (snap/insta/discord)
- Cloud account available for sign-in (used by CloudUtils)
- Optional: a dummy directory for import testing

---

## 1) Smoke Suite
- Launch app → New UI is default; no crashes
- Initial loading screen appears; completes to gallery or shows graceful sign-in failure note
- Basic navigation: open Settings and back

## 2) Permissions and First-Run
- Case A: Storage/Photos permission granted
  - App initializes and loads images/preferences without blocking errors
- Case B: Permission denied
  - App surfaces a clear prompt/error; gallery UI remains stable

## 3) Authentication & Cloud Sync (CloudUtils)
- First sign-in flow succeeds; shows no blocking errors
- Pull-to-refresh sync:
  - Online: shows syncing indicator; completes; last sync time updates
  - Offline: shows “No internet connection” toast/snackbar; no crash
- Manual Sign-out from Settings, then Sign-in again
- Sign-in failure: shows non-blocking initialization error text; app usable locally

## 4) Gallery Browsing
- PageView scroll left/right with `viewportFraction=0.8`; indicator shows "n / total"
- Selecting/deselecting tiles via long-press toggles checkmark
- Selected tiles preserve state when paging
- Details dialog opens on tap; PhotoView supports pinch zoom and pan

## 5) Search (SearchService)
- Enter search text; results filter in real-time; clearing query restores list
- Edge cases: empty results; case-insensitivity; partial matches

## 6) Sorting & Filtering (States)
- Sort options:
  - Name, Date found, Size, Snap Added Date, Instagram Added Date, Added on Snapchat, Added on Instagram
- Asc/Desc toggle inverts order consistently
- State filter dropdown:
  - All; and every other discovered state value
  - Selection persists and is applied to the list
- Current page resets to first item after new sort/filter

## 7) Selection Menu: Move
- Select one/multiple images → Menu: Move → Pick a state
- Expected: Entries update their `state` and persist; UI updates; selection clears

## 8) Import Images
- From system album (WeChat Assets Picker):
  - Multi-select photos; grant permissions if prompted
  - Expected: Import completes; snackbar shows count; images appear in gallery
- From directory (File Picker):
  - Choose folder → valid images import; non-images ignored gracefully
- Import directory setting in Settings:
  - Change, Reset to default, and re-import

## 9) Redo OCR (RedoCropScreen)
- Tap redo button on a tile
- Crop overlay screen appears; complete crop/save
- Expected: Text extraction runs; contact fields update; persists via StorageUtils
- Canceling returns without changes

## 10) Notes Dialog
- Open Notes from tile actions; add/edit text; save
- Expected: Notes saved and shown on subsequent open
- Large notes and multiline formatting preserved

## 11) Edit Usernames Dialog
- Open, modify Snapchat/Instagram/Discord usernames; Save with confirmation
- Discard flow prompts when changes exist
- Saved usernames appear on tile; persisted

## 12) Social Actions
- Snap/Instagram icons open external apps/URLs
- Discord button copies username to clipboard and launches Discord app (if installed)
- Quick Unfriend and Unfriend with Note:
  - Prompts for confirmation; opens app/URL; on confirm, appends a note with timestamp
  - Optional custom note appended when chosen

## 13) Settings Screen
- Shows last sync time when available
- Sign in/out works and returns to gallery appropriately
- UI Mode toggle:
  - Switching asks for confirmation; switching to Legacy is allowed but not covered further here

## 14) Persistence
- Last selected state filter persists via SharedPreferences (relaunch app)
- Import directory setting persists
- Selected sort option and order persist if designed to; otherwise no regression

## 15) Error Handling & UX
- No internet on sync: friendly message; no crash
- Sign-in unavailable: initialization shows warning; gallery usable locally
- Missing/invalid image path: tile shows fallback or skips gracefully

## 16) Performance & Stability
- Scrolling/paging is smooth; no jank or dropped frames on mid-range device
- No memory leaks when paging many items; images disposed off-screen
- No I/O on hot rebuild paths (regression check for Sortings cache updates)

## 17) Accessibility (Quick Pass)
- Buttons have tappable touch targets; icons with tooltips/semantics where appropriate
- Color contrast sufficient on overlay labels and buttons

---

# Suggested Automated Tests (Widget/Unit)

Widget Tests
- ImageGallery basic render
  - Given empty list → shows `1 / 0`
  - Given N items → page indicator updates on page change
- Tile selection state toggles on long-press
- Notes dialog opens and returns updated text (use testable dialog injection)
- Edit usernames dialog save/discard flows
- State filter dialog validates selection and saves
- Sorting comparator unit tests: each sort option produces expected order for sample data

Unit Tests
- StorageUtils save/load roundtrip for ContactEntry
- SocialType.saveUsername updates relevant fields
- SearchService returns expected results for sample dataset

Integration Tests (golden or e2e)
- Import from directory → images appear and persist
- Redo OCR happy path with mocked ChatGPTService → contact updates
- Pull-to-refresh sync calls CloudUtils.updateCloudJson and updates timestamp (mocked)
- Sign-in/out flows via CloudUtils (mocked)

---

# Regression Guard List
- Removing Scrollbar around PageView (prior test failure): ensure no ScrollController errors
- Debounced cache updates: ensure sorting responsiveness unchanged and no I/O during build
- PageController sharing (kGalleryPageController): no stale index after filters/sorts

---

# Pre-release Checklist
- Analyzer: no errors/warnings of significance
- Widget tests: pass
- Integration smoke: app launch, browse, search, import, redo OCR, social buttons
- Offline sync gracefulness verified
- Permissions granted/denied flows verified

# How to Run (optional)
- Analyzer
  - flutter analyze
- Widget tests
  - flutter test test/image_gallery_test.dart
- All tests
  - flutter test

Notes
- Prefer mocking CloudUtils/ChatGPTService in tests to avoid network/flaky dependencies.
- Keep small, deterministic fixtures for sorting and search tests.
