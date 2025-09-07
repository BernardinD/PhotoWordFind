/*
 Overview of app features
 - Dual UI modes: modern gallery UI and legacy interface with in-app toggle.
 - Gallery browsing: masonry grid (sliver) with full-screen review and swipe.
 - Search, filter, sort: rich search; filters for state, verification, platform added; multiple sort options with order toggle.
 - Handles management: edit/view Snapchat, Instagram, Discord; verify/unverify with timestamps; mark added/reset added.
 - OCR & AI: ChatGPT-based extraction; manual crop/redo flow; safe post-processing to preserve verified data.
 - Import workflow: pick from device albums for a chosen import directory; move/copy into DCIM/Comb; auto-process and save.
 - Data & persistence: Hive storage with autosave; migrations from SharedPreferences; legacy path recovery.
 - Cloud backup: Google Drive JSON backup; sign-in/out; merge cloud→local; explicit sync and pull-to-refresh.
 - Notes & actions: edit notes; open socials; guided unfriend flows with timestamped notes.
 - Settings: manage import directory, cloud account, view last sync time.
 - Performance & reliability: cache trimming on lifecycle/memory pressure; targeted image decoding; progress and error feedback; crash reporting.
*/
/*
 App feature summary (as of 2025-08-27)

 - UI modes
   - Modern gallery UI with compact, pinnable controls and legacy UI; users can switch between them from the AppBar.

 - Image gallery & navigation
   - Masonry grid (sliver-based) with PageView fallback; counter overlay; full-screen review on tap in grid.
   - Search across filename, identifier, state, name, usernames, previous handles, sections, and OCR/extracted text.
   - Filters: State, Verification (Unverified any/Snap/Instagram/Discord), and per-platform “Added” (Snap/Instagram: Any/Added/Not added).
   - Sorting: Name, Date found, File size, Snap/Instagram Added dates, and Added flags; ascending/descending toggle.
   - Selection and bulk actions: select tiles and move to a state; single-item move supported.
   - Quick entry point to “Review unverified” that narrows to unverified items and opens the full-screen viewer.

 - Full-screen review (ReviewViewer)
   - Zoomable photo viewer with swipe navigation.
   - “Details” bottom sheet shows the full OCR/extracted text.
   - Handles & Verification editor panel:
     - Edit Snapchat/Instagram/Discord usernames (with verified handles locked until unverified).
     - Mark Verified/Unverified with timestamps; mark Added/Reset Added with dates per platform.
     - Suggestions sourced from detected handles (aggregated map), previous handles history, and section content.
     - Quick-open social profiles/apps for verification; haptic feedback on panel snap points.

 - Redo OCR / crop (RedoCropScreen)
   - Manual crop UI with corner handles, grid overlay, and zoomable background.
   - Sends cropped image to ChatGPT OCR; optional one-time name/age update when missing.
   - Safe post-processing preserves verified handles, merges sections without duplicates, and avoids overwriting an existing location.

 - Import pipeline
   - Choose/persist an import directory; pick images via device album matching the directory name (Android bucketId filter).
   - Permission handling; move/copy images to DCIM/Comb; create entries with initial state; run ChatGPT extraction per image.
   - Persist to Hive and a file-path map; progress via snackbars; final cloud sync after import.

 - Data model & storage
   - ContactEntry persisted in Hive with autosave via MobX reactions and debounced cloud backup.
   - Tracks usernames, platform Added flags and dates, Verification dates, previous handles, notes, sections, name/age, location.
   - Migrations: SharedPreferences → Hive, legacy image-path recovery, and one-time verification date backfill from added dates.

 - Cloud backup & settings
   - Google Sign-In with Drive JSON backup (create/get/update); merge cloud → local; explicit sync; pull-to-refresh in gallery.
   - Settings for sign-in/out, last sync time, and import directory management.

 - Social actions & notes
   - Open Snapchat/Instagram/Discord (Discord copies handle to clipboard before opening app).
   - Quick unfriend flows with confirmation and timestamped note entries; dedicated Notes editor dialog.

 - Performance & resilience
   - Proactive image cache trimming on lifecycle/memory pressure; width-targeted image decoding for grids.
   - Cached file-size lookup for sorting; error banners; progress callbacks; crash reporting via Catcher.
*/
import 'dart:async';
import 'dart:io';

import 'package:PhotoWordFind/main.dart' show UiMode; // for UI mode switching
import 'package:PhotoWordFind/models/contactEntry.dart';
import 'package:PhotoWordFind/screens/gallery/widgets/image_gallery.dart';
import 'package:PhotoWordFind/screens/settings/settings_screen.dart';
import 'package:PhotoWordFind/services/chat_gpt_service.dart';
import 'package:PhotoWordFind/services/search_service.dart';
import 'package:PhotoWordFind/social_icons.dart';
import 'package:PhotoWordFind/utils/chatgpt_post_utils.dart';
import 'package:PhotoWordFind/utils/cloud_utils.dart';
import 'package:PhotoWordFind/utils/storage_utils.dart';
import 'package:PhotoWordFind/services/redo_job_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:PhotoWordFind/screens/gallery/review_viewer.dart';
import 'package:PhotoWordFind/utils/memory_utils.dart';
import 'package:PhotoWordFind/utils/media_scan_utils.dart';

// Platform "added" filter: Any, Added, or Not added
enum AddedFilter { any, added, notAdded }

// Result returned from the Move dialog: target state and whether to apply
// the "never friended back" automation to moved entries.
class _MoveSelection {
  final String state;
  final bool applyNeverBack;
  const _MoveSelection(this.state, this.applyNeverBack);
}

class ImageGalleryScreen extends StatefulWidget {
  const ImageGalleryScreen({super.key});

  @override
  State<ImageGalleryScreen> createState() => _ImageGalleryScreenState();
}

