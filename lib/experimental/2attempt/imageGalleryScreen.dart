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

final PageController _pageController =
    PageController(viewportFraction: 0.8); // Gives a gallery feel

class ImageGalleryScreen extends StatefulWidget {
  @override
  _ImageGalleryScreenState createState() => _ImageGalleryScreenState();
}

class _ImageGalleryScreenState extends State<ImageGalleryScreen> {
  String searchQuery = '';
  String selectedSortOption = 'Name'; // Default value from the list
  List<String> sortOptions = [
    'Name',
    'Date',
    'Size'
  ]; // Add your sort options here
  String selectedState = 'All';
  List<String> states = ['All'];
  List<ContactEntry> images = [];
  List<ContactEntry> allImages = [];
  List<String> selectedImages = [];

  // State variable to track the selected sort order
  bool isAscending = true; // Default sorting order

  Map<String, String> extractedTexts = {
    'image1.jpg': 'Sample text for image 1',
    'image2.jpg': 'Sample text for image 2',
    'image3.jpg': 'Sample text for image 3',
  };
  Map<String, String> identifiers = {
    'image1.jpg': 'ID: 001',
    'image2.jpg': 'ID: 002',
    'image3.jpg': 'ID: 003',
  };

  // Add a setting to control which loading method to use
  bool useJsonFileForLoading = false; // Set to true to load from JSON file

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

