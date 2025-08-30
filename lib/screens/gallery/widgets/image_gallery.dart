import 'package:flutter/material.dart';
import 'package:PhotoWordFind/models/contactEntry.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import 'package:PhotoWordFind/screens/gallery/widgets/image_tile.dart';
import 'package:PhotoWordFind/screens/gallery/review_viewer.dart';

// Shared page controller used by the gallery and screen logic
final PageController kGalleryPageController = PageController(viewportFraction: 0.8);

// Feature flag: switch between PageView carousel and Masonry grid.
const bool kUseMasonryGrid = true;

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
    if (!kUseMasonryGrid) {
      return SizedBox(
        height: galleryHeight,
        child: Stack(
          children: [
            PageView.builder(
              controller: kGalleryPageController,
              itemCount: images.length,
              onPageChanged: onPageChanged,
              allowImplicitScrolling: false,
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
            _buildCounterOverlay(context, currentIndex, images.length),
          ],
        ),
      );
    }

    // Masonry grid variant
    final media = MediaQuery.of(context);
  final width = media.size.width;
  // Aim for tiles ~180dp wide with clamped column count
  final int columns = (width / 180).floor().clamp(1, 8);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Stack(
        children: [
          MasonryGridView.count(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            // Limit offscreen cache to reduce memory pressure
            cacheExtent: 600,
            padding: const EdgeInsets.only(bottom: 96, top: 8),
            itemCount: images.length,
      itemBuilder: (context, index) {
              final item = images[index];
              return ImageTile(
        key: ValueKey(item.identifier),
                imagePath: item.imagePath,
                isSelected: selectedImages.contains(item.identifier),
                extractedText: item.extractedText ?? '',
                identifier: item.identifier,
                sortOption: sortOption,
                onSelected: onImageSelected,
                onMenuOptionSelected: onMenuOptionSelected,
                contact: item,
                gridMode: true,
                onOpenFullScreen: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ReviewViewer(images: images, initialIndex: index, sortOption: sortOption),
                    ),
                  );
                },
              );
            },
          ),
          _buildCounterOverlay(context, currentIndex, images.length),
        ],
      ),
    );
  }

  Widget _buildCounterOverlay(BuildContext context, int index, int total) {
    return Positioned(
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
            '${index + 1} / $total',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Sliver variant for use inside a CustomScrollView.
class SliverImageGallery extends StatelessWidget {
  final List<ContactEntry> images;
  final List<String> selectedImages;
  final Function(String) onImageSelected;
  final Function(String, String) onMenuOptionSelected;
  final String sortOption;

  const SliverImageGallery({
    super.key,
    required this.images,
    required this.selectedImages,
    required this.onImageSelected,
    required this.onMenuOptionSelected,
    required this.sortOption,
  });

  @override
  Widget build(BuildContext context) {
    if (!kUseMasonryGrid) {
      // Fallback to a simple sliver list if masonry grid is off.
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final item = images[index];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: ImageTile(
                imagePath: item.imagePath,
                isSelected: selectedImages.contains(item.identifier),
                extractedText: item.extractedText ?? '',
                identifier: item.identifier,
                sortOption: sortOption,
                onSelected: onImageSelected,
                onMenuOptionSelected: onMenuOptionSelected,
                contact: item,
              ),
            );
          },
          childCount: images.length,
        ),
      );
    }

    final media = MediaQuery.of(context);
  final width = media.size.width;
  final int columns = (width / 180).floor().clamp(1, 8);

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
      sliver: SliverMasonryGrid.count(
        crossAxisCount: columns,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        // Sliver scroller uses parent cache; spacing remains.
        childCount: images.length,
    itemBuilder: (context, index) {
          final item = images[index];
          return ImageTile(
      key: ValueKey(item.identifier),
            imagePath: item.imagePath,
            isSelected: selectedImages.contains(item.identifier),
            extractedText: item.extractedText ?? '',
            identifier: item.identifier,
            sortOption: sortOption,
            onSelected: onImageSelected,
            onMenuOptionSelected: onMenuOptionSelected,
            contact: item,
            gridMode: true,
            onOpenFullScreen: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ReviewViewer(images: images, initialIndex: index, sortOption: sortOption),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
