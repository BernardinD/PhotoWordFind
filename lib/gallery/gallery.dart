

import 'dart:io';
import 'dart:math';


import 'package:PhotoWordFind/models/contactEntry.dart';
import 'package:PhotoWordFind/utils/sort_utils.dart';
import 'package:path/path.dart' as path;
import 'package:PhotoWordFind/gallery/gallery_cell.dart';
import 'package:PhotoWordFind/main.dart';
import 'package:PhotoWordFind/utils/toast_utils.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:photo_view/photo_view_gallery.dart';

class Gallery{

  // PriorityQueue<PhotoViewGalleryPageOptions> _images;
  late List<PhotoViewGalleryPageOptions> _images;

  late Set<String> _selected;
  late PageController _galleryController;

  // Getters
  List<PhotoViewGalleryPageOptions> get images {
    Sortings.updateCache();
    // sort();
    return _images;
  }
  Set<String> get selected => _selected;
  PageController get galleryController => _galleryController;

  // Setters
  set selected(Set selected) {
    _selected = selected as Set<String>;
  }
  set galleryController(galleryController) {
    _galleryController = galleryController;
  }

  Gallery(){

    // Initialize indicator for selected photos
    _selected = new Set();

    _galleryController = new PageController(initialPage: 0, keepPage: false, viewportFraction: 1.0);
    _images = [];
  }

  void sort(){
    _images.sort(Sortings.getSorting() as int Function(PhotoViewGalleryPageOptions, PhotoViewGalleryPageOptions)?);
  }

  int length(){
    return _images.length;
  }

  void clear(){
    _images.clear();
  }

  GalleryCell? _getNewCurrentCell(){
    int currentPage = _galleryController.page!.toInt();
    GalleryCell currentCell = _images[currentPage].child as GalleryCell;
    if(_selected.contains((currentCell.key as ValueKey).value)){
      currentPage--;
    }
    return currentPage >= 0 ? _images[currentPage].child as GalleryCell? : null;
  }

  void removeSelected(){
    GalleryCell? newPage = _getNewCurrentCell();
    _images.removeWhere((cell) => _selected.contains(((cell.child as GalleryCell).key as ValueKey<String>).value));
    _selected.clear();

    if(_images.isNotEmpty) {
      int page = _images.indexWhere((cell) => cell.child == newPage);
      _galleryController.jumpToPage(max(page, 0));
    }
  }

  // Creates standardized Widget that will seen in gallery
  void addNewCell(List<Map<String,String>> body, String snapUsername, dynamic file, File displayImage, ContactEntry? contact, {String instaUsername = "", String discordUsername = ""}){
    Function redoListPos = (GalleryCell cell) => _images.indexWhere((element) => element.child == cell);


    var cell = PhotoViewGalleryPageOptions.customChild(
      child: GalleryCell(body, snapUsername, instaUsername, discordUsername, file, displayImage, redoListPos as int Function(GalleryCell), onPressed, onLongPress, contact, key: ValueKey(path.basename(file.path)),),
      // heroAttributes: const HeroAttributes(tag: "tag1"),
    );

    _images.add(cell);
  }

  void redoCell(List<Map<String,String>> body, String snapUsername, String instaUsername, String discordUsername, int idx){
    Function redoListPos = (GalleryCell cell) => _images.indexWhere((element) => element.child == cell);


    GalleryCell replacing = _images[idx].child as GalleryCell;
    var displayImage = replacing.srcImage;
    var f = replacing.f;
    var key = replacing.key!;

    var cell = PhotoViewGalleryPageOptions.customChild(
      child: GalleryCell(body, snapUsername, instaUsername, discordUsername, f, displayImage, redoListPos as int Function(GalleryCell), onPressed, onLongPress, replacing.contact, key: key as ValueKey<String>),
      // heroAttributes: const HeroAttributes(tag: "tag1"),
    );

    _images[idx] = cell;
  }


  void onPressed(String fileName) {
    debugPrint("Entering onPressed()...");
    selected.contains(fileName) ? selected.remove(fileName) : selected.add(fileName);

    runSelectImageToast(selected.contains(fileName));

  LegacyAppShell.updateFrame?.call(() => null);
    debugPrint("Leaving onPressed()...");
  }

  void onLongPress(String fileName){
    Clipboard.setData(ClipboardData(text: fileName));
    filenameCopiedMessage();
  }


  static void runSelectImageToast(bool selected){
    Function message = (selected) => (selected ? "Selected." : "Unselected.");
    Toasts.showToast(selected, message);
  }

  static void filenameCopiedMessage(){
    Toasts.showToast(true, (state)=>"File name copied to clipboard");
  }

  void dispose(){

  }
}
