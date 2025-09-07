import 'package:flutter/material.dart';
import 'package:PhotoWordFind/models/contactEntry.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import 'package:PhotoWordFind/screens/gallery/widgets/image_tile.dart';
import 'package:PhotoWordFind/screens/gallery/review_viewer.dart';

// Shared page controller used by the gallery and screen logic
final PageController kGalleryPageController =
    PageController(viewportFraction: 0.8);

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
  final bool? selectionMode;
  // Secondary selection for "never friended back"
  final Set<String>? neverBackSelectedIds;
  final ValueChanged<String>? onToggleNeverBack;

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
  this.selectionMode,
  this.neverBackSelectedIds,
  this.onToggleNeverBack,
  });

  @override
  Widget build(BuildContext context) {
    if (!kUseMasonryGrid) {
    final bool effectiveSelectionMode =
      selectionMode ?? selectedImages.isNotEmpty;
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
                  selectionMode: effectiveSelectionMode,
          neverBackSelected: neverBackSelectedIds?.contains(images[index].identifier) ?? false,
          onToggleNeverBack: onToggleNeverBack == null
            ? null
            : () => onToggleNeverBack!(images[index].identifier),
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
  final bool effectiveSelectionMode =
    selectionMode ?? selectedImages.isNotEmpty;
    // Aim for tiles ~180dp wide with clamped column count
    final int columns = (width / 180).floor().clamp(1, 8);
    const double baseHPad = 8;
    const double cross = 12;
    // Quantize grid width so each column has an integer pixel width.
    final usable = width - (baseHPad * 2);
    final totalSpacing = (columns - 1) * cross;
    final colWidth = ((usable - totalSpacing) / columns).floorToDouble();
    final adjustedUsable = columns * colWidth + totalSpacing;
    final extra = (usable - adjustedUsable).clamp(0, double.infinity);
    final padLeft = baseHPad + (extra / 2);
    final padRight = baseHPad + (extra - (extra / 2));

    return Padding(
      padding: EdgeInsets.only(left: padLeft, right: padRight),
      child: Stack(
        children: [
          MasonryGridView.count(
            crossAxisCount: columns,
            mainAxisSpacing: cross,
            crossAxisSpacing: cross,
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
                      builder: (_) => ReviewViewer(
                          images: images,
                          initialIndex: index,
                          sortOption: sortOption),
                    ),
                  );
                },
                selectionMode: effectiveSelectionMode,
        neverBackSelected: neverBackSelectedIds?.contains(item.identifier) ?? false,
        onToggleNeverBack: onToggleNeverBack == null
          ? null
          : () => onToggleNeverBack!(item.identifier),
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
  final bool? selectionMode;
  final Set<String>? neverBackSelectedIds;
  final ValueChanged<String>? onToggleNeverBack;

  const SliverImageGallery({
    super.key,
    required this.images,
    required this.selectedImages,
    required this.onImageSelected,
    required this.onMenuOptionSelected,
    required this.sortOption,
  this.selectionMode,
  this.neverBackSelectedIds,
  this.onToggleNeverBack,
  });

  @override
  Widget build(BuildContext context) {
    if (!kUseMasonryGrid) {
      // Fallback to a simple sliver list if masonry grid is off.
  final bool effectiveSelectionMode =
      selectionMode ?? selectedImages.isNotEmpty;
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
        selectionMode: effectiveSelectionMode,
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
    const double baseHPad = 8;
    const double cross = 12;
    // Quantize grid width so each column has an integer pixel width.
    final usable = width - (baseHPad * 2);
    final totalSpacing = (columns - 1) * cross;
    final colWidth = ((usable - totalSpacing) / columns).floorToDouble();
    final adjustedUsable = columns * colWidth + totalSpacing;
    final extra = (usable - adjustedUsable).clamp(0, double.infinity);
    final padLeft = baseHPad + (extra / 2);
    final padRight = baseHPad + (extra - (extra / 2));

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(padLeft, 8, padRight, 96),
      sliver: SliverMasonryGrid.count(
        crossAxisCount: columns,
        mainAxisSpacing: cross,
        crossAxisSpacing: cross,
        // Sliver scroller uses parent cache; spacing remains.
        childCount: images.length,
        itemBuilder: (context, index) {
          final item = images[index];
          final bool effectiveSelectionMode =
              selectionMode ?? selectedImages.isNotEmpty;
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
                  builder: (_) => ReviewViewer(
                      images: images,
                      initialIndex: index,
                      sortOption: sortOption),
                ),
              );
            },
            selectionMode: effectiveSelectionMode,
      neverBackSelected: neverBackSelectedIds?.contains(item.identifier) ?? false,
      onToggleNeverBack: onToggleNeverBack == null
        ? null
        : () => onToggleNeverBack!(item.identifier),
          );
        },
      ),
    );
  }
}
