import 'dart:io';
import 'dart:collection';
import 'dart:math';

import 'package:PhotoWordFind/models/contactEntry.dart';
import 'package:PhotoWordFind/utils/sort_utils.dart';
import 'package:PhotoWordFind/gallery/gallery_cell.dart';
import 'package:PhotoWordFind/main.dart';
import 'package:PhotoWordFind/utils/toast_utils.dart';
import 'package:PhotoWordFind/utils/files_utils.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:photo_view/photo_view_gallery.dart';

class Gallery {
  // PriorityQueue<PhotoViewGalleryPageOptions> _images;
  late List<PhotoViewGalleryPageOptions> _images;

  late Set<ContactEntry> _selected;
  late PageController _galleryController;

  // Getters
  List<PhotoViewGalleryPageOptions> get images {
    // Avoid triggering heavy cache rebuilds on every access; callers
    // should update or sort explicitly at appropriate times.
    return _images;
  }

  Set<ContactEntry> get selected => _selected;
  PageController get galleryController => _galleryController;

  // Setters
  set selected(Set selected) {
    _selected = selected as Set<ContactEntry>;
  }

  set galleryController(galleryController) {
    _galleryController = galleryController;
  }

  Gallery() {
    // Initialize indicator for selected photos
    _selected = LinkedHashSet<ContactEntry>(
      equals: (a, b) => a.identifier == b.identifier,
      hashCode: (e) => e.identifier.hashCode,
    );

    _galleryController = new PageController(
        initialPage: 0, keepPage: false, viewportFraction: 1.0);
    _images = [];
  }

  void sort() {
    _images.sort(Sortings.getSorting() as int Function(
        PhotoViewGalleryPageOptions, PhotoViewGalleryPageOptions)?);
  }

  int length() {
    return _images.length;
  }

  void clear() {
    _images.clear();
  }

  GalleryCell? _getNewCurrentCell() {
    int currentPage = _galleryController.page!.toInt();
    GalleryCell currentCell = _images[currentPage].child as GalleryCell;
    // If the current cell's contact is selected, step back one page
    final currentContact = currentCell.contact;
    if (currentContact != null && _selected.contains(currentContact)) {
      currentPage--;
    }
    return currentPage >= 0 ? _images[currentPage].child as GalleryCell? : null;
  }

  void removeSelected() {
    GalleryCell? newPage = _getNewCurrentCell();
    _images.removeWhere((cell) {
      final entry = (cell.child as GalleryCell).contact;
      return entry != null && _selected.contains(entry);
    });
    _selected.clear();

    if (_images.isNotEmpty) {
      int page = _images.indexWhere((cell) => cell.child == newPage);
      _galleryController.jumpToPage(max(page, 0));
    }
  }

  // Creates standardized Widget that will seen in gallery
  void addNewCell(List<Map<String, String>> body, String snapUsername,
      dynamic file, File displayImage, ContactEntry? contact,
      {String instaUsername = "", String discordUsername = ""}) {
    Function redoListPos = (GalleryCell cell) =>
        _images.indexWhere((element) => element.child == cell);

    var cell = PhotoViewGalleryPageOptions.customChild(
      child: GalleryCell(
        body,
        snapUsername,
        instaUsername,
        discordUsername,
        file,
        displayImage,
        redoListPos as int Function(GalleryCell),
        onPressed,
        onLongPress,
        contact,
        // Use the identifier (filename without extension) as the key
        key: ValueKey(getKeyOfFilename(file.path)),
      ),
      // heroAttributes: const HeroAttributes(tag: "tag1"),
    );

    _images.add(cell);
  }

  void redoCell(List<Map<String, String>> body, String snapUsername,
      String instaUsername, String discordUsername, int idx) {
    Function redoListPos = (GalleryCell cell) =>
        _images.indexWhere((element) => element.child == cell);

    GalleryCell replacing = _images[idx].child as GalleryCell;
    var displayImage = replacing.srcImage;
    var f = replacing.f;
    var key = replacing.key!;

    var cell = PhotoViewGalleryPageOptions.customChild(
      child: GalleryCell(
          body,
          snapUsername,
          instaUsername,
          discordUsername,
          f,
          displayImage,
          redoListPos as int Function(GalleryCell),
          onPressed,
          onLongPress,
          replacing.contact,
          key: key as ValueKey<String>),
      // heroAttributes: const HeroAttributes(tag: "tag1"),
    );

    _images[idx] = cell;
  }

  void onPressed(ContactEntry entry) {
    debugPrint("Entering onPressed()...");
    // Toggle selection using custom equality
    final removed = _selected.remove(entry);
    if (!removed) _selected.add(entry);

    final nowSelected = _selected.contains(entry);
    runSelectImageToast(nowSelected);

    LegacyAppShell.updateFrame?.call(() => null);
    debugPrint("Leaving onPressed()...");
  }

  void onLongPress(String fileName) {
    Clipboard.setData(ClipboardData(text: fileName));
    filenameCopiedMessage();
  }

  static void runSelectImageToast(bool selected) {
    Function message = (selected) => (selected ? "Selected." : "Unselected.");
    Toasts.showToast(selected, message);
  }

  static void filenameCopiedMessage() {
    Toasts.showToast(true, (state) => "File name copied to clipboard");
  }

  void dispose() {}
}
