/*
import 'package:PhotoWordFind/social_icons.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:responsive_framework/responsive_framework.dart'; // Import responsive_framework

final PageController _pageController = PageController(viewportFraction: 0.8);

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: (context, widget) => ResponsiveWrapper.builder(
        ClampingScrollWrapper.builder(context, widget!),
        breakpoints: [
          ResponsiveBreakpoint.resize(350, name: MOBILE),
          ResponsiveBreakpoint.autoScale(600, name: TABLET),
          ResponsiveBreakpoint.autoScale(800, name: DESKTOP),
        ],
      ),
      home: ImageGalleryScreen(),
    );
  }
}

class ImageGalleryScreen extends StatefulWidget {
  @override
  _ImageGalleryScreenState createState() => _ImageGalleryScreenState();
}

class _ImageGalleryScreenState extends State<ImageGalleryScreen> {
  String searchQuery = '';
  String selectedSortOption = 'Name';
  List<String> sortOptions = ['Name', 'Date', 'Size'];
  String selectedDirectory = 'All';
  List<String> directories = ['All', 'Directory1', 'Directory2'];
  List<String> images = ['image1.jpg', 'image2.jpg', 'image3.jpg'];
  List<String> selectedImages = [];

  bool isAscending = true;

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
              },
              child: Icon(Icons.move_to_inbox),
            )
          : null,
      persistentFooterButtons: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ResponsiveRowColumn(
            rowMainAxisAlignment: MainAxisAlignment.spaceBetween,
            rowPadding: const EdgeInsets.symmetric(horizontal: 8.0),
            layout: ResponsiveBreakpoints.of(context).isSmallerThan(TABLET)
                ? ResponsiveRowColumnType.COLUMN
                : ResponsiveRowColumnType.ROW,
            children: [
              _buildSocialIcon(SocialIcon.snapchatIconButton),
              _buildSocialIcon(SocialIcon.galleryIconButton),
              _buildSocialIcon(SocialIcon.bumbleIconButton),
              _buildSocialIcon(SocialIcon.instagramIconButton),
              _buildSocialIcon(SocialIcon.discordIconButton),
              _buildSocialIcon(SocialIcon.kikIconButton),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSocialIcon(Widget? iconButton) {
    return ResponsiveRowColumnItem(
      rowFlex: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: iconButton ?? Container(),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ResponsiveRowColumn(
        layout: ResponsiveBreakpoints.of(context).isSmallerThan(TABLET)
            ? ResponsiveRowColumnType.COLUMN
            : ResponsiveRowColumnType.ROW,
        children: [
          ResponsiveRowColumnItem(
            rowFlex: 1,
            child: DropdownButton<String>(
              value: selectedDirectory,
              underline: SizedBox(),
              isExpanded: true,
              items: directories.map((directory) {
                return DropdownMenuItem<String>(
                  value: directory,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    child: Text(directory),
                  ),
                );
              }).toList(),
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
          SizedBox(width: 8),
          ResponsiveRowColumnItem(
            rowFlex: 2,
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
            Expanded(
              child: DropdownButton<String>(
                value: selectedSortOption,
                isExpanded: true,
                items: sortOptions.map((option) {
                  return DropdownMenuItem<String>(
                    value: option,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                     
*/
