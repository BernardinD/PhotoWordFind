import 'package:PhotoWordFind/gallery/gallery_cell.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

import 'package:PhotoWordFind/main.dart';

class ImageListScreen extends StatelessWidget {

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // Wrapping the entire content in a vertically scrollable layout, if needed
        child: ListView.builder(
          scrollDirection: Axis.horizontal, // Horizontal scrolling for images
          itemCount: MyApp.gallery.images.length,
          itemBuilder: (context, index) {
            return _buildImageCard(context, index);
          },
        ),
      ),
    );
  }

  // Building the card widget for each image along with text, dropdown, and tag
  Widget _buildImageCard(BuildContext context, int index) {
    var imagewidget = MyApp.gallery.images[index].child as GalleryCell;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Column(
        children: [
          Container(
            width: 200, // Set the width for each image card
            height: 200, // Set height for the image display
            child: PhotoView(
              imageProvider:
                  AssetImage(imagewidget.srcImage.path),
              minScale: PhotoViewComputedScale.contained * 0.8,
              maxScale: PhotoViewComputedScale.covered * 2,
            ),
          ),
          SizedBox(height: 10), // Space between image and text

          // Displaying the extracted text from the image
          Text(
            imagewidget.text.toString(),
            style: TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 10), // Space between text and dropdown

          // Popup Menu Icon
          IconButton(
            icon: Icon(Icons.more_vert),
            onPressed: () {
              _showPopupMenu(context, index);
            },
          ),

          SizedBox(height: 10), // Space between dropdown and tag

          // Displaying the tag for the image
          Text(
            "Tag: ${"tags[index]"}",
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // Function to show the Popup Menu when the icon is pressed
  void _showPopupMenu(BuildContext context, int index) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(100, 100, 0, 0), // Customize position as needed
      items: ["test1", "test2"].map((String option) {
        return PopupMenuItem<String>(
          value: option,
          child: Text(option),
        );
      }).toList(),
      elevation: 8.0,
    ).then((value) {
      if (value != null) {
        // Handle option selected from the menu
        print("Selected option: $value for image index: $index");
      }
    });
  }
}