class _ImageGalleryScreenState extends State<ImageGalleryScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // Filters/sort/search state
  String searchQuery = '';
  String selectedSortOption = 'Name';
  final List<String> sortOptions = const [
    'Name',
    'Date found',
    'Size',
    'Snap Added Date',
    'Instagram Added Date',
    'Added on Snapchat',
    'Added on Instagram',
    'Location',
  ];
  String selectedState = 'All';
  List<String> states = ['All'];

  // Advanced filters (compact header -> bottom sheet)
  final Set<String> _selectedStatesMulti = <String>{};
  AddedFilter _snapAddedFilter = AddedFilter.any;
  AddedFilter _instaAddedFilter = AddedFilter.any;
  // Time difference filter (relative to device timezone), stored in minutes
  // Default range: ±10 hours
  static const int _kTimeDiffMinDefault = -600; // -10h
  static const int _kTimeDiffMaxDefault = 600; // +10h
  int _timeDiffMinMinutes = _kTimeDiffMinDefault;
  int _timeDiffMaxMinutes = _kTimeDiffMaxDefault;

  // Verification filter
  String verificationFilter = 'All';
  final List<String> verificationOptions = const [
    'All',
    'Unverified (any)',
    'Unverified: Snapchat',
    'Unverified: Instagram',
    'Unverified: Discord',
  ];

  // Data
  List<ContactEntry> images = [];
  List<ContactEntry> allImages = [];
  List<String> selectedImages = [];
  // Sub-selection: tiles flagged for the "never friended back" bulk process
  final Set<String> _neverBackSelected = <String>{};

  // View state
  int currentIndex = 0;
  bool isAscending = true;
  bool _controlsExpanded = false; // compact by default
  bool _isInitializing = true;
  String? _initializationError;
  bool _filtersCollapsed = false; // compact header collapse for split screen

  // Sync
  bool _syncing = false;
  DateTime? _lastSyncTime;

  // Debounce
  Timer? _searchDebounce;
  final TextEditingController _searchController = TextEditingController();

  // Feature flags
  static const bool kUseCompactHeader = true;
  // Max number of images user can select in one import batch (wechat_assets_picker default is 9)
  static const int kMaxImportSelection = 200;
  static const String _importMaxSelectionKey = 'import_max_selection_v1';

  // Redo Mode state
  bool _redoMode =
      false; // when true, show only redo candidates/failed and change FAB
  // Selection mode: stays active until user cancels
  bool _selectionModeActive = false;

  // Listen to job status changes to refresh banner/mode contents
  void _onJobsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  // Persisted keys
  static const String _lastStateKey = 'last_selected_state';
  static const String _importDirKey = 'import_directory';
  // New persisted keys for advanced filters/header state
  static const String _filtersCollapsedKey = 'gallery_filters_collapsed_v1';
  static const String _verificationFilterKey = 'gallery_verification_filter_v1';
  static const String _snapAddedKey = 'gallery_snap_added_filter_v1';
  static const String _instaAddedKey = 'gallery_insta_added_filter_v1';
  static const String _multiStatesKey = 'gallery_selected_states_multi_v1';
  static const String _timeDiffMinKey = 'gallery_time_diff_min_v1';
  static const String _timeDiffMaxKey = 'gallery_time_diff_max_v1';
  // Persist sort option and direction
  static const String _sortOptionKey = 'gallery_sort_option_v1';
  static const String _sortAscendingKey = 'gallery_sort_ascending_v1';
  String? _importDirPath;
  // Cached file sizes to avoid repeated sync I/O in comparators
  final Map<String, int> _sizeCache = <String, int>{};
  // Sign-in state to avoid repeated futures in AppBar
  bool _signedIn = false;
  // ImageCache budget backup
  int? _oldCacheItems;
  int? _oldCacheBytes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Downsize the global image cache while this memory-heavy screen is active
    try {
      final cache = PaintingBinding.instance.imageCache;
      _oldCacheItems = cache.maximumSize;
      _oldCacheBytes = cache.maximumSizeBytes;
      cache.maximumSize = 300; // default ~1000; reduce retained decodes
      cache.maximumSizeBytes = 48 * 1024 * 1024; // ~48MB
    } catch (_) {}
    CloudUtils.progressCallback = (
        {double? value,
        String? message,
        bool done = false,
        bool error = false}) {
      // Reserved hook for future UI progress
    };
    // Refresh UI when background redo statuses change (affects banner and mode list)
    RedoJobManager.instance.statuses.addListener(_onJobsChanged);
    _initializeApp();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    RedoJobManager.instance.statuses.removeListener(_onJobsChanged);
    // Restore global image cache budgets
    try {
      final cache = PaintingBinding.instance.imageCache;
      if (_oldCacheItems != null) cache.maximumSize = _oldCacheItems!;
      if (_oldCacheBytes != null) cache.maximumSizeBytes = _oldCacheBytes!;
    } catch (_) {}
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Proactively trim caches when backgrounding or coming back
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      MemoryUtils.trimImageCaches();
    } else if (state == AppLifecycleState.resumed) {
      // Also clear any stale decodes on resume
      MemoryUtils.trimImageCaches();
    }
  }

  @override
  void didHaveMemoryPressure() {
    // Android signaled low memory; free decoded bitmaps immediately
    MemoryUtils.trimImageCaches();
  }

  // ---------------- Initialization ----------------
  Future<void> _initializeApp() async {
    try {
      await _ensureSignedIn();
      await _loadImportDirectory();
      await _loadImages();
      await _restorePersistedFilters();
      await _applyFiltersAndSort();
      setState(() => _isInitializing = false);
    } catch (e) {
      setState(() {
        _initializationError = 'Initialization failed: $e';
        _isInitializing = false;
      });
    }
  }

  Future<bool> _ensureSignedIn() async {
    try {
      final signed = await CloudUtils.isSignedin();
      if (!signed) {
        await CloudUtils.firstSignIn();
      }
      if (mounted) setState(() => _signedIn = true);
      return true;
    } catch (e) {
      _initializationError = 'Sign-in failed: $e';
      if (mounted) setState(() => _signedIn = false);
      return false;
    }
  }

  Future<void> _forceSync({bool fromPull = false}) async {
    if (_syncing) return;
    setState(() => _syncing = true);
    final messenger = ScaffoldMessenger.of(context);
    void show(String msg) =>
        messenger.showSnackBar(SnackBar(content: Text(msg)));
    try {
      await StorageUtils.syncLocalAndCloud();
      _lastSyncTime = DateTime.now();
      show('Synced at ${DateFormat('hh:mm a').format(_lastSyncTime!)}');
      await _loadImages();
      await _applyFiltersAndSort();
    } catch (e) {
      show('Sync failed: $e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  // ---------------- Data load & persistence ----------------
  Future<void> _loadImages() async {
    final keys = List<String>.from(StorageUtils.getKeys());
    // Load in parallel to reduce total latency
    final results = await Future.wait(keys.map((id) => StorageUtils.get(id)));
    final List<ContactEntry> loaded = [
      for (final c in results)
        if (c != null) c,
    ];
    allImages = loaded;
    _updateStates(allImages);
    await _restoreLastSelectedState();
  }

  Future<void> _loadImagesFromJsonFile() async {
    final Map<String, dynamic> fileMap = await StorageUtils.readJson();
    final List<ContactEntry> loaded = [];
    for (final entry in fileMap.entries) {
      final identifier = entry.key;
      final value = entry.value;
      if (value is String) {
        loaded.add(ContactEntry(
          identifier: identifier,
          imagePath: value,
          dateFound: File(value).existsSync()
              ? File(value).lastModifiedSync()
              : DateTime.now(),
          json: {'imagePath': value},
        ));
      } else if (value is Map<String, dynamic>) {
        final imagePath = value['imagePath'] ?? '';
        loaded.add(ContactEntry.fromJson(identifier, imagePath, value));
      }
    }
    allImages = loaded;
    _updateStates(allImages);
    await _restoreLastSelectedState();
  }

  Future<void> _loadImportDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    _importDirPath = prefs.getString(_importDirKey);
  }

  Future<void> _saveImportDirectory(String pathStr) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_importDirKey, pathStr);
  }

  Future<void> _changeImportDir() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir != null) {
      setState(() => _importDirPath = dir);
      await _saveImportDirectory(dir);
    }
  }

  Future<void> _resetImportDir() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_importDirKey);
    setState(() => _importDirPath = null);
  }

  Future<int> _resolveImportMaxSelection() async {
    // Returns the effective max selection for the picker.
    // If user sets Unlimited (stored as -1), return a very high number.
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(_importMaxSelectionKey);
    if (v == null) return kMaxImportSelection; // default
    if (v < 0) return 999999; // practical "unlimited"
    return v;
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final navContext = context;

    final body =
        _isInitializing ? _buildInitializing() : _buildMainContent(navContext);

    return Scaffold(
      appBar: kUseCompactHeader
          ? null
          : AppBar(
              title: const Text('Image Gallery'),
              actions: _buildAppBarActions(navContext)),
      body: body,
      floatingActionButton: _isInitializing
          ? null
          : _redoMode
              ? FloatingActionButton.extended(
                  onPressed: () {
                    // In redo mode, apply full redo to all displayed candidates
                    final Map<String, RedoJobStatus> statusMap =
                        RedoJobManager.instance.statuses.value;
                    bool _isRedoCandidate(ContactEntry c) {
                      final isEmpty =
                          ((c.extractedText?.trim().isEmpty ?? true)) &&
                              ((c.name == null || c.name!.trim().isEmpty)) &&
                              (c.age == null) &&
                              ((c.snapUsername?.trim().isEmpty ?? true)) &&
                              ((c.instaUsername?.trim().isEmpty ?? true)) &&
                              ((c.discordUsername?.trim().isEmpty ?? true)) &&
                              ((c.sections?.isNotEmpty ?? false) == false);
                      final failed =
                          statusMap[c.identifier]?.message == 'Failed';
                      return isEmpty || failed;
                    }

                    final targets = images.where(_isRedoCandidate).toList();
                    if (targets.isEmpty) return;
                    for (final entry in targets) {
                      try {
                        RedoJobManager.instance.enqueueFull(
                          entry: entry,
                          imageFile: File(entry.imagePath),
                          allowNameAgeUpdate: (entry.name == null ||
                              entry.name!.isEmpty ||
                              entry.age == null),
                        );
                      } catch (_) {}
                    }
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(
                              'Queued ${targets.length} redo job${targets.length == 1 ? '' : 's'}')),
                    );
                  },
                  icon: const Icon(Icons.autorenew),
                  label: const Text('Redo (Full)'),
                )
        : _selectionModeActive
          ? FloatingActionButton(
            onPressed: selectedImages.isEmpty
              ? null
              : () => _onMenuOptionSelected('', 'move'),
            tooltip: 'Move selected',
            child: const Icon(Icons.move_to_inbox),
          )
                  : FloatingActionButton(
                      onPressed: () => _importImages(navContext),
                      tooltip: 'Import Images',
                      child: const Icon(Icons.add),
                    ),
      persistentFooterButtons: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: MediaQuery.of(navContext).size.width * 1.20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SocialIcon.snapchatIconButton!,
                const Spacer(),
                SocialIcon.galleryIconButton!,
                const Spacer(),
                SocialIcon.bumbleIconButton!,
                const Spacer(),
                FloatingActionButton(
                  heroTag: null,
                  tooltip: 'Change current directory',
                  onPressed: _changeImportDir,
                  child: const Icon(Icons.drive_folder_upload),
                ),
                const Spacer(),
                SocialIcon.instagramIconButton!,
                const Spacer(),
                SocialIcon.discordIconButton!,
                const Spacer(),
                SocialIcon.kikIconButton!,
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInitializing() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          const Text('Signing in and loading images...'),
          if (_initializationError != null) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                _initializationError!,
                style: const TextStyle(color: Colors.orange),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMainContent(BuildContext navContext) {
    // Compute the list to display (apply redo mode filtering on top of current images)
    final Map<String, RedoJobStatus> statusMap =
        RedoJobManager.instance.statuses.value;
    bool _isRedoCandidate(ContactEntry c) {
      final isEmpty = ((c.extractedText?.trim().isEmpty ?? true)) &&
          ((c.name == null || c.name!.trim().isEmpty)) &&
          (c.age == null) &&
          ((c.snapUsername?.trim().isEmpty ?? true)) &&
          ((c.instaUsername?.trim().isEmpty ?? true)) &&
          ((c.discordUsername?.trim().isEmpty ?? true)) &&
          ((c.sections?.isNotEmpty ?? false) == false);
      final failed = statusMap[c.identifier]?.message == 'Failed';
      return isEmpty || failed;
    }

    final List<ContactEntry> displayedImages =
        _redoMode ? images.where(_isRedoCandidate).toList() : images;

    if (!kUseCompactHeader) {
      return LayoutBuilder(builder: (context, constraints) {
        final screenHeight = constraints.maxHeight;
        return Column(
          children: [
            if (_initializationError != null)
              _buildInitializationErrorBanner(context),
            if (!_redoMode) _buildRedoBanner(),
            _buildControls(),
    Expanded(
              child: ImageGallery(
                images: displayedImages,
                selectedImages: selectedImages,
                sortOption: selectedSortOption,
                onImageSelected: (String id) {
                  setState(() {
                    if (selectedImages.contains(id)) {
                      selectedImages.remove(id);
                      _neverBackSelected.remove(id);
                    } else {
                      selectedImages.add(id);
          _selectionModeActive = true;
                    }
                  });
                },
                onMenuOptionSelected: _onMenuOptionSelected,
                galleryHeight: screenHeight,
                onPageChanged: (idx) => setState(() => currentIndex = idx),
                currentIndex: currentIndex,
        selectionMode: _selectionModeActive,
                neverBackSelectedIds: _neverBackSelected,
                onToggleNeverBack: (id) {
                  setState(() {
                    if (_neverBackSelected.contains(id)) {
                      _neverBackSelected.remove(id);
                    } else if (selectedImages.contains(id)) {
                      _neverBackSelected.add(id);
                    }
                  });
                },
              ),
            ),
          ],
        );
      });
    }

    // Compact header with CustomScrollView and slivers
    return CustomScrollView(
      // Limit offscreen cache to control memory usage
      cacheExtent: 800,
      slivers: [
        SliverAppBar(
          title: const Text('Image Gallery'),
          floating: false,
          snap: false,
          pinned: true,
          primary: true,
          actions: _buildAppBarActions(navContext),
        ),
        if (_initializationError != null)
          SliverToBoxAdapter(child: _buildInitializationErrorBanner(context)),
        if (!_redoMode) SliverToBoxAdapter(child: _buildRedoBanner()),
        SliverPersistentHeader(
          pinned: true,
          delegate: _FixedHeaderDelegate(
            // True minimized single-row when collapsed
            minHeight: _filtersCollapsed ? 48 : 120,
            maxHeight: _filtersCollapsed ? 48 : 120,
            child: _buildSlimFilterBar(),
          ),
        ),
        SliverImageGallery(
          images: displayedImages,
          selectedImages: selectedImages,
          sortOption: selectedSortOption,
          onImageSelected: (String id) {
            setState(() {
              if (selectedImages.contains(id)) {
                selectedImages.remove(id);
                _neverBackSelected.remove(id);
              } else {
                selectedImages.add(id);
        _selectionModeActive = true;
              }
            });
          },
          onMenuOptionSelected: _onMenuOptionSelected,
      selectionMode: _selectionModeActive,
          neverBackSelectedIds: _neverBackSelected,
          onToggleNeverBack: (id) {
            setState(() {
              if (_neverBackSelected.contains(id)) {
                _neverBackSelected.remove(id);
              } else {
                if (selectedImages.contains(id)) {
                  _neverBackSelected.add(id);
                }
              }
            });
          },
        ),
      ],
    );
  }

  List<Widget> _buildAppBarActions(BuildContext navContext) {
    final actions = <Widget>[];

    // If in selection mode, show a Clear/Cancel button to exit selection state.
    if (_selectionModeActive) {
      actions.add(
        IconButton(
          tooltip: 'Cancel selection',
          icon: const Icon(Icons.close),
          onPressed: () {
            setState(() {
              selectedImages.clear();
              _neverBackSelected.clear();
              _selectionModeActive = false;
            });
          },
        ),
      );
      // Badge menu: quick access to apply never-back, or move+never-back
      actions.add(
        PopupMenuButton<String>(
          tooltip: 'Never-back actions',
          onSelected: (value) async {
            if (value == 'never_back') {
              await _applyNeverFriendedBack();
            } else if (value == 'move_never') {
              await _onMenuOptionSelected('', 'move');
            }
          },
          itemBuilder: (ctx) => [
            PopupMenuItem<String>(
              value: 'never_back',
              enabled: _neverBackSelected.isNotEmpty,
              child: Row(
                children: [
                  const Icon(Icons.person_off),
                  const SizedBox(width: 8),
                  Text('Apply never-back (${_neverBackSelected.length})'),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              value: 'move_never',
              enabled: selectedImages.isNotEmpty,
              child: Row(
                children: const [
                  Icon(Icons.move_to_inbox),
                  SizedBox(width: 8),
                  Text('Move selected… (with never-back)'),
                ],
              ),
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.person_off),
                if (_neverBackSelected.isNotEmpty)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: _Badge(
                      count: _neverBackSelected.length,
                      color: Colors.redAccent,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    actions.addAll([
      if (_redoMode)
        Padding(
          padding: const EdgeInsets.only(right: 4.0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.15),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.orangeAccent.withOpacity(0.6)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.autorenew,
                    size: 16, color: Colors.orangeAccent),
                const SizedBox(width: 6),
                const Text('Redo mode',
                    style: TextStyle(color: Colors.orangeAccent)),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => setState(() => _redoMode = false),
                  child: const Padding(
                    padding: EdgeInsets.all(2.0),
                    child:
                        Icon(Icons.close, size: 16, color: Colors.orangeAccent),
                  ),
                ),
              ],
            ),
          ),
        ),
      // Global jobs indicator: active/queued/failed
      ValueListenableBuilder<RedoJobsSummary>(
        valueListenable: RedoJobManager.instance.summary,
        builder: (context, s, _) {
          final hasAny = (s.active + s.queued + s.failed) > 0;
          final color = s.failed > 0
              ? Colors.orange
              : (hasAny ? Colors.white : Colors.white70);
          final tooltip =
              'Jobs — Active: ${s.active}, Queued: ${s.queued}, Failed: ${s.failed}';
          return IconButton(
            tooltip: tooltip,
            icon: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.work_outline),
                if (s.active > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child:
                        _Badge(count: s.active, color: Colors.lightBlueAccent),
                  ),
                if (s.failed > 0)
                  Positioned(
                    left: 0,
                    bottom: 0,
                    child: _Badge(count: s.failed, color: Colors.orangeAccent),
                  ),
              ],
            ),
            color: color,
            onPressed: () {
              showModalBottomSheet(
                context: navContext,
                builder: (_) {
                  return SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Background jobs',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text(
                              'Active: ${s.active}  •  Queued: ${s.queued}  •  Failed: ${s.failed}'),
                          const SizedBox(height: 12),
                          if (s.failed > 0)
                            Row(
                              children: [
                                const Icon(Icons.error_outline,
                                    color: Colors.orangeAccent),
                                const SizedBox(width: 8),
                                const Expanded(
                                    child: Text(
                                        'Some jobs failed. You can retry from the failed tiles.')),
                              ],
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      IconButton(
        tooltip: 'Switch to Legacy UI',
        icon: const Icon(Icons.swap_horiz),
        onPressed: () async {
          final proceed = await showDialog<bool>(
            context: navContext,
            builder: (dialogCtx) => AlertDialog(
              title: const Text('Confirm UI Switch'),
              content: const Text('Switch to legacy interface?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogCtx, false),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: () => Navigator.pop(dialogCtx, true),
                    child: const Text('Switch')),
              ],
            ),
          );
          if (proceed == true) {
            await UiMode.switchTo(false);
          }
        },
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: _isInitializing
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(_signedIn ? Icons.cloud_done : Icons.cloud_off,
                color: _signedIn ? Colors.green : Colors.redAccent),
      ),
      if (!_isInitializing)
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: 'Settings',
          onPressed: () {
            Navigator.of(navContext).push(
              MaterialPageRoute(
                builder: (_) => SettingsScreen(
                  onResetImportDir: _resetImportDir,
                  onChangeImportDir: _changeImportDir,
                  onRequestSignIn: () async {
                    final ok = await _ensureSignedIn();
                    if (!ok) {
                      setState(() {
                        _initializationError = 'Sign-in failed';
                      });
                    }
                    return ok;
                  },
                  onRequestSignOut: () async {
                    try {
                      await CloudUtils.signOut();
                    } catch (_) {}
                    if (mounted) setState(() => _signedIn = false);
                  },
                  lastSyncTime: _lastSyncTime,
                  syncing: _syncing,
                  signInFailed: _initializationError != null,
                ),
              ),
            );
          },
        ),
    ]);

    return actions;
  }

  // Banner prompting to enter Redo mode when items need attention
  Widget _buildRedoBanner() {
    final statusMap = RedoJobManager.instance.statuses.value;
    int emptyCount = 0;
    int failedCount = 0;
    for (final c in images) {
      final isEmpty = ((c.extractedText?.trim().isEmpty ?? true)) &&
          ((c.name == null || c.name!.trim().isEmpty)) &&
          (c.age == null) &&
          ((c.snapUsername?.trim().isEmpty ?? true)) &&
          ((c.instaUsername?.trim().isEmpty ?? true)) &&
          ((c.discordUsername?.trim().isEmpty ?? true)) &&
          ((c.sections?.isNotEmpty ?? false) == false);
      if (isEmpty) emptyCount++;
      if (statusMap[c.identifier]?.message == 'Failed') failedCount++;
    }
    if (emptyCount == 0 && failedCount == 0) return const SizedBox.shrink();

    final text = failedCount > 0
        ? '$emptyCount need redo • $failedCount failed'
        : '$emptyCount need redo';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Material(
        color: Colors.orange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => setState(() => _redoMode = true),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.orangeAccent),
                const SizedBox(width: 10),
                Expanded(child: Text(text)),
                const SizedBox(width: 8),
                const Text('Enter redo mode',
                    style: TextStyle(
                        color: Colors.orangeAccent,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, color: Colors.orangeAccent),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSlimFilterBar() {
    final surface = Theme.of(context).colorScheme.surface;
    if (_filtersCollapsed) {
      // True minimized: single-row toolbar with small height.
      return Container(
        color: surface,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
        child: SizedBox(
          height: 40,
          child: Row(
            children: [
              IconButton(
                tooltip: 'Filters',
                icon: const Icon(Icons.tune),
                onPressed: _openFiltersSheet,
              ),
              IconButton(
                tooltip: 'Search',
                icon: const Icon(Icons.search),
                onPressed: _showSearchDialog,
              ),
              IconButton(
                tooltip: 'Sort',
                icon: const Icon(Icons.sort),
                onPressed: () async {
                  final res = await showModalBottomSheet<String>(
                    context: context,
                    builder: (ctx) => SafeArea(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          const ListTile(
                              title: Text('Sort by',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          ...sortOptions.map((o) => RadioListTile<String>(
                                value: o,
                                groupValue: selectedSortOption,
                                title: Text(o),
                                onChanged: (v) => Navigator.pop(ctx, v),
                              )),
                        ],
                      ),
                    ),
                  );
                  if (res != null) {
                    selectedSortOption = res;
                    await _applyFiltersAndSort();
                    await _persistFilters();
                  }
                },
              ),
              _buildOrderToggle(),
              const Spacer(),
              IconButton(
                tooltip: verificationFilter.startsWith('Unverified')
                    ? 'Show all'
                    : 'Review unverified',
                icon: const Icon(Icons.fact_check_outlined),
                onPressed: () async {
                  if (verificationFilter.startsWith('Unverified')) {
                    setState(() => verificationFilter = 'All');
                    await _persistFilters();
                    await _filterImages();
                  } else {
                    setState(() => verificationFilter = 'Unverified (any)');
                    await _persistFilters();
                    await _filterImages();
                    if (images.isNotEmpty) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ReviewViewer(
                              images: images,
                              initialIndex: 0,
                              sortOption: selectedSortOption),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text(
                              'No unverified entries in current filters')));
                    }
                  }
                },
              ),
              IconButton(
                tooltip: 'Expand controls',
                icon: const Icon(Icons.unfold_more),
                onPressed: () async {
                  setState(() => _filtersCollapsed = false);
                  await _persistFilters();
                },
              ),
            ],
          ),
        ),
      );
    }

    // Expanded: two-row layout with full search field.
    return Container(
      color: surface,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildFiltersChip(),
              const SizedBox(width: 6),
              IconButton(
                tooltip: verificationFilter.startsWith('Unverified')
                    ? 'Show all'
                    : 'Review unverified',
                icon: const Icon(Icons.fact_check_outlined),
                onPressed: () async {
                  if (verificationFilter.startsWith('Unverified')) {
                    setState(() => verificationFilter = 'All');
                    await _persistFilters();
                    await _filterImages();
                  } else {
                    setState(() => verificationFilter = 'Unverified (any)');
                    await _persistFilters();
                    await _filterImages();
                    if (images.isNotEmpty) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ReviewViewer(
                              images: images,
                              initialIndex: 0,
                              sortOption: selectedSortOption),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text(
                              'No unverified entries in current filters')));
                    }
                  }
                },
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Collapse controls',
                icon: const Icon(Icons.unfold_less),
                onPressed: () async {
                  setState(() => _filtersCollapsed = true);
                  await _persistFilters();
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 8),
                      suffixIcon: (_searchController.text.isNotEmpty)
                          ? IconButton(
                              tooltip: 'Clear',
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => searchQuery = '');
                                _filterImages();
                              },
                            )
                          : null,
                    ),
                    onChanged: (value) {
                      searchQuery = value;
                      _searchDebounce?.cancel();
                      _searchDebounce =
                          Timer(const Duration(milliseconds: 220), () {
                        if (!mounted) return;
                        _filterImages();
                      });
                      setState(() {});
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Sort',
                icon: const Icon(Icons.sort),
                onPressed: () async {
                  final res = await showModalBottomSheet<String>(
                    context: context,
                    builder: (ctx) => SafeArea(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          const ListTile(
                              title: Text('Sort by',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold))),
                          ...sortOptions.map((o) => RadioListTile<String>(
                                value: o,
                                groupValue: selectedSortOption,
                                title: Text(o),
                                onChanged: (v) => Navigator.pop(ctx, v),
                              )),
                        ],
                      ),
                    ),
                  );
                  if (res != null) {
                    selectedSortOption = res;
                    await _applyFiltersAndSort();
                    await _persistFilters();
                  }
                },
              ),
              _buildOrderToggle(),
            ],
          ),
        ],
      ),
    );
  }

  // Shows a small Filters chip with an active count badge.
  Widget _buildFiltersChip() {
    final activeCount = _activeFilterCount();
    return InkWell(
      onTap: _openFiltersSheet,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color:
              Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.tune, size: 18),
            const SizedBox(width: 6),
            const Text('Filters'),
            if (activeCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$activeCount',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontSize: 12)),
              ),
            ]
          ],
        ),
      ),
    );
  }

  int _activeFilterCount() {
    var c = 0;
    if (selectedState != 'All') c++;
    if (verificationFilter != 'All') c++;
    if (_snapAddedFilter != AddedFilter.any) c++;
    if (_instaAddedFilter != AddedFilter.any) c++;
    if (!(_timeDiffMinMinutes == _kTimeDiffMinDefault &&
        _timeDiffMaxMinutes == _kTimeDiffMaxDefault)) c++;
    return c;
  }

  Future<void> _openFiltersSheet() async {
    // Immediate-apply filter sheet; updates happen as you toggle, with Done to close.
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: media.size.height < 700 ? 0.85 : 0.6,
            minChildSize: 0.4,
            builder: (c, scroll) => StatefulBuilder(
              builder: (innerCtx, innerSetState) => Padding(
                padding: const EdgeInsets.all(12.0),
                child: ListView(
                  controller: scroll,
                  children: [
                    Row(
                      children: [
                        const Text('Filters',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Done'),
                        ),
                        TextButton(
                          onPressed: () {
                            // Reset to defaults and apply immediately
                            innerSetState(() {});
                            this.setState(() {
                              selectedState = 'All';
                              verificationFilter = 'All';
                              _snapAddedFilter = AddedFilter.any;
                              _instaAddedFilter = AddedFilter.any;
                            });
                            _saveLastSelectedState(selectedState);
                            _persistFilters();
                            _filterImages();
                          },
                          child: const Text('Reset'),
                        )
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('State',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in states)
                          ChoiceChip(
                            label: Text(s),
                            selected: selectedState == s,
                            onSelected: (_) async {
                              innerSetState(() {});
                              this.setState(() => selectedState = s);
                              await _saveLastSelectedState(selectedState);
                              await _persistFilters();
                              await _filterImages();
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Verification',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    ...verificationOptions.map((o) => RadioListTile<String>(
                          dense: true,
                          value: o,
                          groupValue: verificationFilter,
                          title: Text(o),
                          onChanged: (v) async {
                            innerSetState(() {});
                            this.setState(
                                () => verificationFilter = v ?? 'All');
                            await _persistFilters();
                            await _filterImages();
                          },
                        )),
                    const SizedBox(height: 8),
                    const Text('Added on',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    _AddedFilterRow(
                      label: 'Snapchat',
                      value: _snapAddedFilter,
                      onChanged: (v) async {
                        innerSetState(() {});
                        this.setState(() => _snapAddedFilter = v);
                        await _persistFilters();
                        await _filterImages();
                      },
                    ),
                    _AddedFilterRow(
                      label: 'Instagram',
                      value: _instaAddedFilter,
                      onChanged: (v) async {
                        innerSetState(() {});
                        this.setState(() => _instaAddedFilter = v);
                        await _persistFilters();
                        await _filterImages();
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('Time difference',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            innerSetState(() {});
                            this.setState(() {
                              _timeDiffMinMinutes = _kTimeDiffMinDefault;
                              _timeDiffMaxMinutes = _kTimeDiffMaxDefault;
                            });
                            _persistFilters();
                            _filterImages();
                          },
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                    Builder(builder: (_) {
                      String _fmtMinutes(int mins) {
                        if (mins == 0) return '0m';
                        final sign = mins > 0 ? '+' : '-';
                        final abs = mins.abs();
                        final h = abs ~/ 60;
                        final m = abs % 60;
                        if (h > 0 && m > 0) return '$sign${h}h ${m}m';
                        if (h > 0) return '$sign${h}h';
                        return '$sign${m}m';
                      }

                      final isAny =
                          _timeDiffMinMinutes == _kTimeDiffMinDefault &&
                              _timeDiffMaxMinutes == _kTimeDiffMaxDefault;
                      final subtitle = isAny
                          ? 'Any'
                          : '${_fmtMinutes(_timeDiffMinMinutes)} to ${_fmtMinutes(_timeDiffMaxMinutes)}';
                      // Use hours for the UI RangeSlider but persist minutes
                      final RangeValues values = RangeValues(
                        _timeDiffMinMinutes / 60.0,
                        _timeDiffMaxMinutes / 60.0,
                      );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 6, bottom: 2),
                            child: Text(subtitle,
                                style: const TextStyle(color: Colors.black54)),
                          ),
                          RangeSlider(
                            min: -10,
                            max: 10,
                            divisions:
                                40, // 30-minute steps (hours and half-hours)
                            labels: RangeLabels(
                              '${values.start.toStringAsFixed(1)}h',
                              '${values.end.toStringAsFixed(1)}h',
                            ),
                            values: values,
                            onChanged: (rv) {
                              // Round to nearest 30 minutes
                              int round30(double hours) =>
                                  ((hours * 60) / 30).round() * 30;
                              final newMin = round30(rv.start);
                              final newMax = round30(rv.end);
                              innerSetState(() {});
                              this.setState(() {
                                _timeDiffMinMinutes = newMin;
                                _timeDiffMaxMinutes = newMax;
                              });
                              _persistFilters();
                              _filterImages();
                            },
                          ),
                        ],
                      );
                    }),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Done'),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildControls() {
    return RefreshIndicator(
      onRefresh: () => _forceSync(fromPull: true),
      displacement: 56,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 300),
          child: _controlsExpanded
              ? _buildExpandedControls()
              : _buildMinimizedControls(),
        ),
      ),
    );
  }

  Widget _buildExpandedControls() {
    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 500;
      final children = <Widget>[
        Expanded(
          child: DropdownButtonFormField<String>(
            value: states.contains(selectedState) ? selectedState : null,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'State',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: states
                .map((dir) =>
                    DropdownMenuItem<String>(value: dir, child: Text(dir)))
                .toList(),
            onChanged: (value) async {
              selectedState = value!;
              await _saveLastSelectedState(selectedState);
              await _filterImages();
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (value) async {
              searchQuery = value;
              _searchDebounce?.cancel();
              _searchDebounce = Timer(const Duration(milliseconds: 220), () {
                if (!mounted) return;
                _filterImages();
              });
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<String>(
            value: selectedSortOption,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Sort by',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: sortOptions
                .map((o) => DropdownMenuItem<String>(value: o, child: Text(o)))
                .toList(),
            onChanged: (value) async {
              selectedSortOption = value!;
              await _applyFiltersAndSort();
            },
          ),
        ),
        const SizedBox(width: 12),
        _buildOrderToggle(),
      ];

      final content = isWide
          ? Row(children: children)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: children.sublist(0, 3)),
                const SizedBox(height: 12),
                Row(children: children.sublist(3)),
              ],
            );

      return Card(
        margin: const EdgeInsets.all(12),
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8.0, right: 8.0),
                child: content,
              ),
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  icon: const Icon(Icons.expand_less),
                  onPressed: () => setState(() => _controlsExpanded = false),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildMinimizedControls() {
    return Card(
      margin: const EdgeInsets.all(12),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: sortOptions.contains(selectedSortOption)
                    ? selectedSortOption
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Sort by',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: sortOptions
                    .map((o) =>
                        DropdownMenuItem<String>(value: o, child: Text(o)))
                    .toList(),
                onChanged: (value) async {
                  selectedSortOption = value!;
                  await _applyFiltersAndSort();
                },
              ),
            ),
            const SizedBox(width: 8),
            _buildOrderToggle(),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Filter by state',
              child: IconButton(
                  icon: const Icon(Icons.filter_list),
                  onPressed: _showStatePicker),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: 'Search',
              child: IconButton(
                  icon: const Icon(Icons.search), onPressed: _showSearchDialog),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.expand_more),
              onPressed: () => setState(() => _controlsExpanded = true),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSearchDialog() async {
    final controller = TextEditingController(text: searchQuery);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Search'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Type to filter…'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Apply')),
        ],
      ),
    );
    if (result != null) {
      setState(() => searchQuery = result);
      await _filterImages();
    }
  }

  Future<void> _showStatePicker() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
                title: Text('Filter by state',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            ...states.map((s) => RadioListTile<String>(
                  value: s,
                  groupValue: selectedState,
                  title: Text(s),
                  onChanged: (v) => Navigator.pop(ctx, v),
                )),
          ],
        ),
      ),
    );
    if (result != null) {
      selectedState = result;
      await _saveLastSelectedState(selectedState);
      await _filterImages();
    }
  }

  Widget _buildOrderToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Ink(
        decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1), shape: BoxShape.circle),
        child: IconButton(
          icon: AnimatedRotation(
            turns: isAscending ? 0 : 0.5,
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.arrow_upward, color: Colors.blue),
          ),
          onPressed: () async {
            isAscending = !isAscending;
            await _applyFiltersAndSort();
            await _persistFilters();
          },
        ),
      ),
    );
  }

  // ---------------- Filtering/sorting ----------------
  Future<void> _filterImages() async {
    await _applyFiltersAndSort();
  }

  void _updateStates(List<ContactEntry> imgs) {
    final tags = <String>{};
    for (final img in imgs) {
      if (img.state != null) tags.add(img.state!);
    }
    final sorted = tags.toList()..sort();
    setState(() {
      states = ['All', ...sorted];
      if (!states.contains(selectedState)) selectedState = 'All';
    });
  }

  Future<void> _restoreLastSelectedState() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(_lastStateKey);
    if (last != null && states.contains(last)) selectedState = last;
  }

  Future<void> _saveLastSelectedState(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastStateKey, value);
  }

  // ---------------- Persist/restore advanced filters ----------------
  Future<void> _restorePersistedFilters() async {
    final prefs = await SharedPreferences.getInstance();
    _filtersCollapsed =
        prefs.getBool(_filtersCollapsedKey) ?? _filtersCollapsed;
    verificationFilter =
        prefs.getString(_verificationFilterKey) ?? verificationFilter;
    _snapAddedFilter = _parseAddedFilter(prefs.getString(_snapAddedKey));
    _instaAddedFilter = _parseAddedFilter(prefs.getString(_instaAddedKey));
    selectedSortOption = prefs.getString(_sortOptionKey) ?? selectedSortOption;
    isAscending = prefs.getBool(_sortAscendingKey) ?? isAscending;
    _timeDiffMinMinutes = prefs.getInt(_timeDiffMinKey) ?? _kTimeDiffMinDefault;
    _timeDiffMaxMinutes = prefs.getInt(_timeDiffMaxKey) ?? _kTimeDiffMaxDefault;
    if (_timeDiffMinMinutes > _timeDiffMaxMinutes) {
      final t = _timeDiffMinMinutes;
      _timeDiffMinMinutes = _timeDiffMaxMinutes;
      _timeDiffMaxMinutes = t;
    }
    final savedStates =
        prefs.getStringList(_multiStatesKey) ?? const <String>[];
    _selectedStatesMulti
      ..clear()
      ..addAll(savedStates.where((s) => s != 'All' && states.contains(s)));
  }

  AddedFilter _parseAddedFilter(String? v) {
    switch (v) {
      case 'added':
        return AddedFilter.added;
      case 'notAdded':
        return AddedFilter.notAdded;
      case 'any':
      default:
        return AddedFilter.any;
    }
  }

  String _addedFilterToString(AddedFilter v) {
    switch (v) {
      case AddedFilter.added:
        return 'added';
      case AddedFilter.notAdded:
        return 'notAdded';
      case AddedFilter.any:
      default:
        return 'any';
    }
  }

  Future<void> _persistFilters() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_filtersCollapsedKey, _filtersCollapsed);
    await prefs.setString(_verificationFilterKey, verificationFilter);
    await prefs.setString(
        _snapAddedKey, _addedFilterToString(_snapAddedFilter));
    await prefs.setString(
        _instaAddedKey, _addedFilterToString(_instaAddedFilter));
    await prefs.setStringList(_multiStatesKey, _selectedStatesMulti.toList());
    await prefs.setString(_sortOptionKey, selectedSortOption);
    await prefs.setBool(_sortAscendingKey, isAscending);
    await prefs.setInt(_timeDiffMinKey, _timeDiffMinMinutes);
    await prefs.setInt(_timeDiffMaxKey, _timeDiffMaxMinutes);
  }

  // ---------------- Import helpers ----------------
  Future<AssetPathEntity?> _getImportAlbum() async {
    if (_importDirPath == null) return null;
    final paths = await PhotoManager.getAssetPathList(
        type: RequestType.image, hasAll: true);
    final dirName = path.basename(_importDirPath!);
    for (final p in paths) {
      if (p.name == dirName) return p;
    }
    return null;
  }

  Future<PMFilter?> _buildImportFilter() async {
    if (_importDirPath == null) return null;
    final album = await _getImportAlbum();
    if (album == null) return null;
    if (Platform.isAndroid) {
      final id = album.id.replaceAll("'", "''");
      return CustomFilter.sql(
          where: "${CustomColumns.android.bucketId} = '$id'");
    }
    return null;
  }

  // ---------------- Sorting/apply ----------------
  Future<void> _applyFiltersAndSort() async {
    // Helper to evaluate verification filter
    bool passesVerification(ContactEntry e) {
      switch (verificationFilter) {
        case 'Unverified (any)':
          // Show only entries with no verification on any platform
          return (e.verifiedOnSnapAt == null) &&
              (e.verifiedOnInstaAt == null) &&
              (e.verifiedOnDiscordAt == null);
        case 'Unverified: Snapchat':
          return e.verifiedOnSnapAt == null;
        case 'Unverified: Instagram':
          return e.verifiedOnInstaAt == null;
        case 'Unverified: Discord':
          return e.verifiedOnDiscordAt == null;
        case 'All':
        default:
          return true;
      }
    }

    final filtered =
        SearchService.searchEntries(allImages, searchQuery).where((img) {
      final tag = img.state ?? path.basename(path.dirname(img.imagePath));
      // Single-select state filter
      final matchesLegacyState = selectedState == 'All' || tag == selectedState;

      final matchesVerification = passesVerification(img);

      bool matchSnap;
      switch (_snapAddedFilter) {
        case AddedFilter.added:
          matchSnap = img.addedOnSnap == true;
          break;
        case AddedFilter.notAdded:
          matchSnap = img.addedOnSnap != true;
          break;
        case AddedFilter.any:
        default:
          matchSnap = true;
      }

      bool matchInsta;
      switch (_instaAddedFilter) {
        case AddedFilter.added:
          matchInsta = img.addedOnInsta == true;
          break;
        case AddedFilter.notAdded:
          matchInsta = img.addedOnInsta != true;
          break;
        case AddedFilter.any:
        default:
          matchInsta = true;
      }

      bool matchTimeDiff() {
        // If full range, no restriction
        final full = _timeDiffMinMinutes == _kTimeDiffMinDefault &&
            _timeDiffMaxMinutes == _kTimeDiffMaxDefault;
        final off = img.location?.utcOffset;
        if (full) return true;
        if (off == null) return false; // exclude unknown when narrowed
        int normalize(int raw) {
          final abs = raw.abs();
          const maxMinutes = 18 * 60;
          const maxSeconds = 18 * 3600;
          const maxMillis = maxSeconds * 1000;
          const maxMicros = maxMillis * 1000;
          if (abs <= maxMinutes) return raw * 60;
          if (abs <= maxSeconds) return raw;
          if (abs <= maxMillis) return (raw / 1000).round();
          if (abs <= maxMicros) return (raw / 1000000).round();
          return 0;
        }

        final sec = normalize(off);
        final localSec = DateTime.now().timeZoneOffset.inSeconds;
        final deltaMin = ((sec - localSec) / 60).round();
        return deltaMin >= _timeDiffMinMinutes &&
            deltaMin <= _timeDiffMaxMinutes;
      }

      return matchesLegacyState &&
          matchesVerification &&
          matchSnap &&
          matchInsta &&
          matchTimeDiff();
    }).toList();

    // Precompute file sizes once when sorting by size to avoid repeated sync I/O
    if (selectedSortOption == 'Size') {
      for (final e in filtered) {
        _sizeCache.putIfAbsent(e.imagePath, () {
          try {
            final stat = FileStat.statSync(e.imagePath);
            return stat.size;
          } catch (_) {
            return 0;
          }
        });
      }
    }

    int compare(ContactEntry a, ContactEntry b) {
      // Deterministic tie-breakers to keep ordering stable across rebuilds.
      int _tieBreak(ContactEntry a, ContactEntry b) {
        // 1) Basename of image path
        final na = path.basename(a.imagePath);
        final nb = path.basename(b.imagePath);
        var r = na.compareTo(nb);
        if (r != 0) return r;
        // 2) Identifier fallback
        return a.identifier.compareTo(b.identifier);
      }

      int result;
      switch (selectedSortOption) {
        case 'Date found':
          result = a.dateFound.compareTo(b.dateFound);
          if (result == 0) result = _tieBreak(a, b);
          break;
        case 'Size':
          final sa = _sizeCache[a.imagePath] ?? 0;
          final sb = _sizeCache[b.imagePath] ?? 0;
          result = sa.compareTo(sb);
          if (result == 0) result = _tieBreak(a, b);
          break;
        case 'Snap Added Date':
          result = (a.dateAddedOnSnap ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(
                  b.dateAddedOnSnap ?? DateTime.fromMillisecondsSinceEpoch(0));
          if (result == 0) result = _tieBreak(a, b);
          break;
        case 'Instagram Added Date':
          result = (a.dateAddedOnInsta ??
                  DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(
                  b.dateAddedOnInsta ?? DateTime.fromMillisecondsSinceEpoch(0));
          if (result == 0) result = _tieBreak(a, b);
          break;
        case 'Added on Snapchat':
          result = (a.addedOnSnap ? 1 : 0).compareTo(b.addedOnSnap ? 1 : 0);
          if (result == 0) result = _tieBreak(a, b);
          break;
        case 'Added on Instagram':
          result = (a.addedOnInsta ? 1 : 0).compareTo(b.addedOnInsta ? 1 : 0);
          if (result == 0) result = _tieBreak(a, b);
          break;
        case 'Location':
          // Sort by relative timezone delta vs device time.
          int? offA = a.location?.utcOffset;
          int? offB = b.location?.utcOffset;
          int normalize(int raw) {
            final abs = raw.abs();
            const maxMinutes = 18 * 60; // 1080
            const maxSeconds = 18 * 3600; // 64800
            const maxMillis = maxSeconds * 1000; // 64,800,000
            const maxMicros = maxMillis * 1000; // 64,800,000,000
            if (abs <= maxMinutes) return raw * 60; // minutes
            if (abs <= maxSeconds) return raw; // seconds
            if (abs <= maxMillis) return (raw / 1000).round(); // ms
            if (abs <= maxMicros) return (raw / 1000000).round(); // µs
            return 0; // fallback
          }
          int? secA = offA != null ? normalize(offA) : null;
          int? secB = offB != null ? normalize(offB) : null;
          final local = DateTime.now().timeZoneOffset.inSeconds;
          int? deltaA = secA != null ? (secA - local) : null;
          int? deltaB = secB != null ? (secB - local) : null;

          if (deltaA == null && deltaB == null) {
            result = 0;
          } else if (deltaA == null) {
            result = 1; // a (unknown) goes after b
          } else if (deltaB == null) {
            result = -1; // b (unknown) goes after a
          } else {
            result = deltaA.compareTo(deltaB);
            if (result == 0) {
              // Stable tie-breaker by name to ensure deterministic order
              final na = path.basename(a.imagePath);
              final nb = path.basename(b.imagePath);
              result = na.compareTo(nb);
            }
          }
          if (result == 0) {
            // Already ties break by name inside this branch; add identifier fallback.
            result = a.identifier.compareTo(b.identifier);
          }
          break;
        case 'Name':
        default:
          result =
              path.basename(a.imagePath).compareTo(path.basename(b.imagePath));
          if (result == 0) result = a.identifier.compareTo(b.identifier);
      }
      return isAscending ? result : -result;
    }

    filtered.sort(compare);

    setState(() {
      images = filtered;
      currentIndex = 0;
    });

    if (images.isNotEmpty) {
      if (kGalleryPageController.hasClients) {
        kGalleryPageController.jumpToPage(0);
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (kGalleryPageController.hasClients) {
            try {
              kGalleryPageController.jumpToPage(0);
            } catch (_) {}
          }
        });
      }
    }
  }

  Widget _buildInitializationErrorBanner(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade300),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _initializationError ?? 'Initialization error',
                style: TextStyle(color: Colors.orange.shade900),
              ),
            ),
            IconButton(
              tooltip: 'Dismiss',
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() => _initializationError = null),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- Item actions ----------------
  Future<_MoveSelection?> _selectState(String currentState) async {
    String? selected = currentState.isNotEmpty
        ? currentState
        : states.firstWhere((s) => s != 'All', orElse: () => '');
    final controller = TextEditingController(text: selected);
  // Default checkbox: ON by default (user can toggle off)
  bool applyNeverBack = true;
  bool userToggled = false; // track manual user change

    return showDialog<_MoveSelection>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Move to state'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (currentState.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: [
                        const Text('Current:'),
                        const SizedBox(width: 4),
                        Chip(
                            label: Text(currentState),
                            backgroundColor: Colors.grey.shade300),
                      ],
                    ),
                  ),
                if (states.where((s) => s != 'All').isNotEmpty)
                  Wrap(
                    spacing: 6,
                    children: [
                      ...states.where((s) => s != 'All').map((s) => ChoiceChip(
                            label: Text(s),
                            selected: selected == s,
                            onSelected: (_) {
                              setState(() {
                                selected = s;
                                controller.text = s;
                                // Keep current toggle unless user changes it
                                if (!userToggled) {
                                  applyNeverBack = true;
                                }
                              });
                            },
                          )),
                      const SizedBox(height: 8),
                    ],
                  ),
                TextField(
                    controller: controller,
                    decoration: const InputDecoration(labelText: 'State')),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Also mark "never friended back" for moved items'),
                  subtitle: const Text('Resets Added on Snap/Insta/Discord and adds a note'),
                  value: applyNeverBack,
                  onChanged: (v) {
                    setState(() {
                      userToggled = true;
                      applyNeverBack = v ?? false;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () {
                  final state = controller.text.trim();
                  if (state.isEmpty) {
                    Navigator.pop(context);
                  } else {
                    Navigator.pop(context, _MoveSelection(state, applyNeverBack));
                  }
                },
                child: const Text('OK')),
          ],
        ),
      ),
    );
  }

  Future<void> _onMenuOptionSelected(String imagePath, String _option) async {
    final targets = <ContactEntry>[];

    if (selectedImages.isNotEmpty) {
      for (final id in selectedImages) {
        final match = allImages.where((e) => e.identifier == id);
        if (match.isNotEmpty) targets.add(match.first);
      }
    } else {
      final match = allImages.where((e) => e.imagePath == imagePath);
      if (match.isNotEmpty) targets.add(match.first);
    }

    if (targets.isEmpty) return;

    String currentState = '';
    if (targets.isNotEmpty) {
      final firstState = targets.first.state ?? '';
      if (targets.every((e) => e.state == firstState))
        currentState = firstState;
    }

    if (_option == 'move') {
      final selection = await _selectState(currentState);
      if (selection == null || selection.state.isEmpty) return;

      // Determine which of the selected targets are flagged for never-back before clearing state
      final List<ContactEntry> flaggedTargets = selection.applyNeverBack
          ? targets
              .where((e) => _neverBackSelected.contains(e.identifier))
              .toList()
          : const [];

      final now = DateTime.now();
      setState(() {
        for (final entry in targets) {
          entry.state = selection.state;
          // Record moved-to date via a neutral key
          entry.markMovedToArchiveBucket(now, targetState: selection.state);
        }
        // Exit selection mode after a move operation
        selectedImages.clear();
        _neverBackSelected.clear();
        _selectionModeActive = false;
      });

      _updateStates(allImages);
      await _applyFiltersAndSort();

      int changed = 0;
      if (selection.applyNeverBack) {
        changed = flaggedTargets.isNotEmpty
            ? _applyNeverBackToEntries(flaggedTargets)
            : 0;
        if (changed > 0) {
          await _applyFiltersAndSort();
        }
      }
      // Always show a concise summary of what happened
      if (mounted) {
        final moved = targets.length;
        final msg = selection.applyNeverBack
            ? 'Moved $moved. Applied never-back to $changed.'
            : 'Moved $moved.';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  // Applies the Never-Friended-Back automation to the provided entries.
  // Returns the number of entries updated.
  int _applyNeverBackToEntries(List<ContactEntry> targets) {
    final now = DateFormat.yMd().add_jm().format(DateTime.now());
    int changed = 0;
    setState(() {
      for (final entry in targets) {
        final platforms = <String>[];
        if (entry.addedOnSnap) {
          // Only reset the boolean, preserve dates
          entry.addedOnSnap = false;
          platforms.add('Snap');
        }
        if (entry.addedOnInsta) {
          entry.addedOnInsta = false;
          platforms.add('Insta');
        }
        if (entry.addedOnDiscord) {
          entry.addedOnDiscord = false;
          platforms.add('Discord');
        }
        if (platforms.isNotEmpty) {
          final note =
              'Marked as "never friended back" (${platforms.join(', ')}) on $now';
          if (entry.notes == null || entry.notes!.isEmpty) {
            entry.notes = note;
          } else {
            entry.notes = '${entry.notes}\n$note';
          }
          changed++;
        }
      }
    });
    return changed;
  }

  // ---------------- Bulk: mark never-friended-back ----------------
  Future<void> _applyNeverFriendedBack() async {
    if (_neverBackSelected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No tiles flagged for this action.')));
      return;
    }
    final targets = <ContactEntry>[];
    for (final id in _neverBackSelected) {
      final match = allImages.where((e) => e.identifier == id);
      if (match.isNotEmpty) targets.add(match.first);
    }
    if (targets.isEmpty) return;

    final changed = _applyNeverBackToEntries(targets);
    // Clear only the flagged subset; keep any remaining selection
    setState(() {
      selectedImages.removeWhere((id) => _neverBackSelected.contains(id));
      _neverBackSelected.clear();
    });

    await _applyFiltersAndSort();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(changed > 0
            ? 'Updated $changed entr${changed == 1 ? 'y' : 'ies'}'
            : 'No changes applied')));
  }

  // ---------------- Import flow ----------------
  Future<void> _importImages(BuildContext pickerContext) async {
    if (_importDirPath == null) {
      await _changeImportDir();
      if (_importDirPath == null) {
        ScaffoldMessenger.of(pickerContext).showSnackBar(
            const SnackBar(content: Text('No directory selected')));
        return;
      }
    }

    final filter = await _buildImportFilter();
    final ps = await PhotoManager.requestPermissionExtend();
    if (ps != PermissionState.authorized && ps != PermissionState.limited) {
      ScaffoldMessenger.of(pickerContext).showSnackBar(
          const SnackBar(content: Text('Permission not granted')));
      return;
    }

    final maxSel = await _resolveImportMaxSelection();
    final config = AssetPickerConfig(
      requestType: RequestType.image,
      filterOptions: filter,
      maxAssets: maxSel,
      textDelegate: const EnglishAssetPickerTextDelegate(),
    );

    final List<AssetEntity>? assets =
        await AssetPicker.pickAssets(pickerContext, pickerConfig: config);
    if (assets == null || assets.isEmpty) {
      ScaffoldMessenger.of(pickerContext)
          .showSnackBar(const SnackBar(content: Text('No images selected')));
      return;
    }

    final destDir = Directory('/storage/emulated/0/DCIM/Comb');
    await destDir.create(recursive: true);

    final messenger = ScaffoldMessenger.of(pickerContext);
    final total = assets.length;
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(hours: 1),
        content: Row(
          children: const [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator()),
            SizedBox(width: 16),
            Text('Importing images...'),
          ],
        ),
      ),
    );

    final List<ContactEntry> newEntries = [];
    var processed = 0;

    for (final asset in assets) {
      try {
        final origin = await asset.originFile;
        if (origin == null) continue;

        final filename = path.basename(origin.path);
        final destPath = path.join(destDir.path, filename);
        if (File(destPath).existsSync()) {
          debugPrint('File already exists at $destPath, skipping');
          continue;
        }

        try {
          // TODO: Consider using the package media_store_plus instead. It can supposedly
          // do move AND update the MediaStore behind the Gallery app in one move.
          await origin.rename(destPath);
        } catch (_) {
          await origin.copy(destPath);
          try {
            await origin.delete();
          } catch (_) {}
        }

        // Ask MediaScanner to index the new file so Gallery updates
        await MediaScanUtils.scanPaths([destPath]);
        await MediaScanUtils.scanPaths([origin.path]);

        final id = path.basenameWithoutExtension(filename);
        var entry = ContactEntry(
          identifier: id,
          imagePath: destPath,
          dateFound: File(destPath).lastModifiedSync(),
          json: {SubKeys.State: 'Comb'},
          isNewImport: true,
        );

        final result =
            await ChatGPTService.processImage(imageFile: File(destPath));
        if (result != null) {
          entry = postProcessChatGptResult(entry, result, save: false);
        }

        await StorageUtils.save(entry);
        StorageUtils.filePaths[id] = destPath;
        newEntries.add(entry);
      } catch (e) {
        debugPrint('Failed to import ${asset.id}: $e');
      }

      processed++;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(hours: 1),
            content: Row(
              children: [
                const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator()),
                const SizedBox(width: 16),
                Text('Importing images... $processed/$total'),
              ],
            ),
          ),
        );
    }

    await StorageUtils.writeJson(StorageUtils.filePaths);

    if (newEntries.isNotEmpty) {
      setState(() => allImages.addAll(newEntries));
      _updateStates(allImages);
      await _applyFiltersAndSort();
      await StorageUtils.syncLocalAndCloud();
    }

    messenger.hideCurrentSnackBar();
    final imported = newEntries.length;
    messenger.showSnackBar(
      SnackBar(
        content: Text(imported > 0
            ? 'Imported $imported image${imported == 1 ? '' : 's'}'
            : 'No new images imported'),
      ),
    );
  }
}

