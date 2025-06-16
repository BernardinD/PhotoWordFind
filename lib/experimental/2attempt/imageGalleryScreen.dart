import 'dart:convert';
import 'dart:io';

import 'package:PhotoWordFind/models/contactEntry.dart';
import 'package:PhotoWordFind/social_icons.dart';
import 'package:PhotoWordFind/utils/storage_utils.dart';
import 'package:PhotoWordFind/services/search_service.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:PhotoWordFind/widgets/note_dialog.dart';
import 'package:PhotoWordFind/widgets/confirmation_dialog.dart';
import 'package:intl/intl.dart';

final PageController _pageController =
    PageController(viewportFraction: 0.8); // Gives a gallery feel

class ImageGalleryScreen extends StatefulWidget {
  @override
  _ImageGalleryScreenState createState() => _ImageGalleryScreenState();
}

class _ImageGalleryScreenState extends State<ImageGalleryScreen>
    with TickerProviderStateMixin {
  String searchQuery = '';
  String selectedSortOption = 'Name'; // Default value from the list
  List<String> sortOptions = [
    'Name',
    'Date found',
    'Size',
    'Snap Added Date',
    'Instagram Added Date',
    'Added on Snapchat',
    'Added on Instagram'
  ]; // Add your sort options here
  String selectedState = 'All';
  List<String> states = ['All'];
  List<ContactEntry> images = [];
  List<ContactEntry> allImages = [];
  List<String> selectedImages = [];

  int currentIndex = 0;
  static const String _lastStateKey = 'last_selected_state';

  // State variable to track the selected sort order
  bool isAscending = true; // Default sorting order

  // Add a setting to control which loading method to use
  bool useJsonFileForLoading = false; // Set to true to load from JSON file

  bool _controlsExpanded = true; // Tracks whether the controls are minimized

  @override
  void initState() {
    super.initState();
    if (useJsonFileForLoading) {
      _loadImagesFromJsonFile();
    } else {
      _loadImagesFromPreferences();
    }
  }

  Future<void> _loadImagesFromPreferences() async {
    // Read the image path map from the JSON file (simulating a separate storage location)
    List<ContactEntry> loadedImages = [];

    // Fetch each contact directly from Hive using the keys list to avoid
    // reading the entire box twice.
    for (final identifier in StorageUtils.getKeys()) {
      final contactEntry = await StorageUtils.get(identifier);
      if (contactEntry != null) {
        loadedImages.add(contactEntry);
      }
    }
    allImages = loadedImages;
    _updateStates(allImages);
    await _restoreLastSelectedState();
    await _applyFiltersAndSort();
  }

  Future<void> _loadImagesFromJsonFile() async {
    // Read the image path map from the JSON file
    final Map<String, dynamic> fileMap = await StorageUtils.readJson();
    List<ContactEntry> loadedImages = [];
    for (final entry in fileMap.entries) {
      final identifier = entry.key;
      final value = entry.value;
      // If the value is just a path string, create a minimal ContactEntry
      if (value is String) {
        loadedImages.add(ContactEntry(
          identifier: identifier,
          imagePath: value,
          dateFound: File(value).existsSync()
              ? File(value).lastModifiedSync()
              : DateTime.now(),
          json: {'imagePath': value},
        ));
      } else if (value is Map<String, dynamic>) {
        // If the value is a full contact JSON, use fromJson
        final imagePath = value['imagePath'] ?? '';
        loadedImages.add(ContactEntry.fromJson(
          identifier,
          imagePath,
          value,
        ));
      }
    }
    allImages = loadedImages;
    _updateStates(allImages);
    await _restoreLastSelectedState();
    await _applyFiltersAndSort();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: (context, child) {
        return ResponsiveBreakpoints.builder(
          child: child!,
          breakpoints: [
            const Breakpoint(start: 0, end: 600, name: MOBILE),
            const Breakpoint(start: 601, end: 1200, name: TABLET),
            const Breakpoint(start: 1201, end: double.infinity, name: DESKTOP),
          ],
        );
      },
      home: Scaffold(
        appBar: AppBar(title: Text('Image Gallery')),
        body: LayoutBuilder(builder: (context, constraints) {
          double screenHeight = constraints.maxHeight;
          return Column(
            children: [
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
                  onMenuOptionSelected: (String imagePath, String option) {
                    // Handle image option
                  },
                  galleryHeight: screenHeight,
                  onPageChanged: (idx) {
                    setState(() {
                      currentIndex = idx;
                    });
                  },
                  currentIndex: currentIndex,
                ),
              ),
            ],
          );
        }),
        floatingActionButton: selectedImages.isNotEmpty
            ? FloatingActionButton(
                onPressed: () {
                  // Trigger move operation
                  // Optionally show confirmation dialog here
                },
                child: Icon(Icons.move_to_inbox),
              )
            : null,
        persistentFooterButtons: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Container(
              width: MediaQuery.of(context).size.width * 1.20,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SocialIcon.snapchatIconButton!,
                  Spacer(),
                  SocialIcon.galleryIconButton!,
                  Spacer(),
                  SocialIcon.bumbleIconButton!,
                  Spacer(),
                  FloatingActionButton(
                    heroTag: null,
                    tooltip: 'Change current directory',
                    onPressed: null, //changeDir,
                    child: Icon(Icons.drive_folder_upload),
                  ),
                  Spacer(),
                  SocialIcon.instagramIconButton!,
                  Spacer(),
                  SocialIcon.discordIconButton!,
                  Spacer(),
                  SocialIcon.kikIconButton!,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return AnimatedSize(
        duration: const Duration(milliseconds: 300),
        child: _controlsExpanded
            ? _buildExpandedControls()
            : _buildMinimizedControls());
  }

  Widget _buildExpandedControls() {
    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 500;
      final children = <Widget>[
        Expanded(
          child: DropdownButtonFormField<String>(
            value: selectedState,
            decoration: InputDecoration(
              labelText: 'State',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            items: states
                .map((dir) => DropdownMenuItem<String>(
                      value: dir,
                      child: Text(dir),
                    ))
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
            decoration: InputDecoration(
              hintText: 'Search',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (value) async {
              searchQuery = value;
              await _filterImages();
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<String>(
            value: selectedSortOption,
            decoration: InputDecoration(
              labelText: 'Sort by',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            items: sortOptions
                .map((option) => DropdownMenuItem<String>(
                      value: option,
                      child: Text(option),
                    ))
                .toList(),
            onChanged: (value) async {
              selectedSortOption = value!;
              await _applyFiltersAndSort();
            },
          ),
        ),
        const SizedBox(width: 8),
        _buildOrderToggle(),
      ];

      Widget content = isWide
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
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
                  onPressed: () {
                    setState(() => _controlsExpanded = false);
                  },
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: selectedSortOption,
                decoration: const InputDecoration(
                  labelText: 'Sort by',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: sortOptions
                    .map((option) => DropdownMenuItem<String>(
                          value: option,
                          child: Text(option),
                        ))
                    .toList(),
                onChanged: (value) async {
                  selectedSortOption = value!;
                  await _applyFiltersAndSort();
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.expand_more),
              onPressed: () {
                setState(() => _controlsExpanded = true);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
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
    });
  }

  Future<void> _restoreLastSelectedState() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(_lastStateKey);
    if (last != null && states.contains(last)) {
      selectedState = last;
    }
  }

  Future<void> _saveLastSelectedState(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastStateKey, value);
  }

  Future<void> _applyFiltersAndSort() async {
    List<ContactEntry> filtered =
        (await SearchService.searchEntriesWithOcr(allImages, searchQuery))
            .where((img) {
      final tag = img.state ?? path.basename(path.dirname(img.imagePath));
      final matchesState = selectedState == 'All' || tag == selectedState;
      return matchesState;
    }).toList();

    int compare(ContactEntry a, ContactEntry b) {
      int result;
      switch (selectedSortOption) {
        case 'Date found':
          result = a.dateFound.compareTo(b.dateFound);
          break;
        case 'Size':
          result = File(a.imagePath)
              .lengthSync()
              .compareTo(File(b.imagePath).lengthSync());
          break;
        case 'Snap Added Date':
          DateTime aDate =
              a.dateAddedOnSnap ?? DateTime.fromMillisecondsSinceEpoch(0);
          DateTime bDate =
              b.dateAddedOnSnap ?? DateTime.fromMillisecondsSinceEpoch(0);
          result = aDate.compareTo(bDate);
          break;
        case 'Instagram Added Date':
          DateTime aDate =
              a.dateAddedOnInsta ?? DateTime.fromMillisecondsSinceEpoch(0);
          DateTime bDate =
              b.dateAddedOnInsta ?? DateTime.fromMillisecondsSinceEpoch(0);
          result = aDate.compareTo(bDate);
          break;
        case 'Added on Snapchat':
          result = (a.addedOnSnap ? 1 : 0).compareTo(b.addedOnSnap ? 1 : 0);
          break;
        case 'Added on Instagram':
          result = (a.addedOnInsta ? 1 : 0).compareTo(b.addedOnInsta ? 1 : 0);
          break;
        case 'Name':
        default:
          result =
              path.basename(a.imagePath).compareTo(path.basename(b.imagePath));
      }
      return isAscending ? result : -result;
    }

    filtered.sort(compare);

    setState(() {
      images = filtered;
      currentIndex = 0;
    });
    _pageController.jumpToPage(0);
  }
}

// Updated ImageGallery Widget
class ImageGallery extends StatelessWidget {
  final List<ContactEntry> images;
  final List<String> selectedImages;
  final Function(String) onImageSelected;
  final Function(String, String) onMenuOptionSelected;
  final double galleryHeight; // New dynamic height parameter
  final ValueChanged<int> onPageChanged;
  final int currentIndex;
  final String sortOption;

  ImageGallery({
    required this.images,
    required this.selectedImages,
    required this.onImageSelected,
    required this.onMenuOptionSelected,
    required this.galleryHeight,
    required this.onPageChanged,
    required this.currentIndex,
    required this.sortOption,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: galleryHeight,
      child: Stack(
        children: [
          ScrollbarTheme(
            data: ScrollbarThemeData(
              thumbColor: WidgetStateProperty.all(Colors.blueAccent),
              thickness: WidgetStateProperty.all(8.0),
              radius: Radius.circular(8),
              trackColor: WidgetStateProperty.all(Colors.grey.withOpacity(0.3)),
              trackBorderColor: WidgetStateProperty.all(Colors.transparent),
            ),
            child: Scrollbar(
              thumbVisibility: true,
              interactive: true,
              thickness: 10,
              controller: _pageController, // Use the same controller here
              child: PageView.builder(
                controller: _pageController,
                itemCount: images.length,
                onPageChanged: onPageChanged,
                itemBuilder: (context, index) {
                  return ImageTile(
                    imagePath: images[index].imagePath,
                    isSelected:
                        selectedImages.contains(images[index].identifier),
                    extractedText: images[index].extractedText ?? "",
                    identifier: images[index].identifier,
                    sortOption: sortOption,
                    onSelected: onImageSelected,
                    onMenuOptionSelected: onMenuOptionSelected,
                    contact: images[index],
                  );
                },
              ),
            ),
          ),
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${currentIndex + 1} / ${images.length}',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Updated ImageTile Widget with Selection
class ImageTile extends StatefulWidget {
  final String imagePath;
  final bool isSelected;
  final String extractedText;
  final String identifier;
  final String sortOption;
  final Function(String) onSelected;
  final Function(String, String) onMenuOptionSelected;
  final ContactEntry contact;

  ImageTile({
    required this.imagePath,
    required this.isSelected,
    required this.extractedText,
    required this.identifier,
    required this.sortOption,
    required this.onSelected,
    required this.onMenuOptionSelected,
    required this.contact,
  });

  @override
  _ImageTileState createState() => _ImageTileState();
}

class _ImageTileState extends State<ImageTile> {
  String get _truncatedText {
    const maxChars = 120;
    if (widget.extractedText.length <= maxChars) return widget.extractedText;
    return '${widget.extractedText.substring(0, maxChars)}...';
  }

  String get _displayLabel {
    switch (widget.sortOption) {
      case 'Date found':
        return DateFormat.yMd().format(widget.contact.dateFound);
      case 'Snap Added Date':
        final snapDate = widget.contact.dateAddedOnSnap;
        return snapDate != null
            ? DateFormat.yMd().format(snapDate)
            : 'No date';
      case 'Instagram Added Date':
        final instaDate = widget.contact.dateAddedOnInsta;
        return instaDate != null
            ? DateFormat.yMd().format(instaDate)
            : 'No date';
      case 'Added on Snapchat':
        return widget.contact.addedOnSnap ? 'Added' : 'Not Added';
      case 'Added on Instagram':
        return widget.contact.addedOnInsta ? 'Added' : 'Not Added';
      case 'Name':
        return widget.contact.name ?? widget.identifier;
      default:
        return widget.identifier;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showDetailsDialog(context),
      onLongPress: () => widget.onSelected(widget.identifier),
      child: LayoutBuilder(builder: (context, constraints) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          width: constraints.maxWidth * 0.8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: widget.isSelected
                ? Border.all(color: Colors.blueAccent, width: 3)
                : null,
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 6,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                Positioned.fill(
                  child: PhotoView(
                    imageProvider: FileImage(File(widget.imagePath)),
                    backgroundDecoration:
                        const BoxDecoration(color: Colors.white),
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.covered * 2.5,
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ConstrainedBox(
                        constraints:
                            BoxConstraints(maxWidth: constraints.maxWidth - 50),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 2, horizontal: 6),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _displayLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: () => widget.onSelected(widget.identifier),
                        child: Icon(
                          widget.isSelected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: widget.isSelected
                              ? Colors.blueAccent
                              : Colors.grey,
                          size: 28,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black54],
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _truncatedText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        if (widget.contact.snapUsername?.isNotEmpty ?? false)
                          IconButton(
                            iconSize: 22,
                            color: Colors.white,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                                width: 36, height: 36),
                            onPressed: () => _openSocial(SocialType.Snapchat,
                                widget.contact.snapUsername!),
                            icon: SocialIcon.snapchatIconButton!.socialIcon,
                          ),
                        if (widget.contact.instaUsername?.isNotEmpty ?? false)
                          IconButton(
                            iconSize: 22,
                            color: Colors.white,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                                width: 36, height: 36),
                            onPressed: () => _openSocial(SocialType.Instagram,
                                widget.contact.instaUsername!),
                            icon: SocialIcon.instagramIconButton!.socialIcon,
                          ),
                        if (widget.contact.discordUsername?.isNotEmpty ?? false)
                          IconButton(
                            iconSize: 22,
                            color: Colors.white,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                                width: 36, height: 36),
                            onPressed: () => _openSocial(SocialType.Discord,
                                widget.contact.discordUsername!),
                            icon: SocialIcon.discordIconButton!.socialIcon,
                          ),
                        IconButton(
                          iconSize: 22,
                          color: Colors.white,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                              width: 36, height: 36),
                          icon: const Icon(Icons.note_alt_outlined),
                          onPressed: () async {
                            await showNoteDialog(context,
                                widget.contact.identifier, widget.contact,
                                existingNotes: widget.contact.notes);
                          },
                        ),
                        IconButton(
                          iconSize: 22,
                          color: Colors.white,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                              width: 36, height: 36),
                          icon: const Icon(Icons.edit),
                          onPressed: () => _editUsernames(context),
                        ),
                        IconButton(
                          iconSize: 22,
                          color: Colors.white,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                              width: 36, height: 36),
                          icon: const Icon(Icons.more_vert),
                          onPressed: () =>
                              _showPopupMenu(context, widget.imagePath),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  void _showPopupMenu(BuildContext context, String imagePath) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: Icon(Icons.info),
              title: Text('View Details'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showDetailsDialog(context);
              },
            ),
            if (widget.contact.snapUsername?.isNotEmpty ?? false)
              ListTile(
                leading: Icon(Icons.chat_bubble),
                title: Text('Open on Snap'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openSocial(
                      SocialType.Snapchat, widget.contact.snapUsername!);
                },
              ),
            if (widget.contact.instaUsername?.isNotEmpty ?? false)
              ListTile(
                leading: Icon(Icons.camera_alt),
                title: Text('Open on Insta'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openSocial(
                      SocialType.Instagram, widget.contact.instaUsername!);
                },
              ),
            if (widget.contact.discordUsername?.isNotEmpty ?? false)
              ListTile(
                leading: Icon(Icons.discord),
                title: Text('Open on Discord'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openSocial(
                      SocialType.Discord, widget.contact.discordUsername!);
                },
              ),
            if (widget.contact.addedOnSnap)
              ListTile(
                leading: Icon(Icons.refresh),
                title: Text('Mark Snap Unadded'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  bool res = await _confirm(context);
                  if (res) widget.contact.resetSnapchatAdd();
                },
              ),
            if (widget.contact.addedOnInsta)
              ListTile(
                leading: Icon(Icons.refresh),
                title: Text('Mark Insta Unadded'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  bool res = await _confirm(context);
                  if (res) widget.contact.resetInstagramAdd();
                },
              ),
            if (widget.contact.addedOnDiscord)
              ListTile(
                leading: Icon(Icons.refresh),
                title: Text('Mark Discord Unadded'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  bool res = await _confirm(context);
                  if (res) widget.contact.resetDiscordAdd();
                },
              ),
            ListTile(
              leading: Icon(Icons.note_alt_outlined),
              title: Text('Edit Notes'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await showNoteDialog(
                    context, widget.contact.identifier, widget.contact,
                    existingNotes: widget.contact.notes);
              },
            ),
            ListTile(
              leading: Icon(Icons.move_to_inbox),
              title: Text('Move'),
              onTap: () {
                widget.onMenuOptionSelected(imagePath, 'move');
                Navigator.pop(sheetContext);
              },
            ),
          ],
        );
      },
    );
  }

  void _showDetailsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              constraints: BoxConstraints(maxHeight: 300),
              child: PhotoView(
                imageProvider: FileImage(File(widget.imagePath)),
                backgroundDecoration: BoxDecoration(color: Colors.white),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 2.5,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Text(
                widget.extractedText.isNotEmpty
                    ? widget.extractedText
                    : 'No text found',
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirm(BuildContext context,
      {String message = 'Are you sure?'}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialog(message: message),
    );
    return result ?? false;
  }

  Future<void> _editUsernames(BuildContext context) async {
    final originalSnap = widget.contact.snapUsername ?? '';
    final originalInsta = widget.contact.instaUsername ?? '';
    final originalDiscord = widget.contact.discordUsername ?? '';

    final snapController = TextEditingController(text: originalSnap);
    final instaController = TextEditingController(text: originalInsta);
    final discordController = TextEditingController(text: originalDiscord);

    bool changed = false;
    void updateChanged() {
      changed = snapController.text != originalSnap ||
          instaController.text != originalInsta ||
          discordController.text != originalDiscord;
    }

    snapController.addListener(updateChanged);
    instaController.addListener(updateChanged);
    discordController.addListener(updateChanged);

    final result = await showDialog<List<String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return WillPopScope(
          onWillPop: () async {
            if (changed) {
              return await _confirm(context, message: 'Discard changes?');
            }
            return true;
          },
          child: AlertDialog(
            title: Text('Edit Usernames'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: snapController,
                  decoration: InputDecoration(labelText: 'Snapchat'),
                ),
                TextField(
                  controller: instaController,
                  decoration: InputDecoration(labelText: 'Instagram'),
                ),
                TextField(
                  controller: discordController,
                  decoration: InputDecoration(labelText: 'Discord'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  if (changed) {
                    final discard =
                        await _confirm(context, message: 'Discard changes?');
                    if (!discard) return;
                  }
                  Navigator.pop(context);
                },
                child: Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  if (changed) {
                    final confirmSave =
                        await _confirm(context, message: 'Save changes?');
                    if (!confirmSave) return;
                  }
                  Navigator.pop(context, [
                    snapController.text,
                    instaController.text,
                    discordController.text,
                  ]);
                },
                child: Text('Save'),
              ),
            ],
          ),
        );
      },
    );

    if (result != null) {
      if (result[0] != widget.contact.snapUsername) {
        await SocialType.Snapchat.saveUsername(widget.contact, result[0],
            overriding: true);
      }
      if (result[1] != widget.contact.instaUsername) {
        await SocialType.Instagram.saveUsername(widget.contact, result[1],
            overriding: true);
      }
      if (result[2] != widget.contact.discordUsername) {
        await SocialType.Discord.saveUsername(widget.contact, result[2],
            overriding: true);
      }
      setState(() {});
    }
  }

  void _openSocial(SocialType social, String username) async {
    Uri url;
    switch (social) {
      case SocialType.Snapchat:
        url =
            Uri.parse('https://www.snapchat.com/add/${username.toLowerCase()}');
        break;
      case SocialType.Instagram:
        url = Uri.parse('https://www.instagram.com/$username');
        break;
      case SocialType.Discord:
        Clipboard.setData(ClipboardData(text: username));
        SocialIcon.discordIconButton?.openApp();
        return;
      default:
        return;
    }
    if (!url.hasEmptyPath) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}
