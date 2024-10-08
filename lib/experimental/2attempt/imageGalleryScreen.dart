import 'package:PhotoWordFind/social_icons.dart';
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
  List<String> sortOptions = ['Name', 'Date', 'Size']; // Add your sort options here
  String selectedDirectory = 'All'; // Assuming 'All' is one of the filter options
  List<String> directories = ['All', 'Directory1', 'Directory2']; // Filter options
  List<String> images = ['image1.jpg', 'image2.jpg', 'image3.jpg'];
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Image Gallery'),
      ),
      body: Column(
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
            ),
          ),
        ],
      ),
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
              value: selectedDirectory,
              underline: SizedBox(),
              isExpanded: true,
              items: directories.map((directory) => DropdownMenuItem<String>(
                value: directory,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Text(directory),
                ),
              )).toList(),
              onChanged: (value) {
                setState(() {
                  selectedDirectory = value!;
                  _filterImages();
                });
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
                contentPadding: EdgeInsets.symmetric(vertical: 12.0, horizontal: 15.0),
              ),
              onChanged: (value) {
                setState(() {
                  searchQuery = value;
                  _filterImages();
                });
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
                    setState(() {
                      selectedSortOption = value!;
                      // Call sorting function if needed
                    });
                  },
                  underline: SizedBox(), // Removes the underline
                  icon: Icon(Icons.arrow_drop_down, color: Colors.blueAccent), // Custom dropdown icon
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
                    setState(() {
                      isAscending = true; // Set to ascending
                      // Call sorting function if needed
                    });
                  },
                ),
                _buildOrderIcon(
                  icon: Icons.arrow_downward,
                  isActive: !isAscending,
                  onPressed: () {
                    setState(() {
                      isAscending = false; // Set to descending
                      // Call sorting function if needed
                    });
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
                  value: selectedDirectory,
                  isExpanded: true,
                  items: directories
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
                      selectedDirectory = value!;
                      // Call filter function if needed
                    });
                  },
                  underline: SizedBox(), // Removes the underline
                  icon: Icon(Icons.arrow_drop_down, color: Colors.blueAccent), // Custom dropdown icon
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
    // Implement filter logic here
  }
}

// Updated ImageGallery Widget
class ImageGallery extends StatelessWidget {
  final List<String> images;
  final List<String> selectedImages;
  final Map<String, String> extractedTexts;
  final Map<String, String> identifiers;
  final Function(String) onImageSelected;
  final Function(String, String) onMenuOptionSelected;

  ImageGallery({
    required this.images,
    required this.selectedImages,
    required this.extractedTexts,
    required this.identifiers,
    required this.onImageSelected,
    required this.onMenuOptionSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ResponsiveRowColumn(
      layout: ResponsiveBreakpoints.of(context).smallerThan(DESKTOP)
          ? ResponsiveRowColumnType.COLUMN
          : ResponsiveRowColumnType.ROW,
      children: [
        ResponsiveRowColumnItem(
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
              // trackVisibility: true,
              interactive: true,
              thickness: 10,
              controller: _pageController,  // Use the same controller here
              child: PageView.builder(
                // scrollDirection: Axis.horizontal,
                controller: _pageController,
                itemCount: images.length,
                itemBuilder: (context, index) {
                  return ImageTile(
                    imagePath: images[index],
                    isSelected: selectedImages.contains(images[index]),
                    extractedText: extractedTexts[images[index]]!,
                    identifier: identifiers[images[index]]!,
                    onSelected: onImageSelected,
                    onMenuOptionSelected: onMenuOptionSelected,
                  );
                },
              ),
            ),
          ),
        ),
      ],
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

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaledBox(
      width: ResponsiveValue(context, defaultValue: 250.0, conditionalValues: [
        Condition.smallerThan(name: TABLET, value: 200.0),
        Condition.largerThan(name: DESKTOP, value: 300.0),
      ]).value,
      child: GestureDetector(
        onLongPress: () {
          onSelected(imagePath);
        },
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: 10),
          width: 250,
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
                child: Stack(
                  children: [
                    PhotoView(
                      imageProvider: AssetImage(imagePath),
                      backgroundDecoration: BoxDecoration(color: Colors.white),
                      minScale: PhotoViewComputedScale.contained,
                      maxScale: PhotoViewComputedScale.covered * 2.5,
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
      
              // Extracted Text Field
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  extractedText,
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
        ),
      ),
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