    // TODO: revisit this logicand whether it can be simplified
    // specifically, whether there's a way to remove the redundancy of creating a map
    // and then using the results of that map to essentially create a second map with `get()`
    for (final entry in (await StorageUtils.toMap()).entries) {
      final identifier = entry.key;
      final contactEntry = await StorageUtils.get(identifier);
      if (contactEntry != null) {
        loadedImages.add(contactEntry);
      }
    }
    allImages = loadedImages;
    _updateStates(allImages);
    _applyFiltersAndSort();
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
    _applyFiltersAndSort();
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
              _buildTopBar(),
              _buildSortingFilteringBar(),
              Expanded(
                child: ImageGallery(
                  images: images,
                  selectedImages: selectedImages,
                  extractedTexts: extractedTexts,
                  identifiers: identifiers,
                  onImageSelected: (String imagePath) {
                    setState(() {
                      if (selectedImages.contains(imagePath)) {
                        selectedImages.remove(imagePath);
                      } else {
                        selectedImages.add(imagePath);
                      }
                    });
                  },
                  onMenuOptionSelected: (String imagePath, String option) {
                    // Handle image option
                  },
                  galleryHeight: screenHeight, // Pass height dynamically
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

  Widget _buildImageTile(String imagePath) {
    return GestureDetector(
      onTap: () {
        setState(() {
          if (selectedImages.contains(imagePath)) {
            selectedImages.remove(imagePath);
          } else {
            selectedImages.add(imagePath);
          }
        });
      },
      child: Stack(
        children: [
          Image.asset(imagePath, fit: BoxFit.cover),
          if (selectedImages.contains(imagePath))
            Positioned(
              top: 8,
              right: 8,
              child: Icon(Icons.check_circle, color: Colors.blue),
            ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          // Directory Dropdown
          Expanded(
            child: DropdownButton<String>(
              value: selectedState,
              underline: SizedBox(),
              isExpanded: true,
              items: states
                  .map((directory) => DropdownMenuItem<String>(
                        value: directory,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12.0),
                          child: Text(directory),
                        ),
                      ))
                  .toList(),
              onChanged: (value) {
                selectedState = value!;
                _filterImages();
              },
              style: TextStyle(color: Colors.black),
              dropdownColor: Colors.white,
            ),
          ),
          const SizedBox(width: 8), // Spacer
          // Search Text Field
          Expanded(
            flex: 2,
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search...',
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    EdgeInsets.symmetric(vertical: 12.0, horizontal: 15.0),
              ),
              onChanged: (value) {
                searchQuery = value;
                _filterImages();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortingFilteringBar() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Sort Option Dropdown
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      offset: Offset(0, 2),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: DropdownButton<String>(
                  value: selectedSortOption,
                  isExpanded: true,
                  items: sortOptions
                      .map((option) => DropdownMenuItem<String>(
                            value: option,
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Text(option),
                            ),
                          ))
                      .toList(),
                  onChanged: (value) {
                    selectedSortOption = value!;
                    _applyFiltersAndSort();
                  },
                  underline: SizedBox(), // Removes the underline
                  icon: Icon(Icons.arrow_drop_down,
                      color: Colors.blueAccent), // Custom dropdown icon
                  style: TextStyle(color: Colors.black), // Dropdown text style
                  dropdownColor: Colors.white, // Dropdown background color
                ),
              ),
            ),
            SizedBox(width: 10), // Spacer
            // Icon Buttons for Sort Order
            Row(
              children: [
                _buildOrderIcon(
                  icon: Icons.arrow_upward,
                  isActive: isAscending,
                  onPressed: () {
                    isAscending = true;
                    _applyFiltersAndSort();
                  },
                ),
                _buildOrderIcon(
                  icon: Icons.arrow_downward,
                  isActive: !isAscending,
                  onPressed: () {
                    isAscending = false;
                    _applyFiltersAndSort();
                  },
                ),
              ],
            ),
            SizedBox(width: 10), // Spacer
            // Optional Filter Dropdown
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      offset: Offset(0, 2),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: DropdownButton<String>(
                  value: selectedState,
                  isExpanded: true,
                  items: states
                      .map((directory) => DropdownMenuItem<String>(
                            value: directory,
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Text(directory),
                            ),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedState = value!;
                      _applyFiltersAndSort();
                    });
                  },
                  underline: SizedBox(), // Removes the underline
                  icon: Icon(Icons.arrow_drop_down,
                      color: Colors.blueAccent), // Custom dropdown icon
                  style: TextStyle(color: Colors.black), // Dropdown text style
                  dropdownColor: Colors.white, // Dropdown background color
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderIcon({
    required IconData icon,
    required bool isActive,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isActive ? Colors.blue.withOpacity(0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: IconButton(
        icon: Icon(
          icon,
          color: isActive ? Colors.blue : Colors.grey,
          size: 28, // Size of the icons
        ),
        onPressed: onPressed,
      ),
    );
  }

  void _filterImages() {
    _applyFiltersAndSort();
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

  void _applyFiltersAndSort() {
    List<ContactEntry> filtered =
        SearchService.searchEntries(allImages, searchQuery).where((img) {
      final tag = img.state ?? path.basename(path.dirname(img.imagePath));
      final matchesState = selectedState == 'All' || tag == selectedState;
      return matchesState;
    }).toList();

    int compare(ContactEntry a, ContactEntry b) {
      int result;
      switch (selectedSortOption) {
        case 'Date':
          result = a.dateFound.compareTo(b.dateFound);
          break;
        case 'Size':
          result = File(a.imagePath)
              .lengthSync()
              .compareTo(File(b.imagePath).lengthSync());
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
    });
  }
}

// Updated ImageGallery Widget
class ImageGallery extends StatelessWidget {
  final List<ContactEntry> images;
  final List<String> selectedImages;
  final Map<String, String> extractedTexts;
  final Map<String, String> identifiers;
  final Function(String) onImageSelected;
  final Function(String, String) onMenuOptionSelected;
  final double galleryHeight; // New dynamic height parameter

  ImageGallery({
    required this.images,
    required this.selectedImages,
    required this.extractedTexts,
    required this.identifiers,
    required this.onImageSelected,
    required this.onMenuOptionSelected,
    required this.galleryHeight,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: galleryHeight, // Ensure it adapts to screen changes
      child: ScrollbarTheme(
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
            itemBuilder: (context, index) {
              return ImageTile(
                imagePath: images[index].imagePath,
                isSelected: selectedImages.contains(images[index].identifier),
                extractedText: images[index].extractedText ?? "",
                identifier: images[index].identifier,
                onSelected: onImageSelected,
                onMenuOptionSelected: onMenuOptionSelected,
              );
            },
          ),
        ),
      ),
    );
  }
}

// Updated ImageTile Widget with Selection
class ImageTile extends StatelessWidget {
  final String imagePath;
  final bool isSelected;
  final String extractedText;
  final String identifier;
  final Function(String) onSelected;
  final Function(String, String) onMenuOptionSelected;

  ImageTile({
    required this.imagePath,
    required this.isSelected,
    required this.extractedText,
    required this.identifier,
    required this.onSelected,
    required this.onMenuOptionSelected,
  });

  String get _truncatedText {
    const maxChars = 120;
    if (extractedText.length <= maxChars) return extractedText;
    return '${extractedText.substring(0, maxChars)}...';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () {
        onSelected(imagePath);
      },
      child: LayoutBuilder(builder: (context, constraints) {
        return Container(
          margin: EdgeInsets.symmetric(horizontal: 10),
          width: constraints.maxWidth * 0.80,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: isSelected
                ? Border.all(color: Colors.blueAccent, width: 3)
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                offset: Offset(0, 4),
                blurRadius: 4,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image Display
              ClipRRect(
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                child: Container(
                  constraints:
                      BoxConstraints(maxHeight: constraints.maxHeight * 0.70),
                  child: Stack(
                    children: [
                      Flexible(
                        // height: 250,
                        child: PhotoView(
                          imageProvider: FileImage(File(imagePath)),
                          backgroundDecoration:
                              BoxDecoration(color: Colors.white),
                          minScale: PhotoViewComputedScale.contained,
                          maxScale: PhotoViewComputedScale.covered * 2.5,
                        ),
                      ),
                      if (isSelected)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Icon(
                            Icons.check_circle,
                            color: Colors.blueAccent,
                            size: 30,
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Extracted Text Field
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  _truncatedText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                ),
              ),

              // Identifier Label
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text(
                  identifier,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                  ),
                ),
              ),

              // Popup Menu Icon
              Align(
                alignment: Alignment.bottomRight,
                child: IconButton(
                  icon: Icon(Icons.more_vert),
                  onPressed: () {
                    _showPopupMenu(context, imagePath);
                  },
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  void _showPopupMenu(BuildContext context, String imagePath) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: Icon(Icons.info),
              title: Text('View Details'),
              onTap: () {
                onMenuOptionSelected(imagePath, 'details');
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.move_to_inbox),
              title: Text('Move'),
              onTap: () {
                onMenuOptionSelected(imagePath, 'move');
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete),
              title: Text('Delete'),
              onTap: () {
                onMenuOptionSelected(imagePath, 'delete');
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }
}
