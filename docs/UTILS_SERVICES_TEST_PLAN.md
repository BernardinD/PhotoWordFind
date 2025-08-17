# Utilities & Services Test Plan (New UI Focus)

Scope: Test strategy for utilities in `lib/utils` and services in `lib/services` used by the New UI. No actual tests implemented now—this is a blueprint for future automated and exploratory tests. Legacy-only code is out of scope.

---

## 1) utils/storage_utils.dart
Purpose: Persist and retrieve ContactEntry and related data (Hive/JSON map hybrid).

Key Behaviors
- Save single ContactEntry with/without backup
- Bulk save and load all entries
- Migrations/field defaults for missing keys
- Idempotency: repeated saves don’t duplicate
- Error handling when storage path missing or corrupted data

Mocking/Isolation
- Use in-memory Hive boxes or temporary directory
- Stub file I/O with `setUp/tearDown` temp dirs

Suggested Tests
- Roundtrip save/load a ContactEntry (with notes/usernames/states)
- Update fields (snap/insta/discord) via saveUsername helpers; persist
- Handle missing optional fields gracefully
- Corrupt file then ensure graceful failure/logging (no crash)

---

## 2) utils/cloud_utils.dart
Purpose: Auth status, connectivity checks, sync cloud JSON.

Key Behaviors
- isSignedin/firstSignIn lifecycle
- isConnected logic
- updateCloudJson pushes/merges remote changes
- progressCallback contract firing (value, message, done, error)

Mocking/Isolation
- Wrap network in an interface or use dependency injection; provide Fake/Mock HTTP client
- For now: suggest a thin adapter to allow injecting a mock client

Suggested Tests
- isSignedin → false then firstSignIn → true (happy path)
- isConnected → false path blocks sync
- updateCloudJson success updates last sync time; failure surfaces error
- progressCallback invoked with start/progress/done

---

## 3) services/search_service.dart
Purpose: Filter and search across ContactEntry text/metadata.

Key Behaviors
- Query parsing (case-insensitive, partial matches)
- Filters by state, username presence, or other fields
- Stability with empty/null text

Mocking/Isolation
- Pure function/service—no external deps required

Suggested Tests
- Empty query returns all
- Partial case-insensitive matches
- Combination filters (e.g., state + query) yield expected subset
- Performance: large list remains responsive (micro-benchmark optional)

---

## 4) services/chat_gpt_service.dart
Purpose: OCR post-processing and vision requests for text extraction.

Key Behaviors
- processImage returns structured map: names, usernames, dates, notes
- Error handling and timeouts

Mocking/Isolation
- Provide an interface for HTTP/SDK calls; implement Fake returning canned payloads
- Ensure no real network calls in tests

Suggested Tests
- Happy path returns expected keys; post-processing populates ContactEntry
- Timeout/error throws or returns error result without crash
- Non-text images return empty/neutral result

---

## 5) utils/chatgpt_post_utils.dart
Purpose: Map ChatGPT results onto ContactEntry, validation and formatting.

Key Behaviors
- postProcessChatGptResult merges fields without clobbering user edits
- Adds audit trail in notes (if designed)

Mocking/Isolation
- Feed fixed JSON-like maps; verify deterministic ContactEntry updates

Suggested Tests
- Merge semantics: preserve existing usernames when new data missing
- Append notes rather than overwrite
- Date parsing/formatting edge cases handled

---

## 6) utils/sort_utils.dart
Purpose: Compute and cache sort orders, schedule/debounce cache updates.

Key Behaviors
- Comparators for all supported fields (Name, Date found, Size, etc.)
- scheduleCacheUpdate vs heavy update in hot path

Mocking/Isolation
- Pure logic; optionally fake clock/timers

Suggested Tests
- Each comparator ordering across a small fixture set
- Debounce: multiple calls coalesce; final cache state correct (if exposed)

---

## 7) utils/image_utils.dart
Purpose: Image-related helpers (dimensions, formats, safe decoding).

Key Behaviors
- Load file metadata safely; handle missing/corrupt images

Mocking/Isolation
- Temp files with tiny PNGs; mock failures by passing invalid paths

Suggested Tests
- Valid image returns expected metadata
- Invalid path handled gracefully

---

## 8) utils/files_utils.dart
Purpose: File operations (copy/move, directory listing for import).

Key Behaviors
- Filter images by extension
- Move/rename with collision handling

Mocking/Isolation
- Temp directories with dummy files; assert outcomes

Suggested Tests
- Directory scan picks only supported images
- Move preserves content; resolves filename collisions

---

## 9) utils/operations_utils.dart
Purpose: Misc operations helpers; likely UI-friendly wrappers.

Key Behaviors
- Verify any long-running operation helpers respect cancellation/timeouts

Mocking/Isolation
- Wrap timers/futures for determinism in tests

Suggested Tests
- Cancellation/timeout behavior

---

## 10) utils/toast_utils.dart
Purpose: Non-blocking user notifications.

Key Behaviors
- Show info/warning/error toasts; deduplicate spams

Mocking/Isolation
- Wrap platform-specific calls; expose a log sink to assert messages

Suggested Tests
- Suppress duplicate toasts within threshold window
- Correct severity mapping

---

## Cross-Cutting Concerns
- Persistence: verify SharedPreferences keys used by New UI (last selected state, import directory)
- PageController usage: ensure no I/O on rebuilds; debounce sort/cache updates
- Error handling: all public methods should not crash on bad input

## Mocks/Fakes Recommendations
- HTTP client (for Cloud and ChatGPT services)
- SharedPreferences: use setMockInitialValues
- File system: temp dirs + small PNG fixtures
- Clock/timers: fakeAsync for debounce and timeouts

## Minimal Test Harness Proposal
- Add test fixtures under `test/fixtures` for sample ContactEntry JSON and tiny images
- Introduce simple interfaces where direct platform calls exist to enable injection (Cloud/ChatGPT)
- Keep tests hermetic: no network, no external app launches

## How to Run (later)
- flutter test
- flutter analyze
