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
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:PhotoWordFind/screens/gallery/review_viewer.dart';

class ImageGalleryScreen extends StatefulWidget {
  const ImageGalleryScreen({super.key});

  @override
  State<ImageGalleryScreen> createState() => _ImageGalleryScreenState();
}

class _ImageGalleryScreenState extends State<ImageGalleryScreen>
    with TickerProviderStateMixin {
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
    'Added on Instagram'
  ];
  String selectedState = 'All';
  List<String> states = ['All'];

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

  // View state
  int currentIndex = 0;
  bool isAscending = true;
  bool _controlsExpanded = false; // compact by default
  bool _isInitializing = true;
  String? _initializationError;

  // Sync
  bool _syncing = false;
  DateTime? _lastSyncTime;

  // Debounce
  Timer? _searchDebounce;

  // Feature flags
  static const bool kUseCompactHeader = true;

  // Persisted keys
  static const String _lastStateKey = 'last_selected_state';
  static const String _importDirKey = 'import_directory';
  String? _importDirPath;

  @override
  void initState() {
    super.initState();
    CloudUtils.progressCallback = ({double? value, String? message, bool done = false, bool error = false}) {
      // Reserved hook for future UI progress
    };
    _initializeApp();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ---------------- Initialization ----------------
  Future<void> _initializeApp() async {
    try {
      await _ensureSignedIn();
      await _loadImportDirectory();
      await _loadImages();
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
      return true;
    } catch (e) {
      _initializationError = 'Sign-in failed: $e';
      return false;
    }
  }

  Future<void> _forceSync({bool fromPull = false}) async {
    if (_syncing) return;
    setState(() => _syncing = true);
    final messenger = ScaffoldMessenger.of(context);
    void show(String msg) => messenger.showSnackBar(SnackBar(content: Text(msg)));
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
    final List<ContactEntry> loaded = [];
    for (final id in StorageUtils.getKeys()) {
      final contact = await StorageUtils.get(id);
      if (contact != null) loaded.add(contact);
    }
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
          dateFound: File(value).existsSync() ? File(value).lastModifiedSync() : DateTime.now(),
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

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final navContext = context;

    final body = _isInitializing
        ? _buildInitializing()
        : _buildMainContent(navContext);

    return Scaffold(
      appBar: kUseCompactHeader
          ? null
          : AppBar(title: const Text('Image Gallery'), actions: _buildAppBarActions(navContext)),
      body: body,
      floatingActionButton: _isInitializing
          ? null
          : selectedImages.isNotEmpty
              ? FloatingActionButton(
                  onPressed: () => _onMenuOptionSelected('', 'move'),
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
    if (!kUseCompactHeader) {
      return LayoutBuilder(builder: (context, constraints) {
        final screenHeight = constraints.maxHeight;
        return Column(
          children: [
            if (_initializationError != null) _buildInitializationErrorBanner(context),
            _buildControls(),
            Expanded(
              child: ImageGallery(
                images: images,
                selectedImages: selectedImages,
                sortOption: selectedSortOption,
                onImageSelected: (String id) {
                  setState(() {
                    if (selectedImages.contains(id)) {
                      selectedImages.remove(id);
                    } else {
                      selectedImages.add(id);
                    }
                  });
                },
                onMenuOptionSelected: _onMenuOptionSelected,
                galleryHeight: screenHeight,
                onPageChanged: (idx) => setState(() => currentIndex = idx),
                currentIndex: currentIndex,
              ),
            ),
          ],
        );
      });
    }

    // Compact header with CustomScrollView and slivers
    return CustomScrollView(
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
        SliverPersistentHeader(
          pinned: true,
          delegate: _FixedHeaderDelegate(
            minHeight: 120,
            maxHeight: 120,
            child: _buildSlimFilterBar(),
          ),
        ),
        SliverImageGallery(
          images: images,
          selectedImages: selectedImages,
          sortOption: selectedSortOption,
          onImageSelected: (String id) {
            setState(() {
              if (selectedImages.contains(id)) {
                selectedImages.remove(id);
              } else {
                selectedImages.add(id);
              }
            });
          },
          onMenuOptionSelected: _onMenuOptionSelected,
        ),
      ],
    );
  }

  List<Widget> _buildAppBarActions(BuildContext navContext) {
    return [
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
                TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(dialogCtx, true), child: const Text('Switch')),
              ],
            ),
          );
          if (proceed == true) {
            await UiMode.switchTo(false);
          }
        },
      ),
      if (_isInitializing)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0),
          child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
        )
      else
        FutureBuilder<bool>(
          future: CloudUtils.isSignedin(),
          builder: (ctx, snap) {
            final signed = snap.data == true;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Icon(signed ? Icons.cloud_done : Icons.cloud_off, color: signed ? Colors.green : Colors.redAccent),
            );
          },
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
                    setState(() {});
                  },
                  lastSyncTime: _lastSyncTime,
                  syncing: _syncing,
                  signInFailed: _initializationError != null,
                ),
              ),
            );
          },
        ),
    ];
  }

  Widget _buildSlimFilterBar() {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: chips (scrollable to avoid overflow)
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                // State chip
                InkWell(
                  onTap: _showStatePicker,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.label, size: 18),
                        SizedBox(width: 6),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Center(child: Text(selectedState, style: const TextStyle(fontWeight: FontWeight.w600))),
                const SizedBox(width: 12),

                // Verification chip
                Tooltip(
                  message: 'Verification filter',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      final res = await showModalBottomSheet<String>(
                        context: context,
                        builder: (ctx) => SafeArea(
                          child: ListView(
                            shrinkWrap: true,
                            children: [
                              const ListTile(title: Text('Verification filter', style: TextStyle(fontWeight: FontWeight.bold))),
                              ...verificationOptions.map((o) => RadioListTile<String>(
                                    value: o,
                                    groupValue: verificationFilter,
                                    title: Text(o),
                                    onChanged: (v) => Navigator.pop(ctx, v),
                                  )),
                            ],
                          ),
                        ),
                      );
                      if (res != null) {
                        setState(() => verificationFilter = res);
                        await _filterImages();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondary.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.verified_user, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            verificationFilter == 'All' ? 'Verification: All' : verificationFilter,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Review button
                FilledButton.icon(
                  onPressed: () async {
                    if (verificationFilter == 'All') {
                      setState(() => verificationFilter = 'Unverified (any)');
                      await _filterImages();
                    }
                    if (images.isNotEmpty) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ReviewViewer(images: images, initialIndex: 0, sortOption: selectedSortOption),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No unverified entries in this state')));
                    }
                  },
                  icon: const Icon(Icons.rule_folder_outlined),
                  label: const Text('Review unverified'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Row 2: search + sort + order
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    ),
                    onChanged: (value) {
                      searchQuery = value;
                      _searchDebounce?.cancel();
                      _searchDebounce = Timer(const Duration(milliseconds: 220), () {
                        if (!mounted) return;
                        _filterImages();
                      });
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
                          const ListTile(title: Text('Sort by', style: TextStyle(fontWeight: FontWeight.bold))),
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

  Widget _buildControls() {
    return RefreshIndicator(
      onRefresh: () => _forceSync(fromPull: true),
      displacement: 56,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 300),
          child: _controlsExpanded ? _buildExpandedControls() : _buildMinimizedControls(),
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
            items: states.map((dir) => DropdownMenuItem<String>(value: dir, child: Text(dir))).toList(),
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
            items: sortOptions.map((o) => DropdownMenuItem<String>(value: o, child: Text(o))).toList(),
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
                value: sortOptions.contains(selectedSortOption) ? selectedSortOption : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Sort by',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: sortOptions.map((o) => DropdownMenuItem<String>(value: o, child: Text(o))).toList(),
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
              child: IconButton(icon: const Icon(Icons.filter_list), onPressed: _showStatePicker),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: 'Search',
              child: IconButton(icon: const Icon(Icons.search), onPressed: _showSearchDialog),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Apply')),
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
            const ListTile(title: Text('Filter by state', style: TextStyle(fontWeight: FontWeight.bold))),
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
        decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), shape: BoxShape.circle),
        child: IconButton(
          icon: AnimatedRotation(
            turns: isAscending ? 0 : 0.5,
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.arrow_upward, color: Colors.blue),
          ),
          onPressed: () async {
            isAscending = !isAscending;
            await _applyFiltersAndSort();
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

  // ---------------- Import helpers ----------------
  Future<AssetPathEntity?> _getImportAlbum() async {
    if (_importDirPath == null) return null;
    final paths = await PhotoManager.getAssetPathList(type: RequestType.image, hasAll: true);
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
      return CustomFilter.sql(where: "${CustomColumns.android.bucketId} = '$id'");
    }
    return null;
  }

  // ---------------- Sorting/apply ----------------
  Future<void> _applyFiltersAndSort() async {
  bool passesVerification(ContactEntry e) {
      switch (verificationFilter) {
        case 'Unverified (any)':
      // Show only entries with no verification on any platform
      return (e.verifiedOnSnapAt == null) && (e.verifiedOnInstaAt == null) && (e.verifiedOnDiscordAt == null);
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

    final filtered = SearchService.searchEntries(allImages, searchQuery).where((img) {
      final tag = img.state ?? path.basename(path.dirname(img.imagePath));
      final matchesState = selectedState == 'All' || tag == selectedState;
      return matchesState && passesVerification(img);
    }).toList();

    int compare(ContactEntry a, ContactEntry b) {
      int result;
      switch (selectedSortOption) {
        case 'Date found':
          result = a.dateFound.compareTo(b.dateFound);
          break;
        case 'Size':
          result = File(a.imagePath).lengthSync().compareTo(File(b.imagePath).lengthSync());
          break;
        case 'Snap Added Date':
          result = (a.dateAddedOnSnap ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(b.dateAddedOnSnap ?? DateTime.fromMillisecondsSinceEpoch(0));
          break;
        case 'Instagram Added Date':
          result = (a.dateAddedOnInsta ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(b.dateAddedOnInsta ?? DateTime.fromMillisecondsSinceEpoch(0));
          break;
        case 'Added on Snapchat':
          result = (a.addedOnSnap ? 1 : 0).compareTo(b.addedOnSnap ? 1 : 0);
          break;
        case 'Added on Instagram':
          result = (a.addedOnInsta ? 1 : 0).compareTo(b.addedOnInsta ? 1 : 0);
          break;
        case 'Name':
        default:
          result = path.basename(a.imagePath).compareTo(path.basename(b.imagePath));
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
  Future<String?> _selectState(String currentState) async {
    String? selected = currentState.isNotEmpty
        ? currentState
        : states.firstWhere((s) => s != 'All', orElse: () => '');
    final controller = TextEditingController(text: selected);

    return showDialog<String>(
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
                        Chip(label: Text(currentState), backgroundColor: Colors.grey.shade300),
                      ],
                    ),
                  ),
                if (states.where((s) => s != 'All').isNotEmpty)
                  Wrap(
                    spacing: 6,
                    children: [
                      ...states
                          .where((s) => s != 'All')
                          .map((s) => ChoiceChip(
                                label: Text(s),
                                selected: selected == s,
                                onSelected: (_) {
                                  setState(() {
                                    selected = s;
                                    controller.text = s;
                                  });
                                },
                              )),
                      const SizedBox(height: 8),
                    ],
                  ),
                TextField(controller: controller, decoration: const InputDecoration(labelText: 'State')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('OK')),
          ],
        ),
      ),
    );
  }

  Future<void> _onMenuOptionSelected(String imagePath, String option) async {
    if (option != 'move') return;
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
      if (targets.every((e) => e.state == firstState)) currentState = firstState;
    }

    final newState = await _selectState(currentState);
    if (newState == null || newState.isEmpty) return;

    setState(() {
      for (final entry in targets) {
        entry.state = newState;
      }
      selectedImages.clear();
    });

    _updateStates(allImages);
    await _applyFiltersAndSort();
  }

  // ---------------- Import flow ----------------
  Future<void> _importImages(BuildContext pickerContext) async {
    if (_importDirPath == null) {
      await _changeImportDir();
      if (_importDirPath == null) {
        ScaffoldMessenger.of(pickerContext).showSnackBar(const SnackBar(content: Text('No directory selected')));
        return;
      }
    }

    final filter = await _buildImportFilter();
    final ps = await PhotoManager.requestPermissionExtend();
    if (ps != PermissionState.authorized && ps != PermissionState.limited) {
      ScaffoldMessenger.of(pickerContext).showSnackBar(const SnackBar(content: Text('Permission not granted')));
      return;
    }

    final config = AssetPickerConfig(
      requestType: RequestType.image,
      filterOptions: filter,
      textDelegate: const EnglishAssetPickerTextDelegate(),
    );

    final List<AssetEntity>? assets = await AssetPicker.pickAssets(pickerContext, pickerConfig: config);
    if (assets == null || assets.isEmpty) {
      ScaffoldMessenger.of(pickerContext).showSnackBar(const SnackBar(content: Text('No images selected')));
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
          await origin.rename(destPath);
        } catch (_) {
          await origin.copy(destPath);
          try {
            await origin.delete();
          } catch (_) {}
        }

        final id = path.basenameWithoutExtension(filename);
        var entry = ContactEntry(
          identifier: id,
          imagePath: destPath,
          dateFound: File(destPath).lastModifiedSync(),
          json: {SubKeys.State: 'Comb'},
          isNewImport: true,
        );

        final result = await ChatGPTService.processImage(imageFile: File(destPath));
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
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator()),
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
        content: Text(imported > 0 ? 'Imported $imported image${imported == 1 ? '' : 's'}' : 'No new images imported'),
      ),
    );
  }

}

class _FixedHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double minHeight;
  final double maxHeight;
  final Widget child;

  _FixedHeaderDelegate({required this.minHeight, required this.maxHeight, required this.child});

  @override
  double get minExtent => minHeight;

  @override
  double get maxExtent => maxHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(color: Theme.of(context).colorScheme.surface, child: child);
  }

  @override
  bool shouldRebuild(covariant _FixedHeaderDelegate oldDelegate) {
    return minHeight != oldDelegate.minHeight || maxHeight != oldDelegate.maxHeight || child != oldDelegate.child;
  }
}

