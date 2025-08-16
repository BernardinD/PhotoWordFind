import 'package:flutter/material.dart';
import 'package:PhotoWordFind/models/contactEntry.dart';

import 'package:PhotoWordFind/screens/gallery/widgets/image_tile.dart';

// Shared page controller used by the gallery and screen logic
final PageController kGalleryPageController = PageController(viewportFraction: 0.8);

class ImageGallery extends StatelessWidget {
  final List<ContactEntry> images;
  final List<String> selectedImages;
  final Function(String) onImageSelected;
  final Function(String, String) onMenuOptionSelected;
  final double galleryHeight;
  final ValueChanged<int> onPageChanged;
  final int currentIndex;
  final String sortOption;

  const ImageGallery({
    super.key,
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
          PageView.builder(
            controller: kGalleryPageController,
            itemCount: images.length,
            onPageChanged: onPageChanged,
            itemBuilder: (context, index) {
              return ImageTile(
                imagePath: images[index].imagePath,
                isSelected: selectedImages.contains(images[index].identifier),
                extractedText: images[index].extractedText ?? "",
                identifier: images[index].identifier,
                sortOption: sortOption,
                onSelected: onImageSelected,
                onMenuOptionSelected: onMenuOptionSelected,
                contact: images[index],
              );
            },
          ),
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${currentIndex + 1} / ${images.length}',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