class _AddedFilterRow extends StatelessWidget {
  final String label;
  final AddedFilter value;
  final ValueChanged<AddedFilter> onChanged;

  const _AddedFilterRow(
      {required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Any'),
              selected: value == AddedFilter.any,
              onSelected: (_) => onChanged(AddedFilter.any),
            ),
            ChoiceChip(
              label: const Text('Added'),
              selected: value == AddedFilter.added,
              onSelected: (_) => onChanged(AddedFilter.added),
            ),
            ChoiceChip(
              label: const Text('Not added'),
              selected: value == AddedFilter.notAdded,
              onSelected: (_) => onChanged(AddedFilter.notAdded),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Divider(color: theme.dividerColor.withOpacity(0.4)),
      ],
    );
  }
}

class _FixedHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double minHeight;
  final double maxHeight;
  final Widget child;

  _FixedHeaderDelegate(
      {required this.minHeight, required this.maxHeight, required this.child});

  @override
  double get minExtent => minHeight;

  @override
  double get maxExtent => maxHeight;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(color: Theme.of(context).colorScheme.surface, child: child);
  }

  @override
  bool shouldRebuild(covariant _FixedHeaderDelegate oldDelegate) {
    return minHeight != oldDelegate.minHeight ||
        maxHeight != oldDelegate.maxHeight ||
        child != oldDelegate.child;
  }
}

class _Badge extends StatelessWidget {
  final int count;
  final Color color;
  const _Badge({required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final text = count > 99 ? '99+' : '$count';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
      ),
      child: Text(text,
          style: const TextStyle(
              fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black)),
    );
  }
}
