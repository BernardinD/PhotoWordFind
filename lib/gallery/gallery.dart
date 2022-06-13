

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';


import 'package:path/path.dart' as path;
import 'package:PhotoWordFind/constants/constants.dart';
import 'package:PhotoWordFind/gallery/gallery_cell.dart';
import 'package:PhotoWordFind/main.dart';
import 'package:PhotoWordFind/utils/toast_utils.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:photo_view/photo_view_gallery.dart';

class Gallery{

  List<PhotoViewGalleryPageOptions> _images;

  Set _selected;
  PageController _galleryController;

  // Getters
  List<PhotoViewGalleryPageOptions> get images => _images;
  Set get selected => _selected;
  get galleryController => _galleryController;

  // Setters
  set selected(Set selected) {
    _selected = selected;
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

  int length(){
    return _images.length;
  }

  void clear(){
    _images.clear();
  }

  GalleryCell _getNewCurrentCell(){
    int currentPage = _galleryController.page.toInt();
    GalleryCell currentCell = _images[currentPage].child;
    if(_selected.contains((currentCell.key as ValueKey).value)){
      currentPage--;
    }
    return currentPage >= 0 ? _images[currentPage].child : null;
  }

  void removeSelected(){
    GalleryCell newPage = _getNewCurrentCell();
    _images.removeWhere((cell) => _selected.contains(((cell.child as GalleryCell).key as ValueKey<String>).value));
    _selected.clear();

    if(_images.isNotEmpty) {
      int page = _images.indexWhere((cell) => cell.child == newPage);
      _galleryController.jumpToPage(max(page, 0));
    }
  }

  // Creates standardized Widget that will seen in gallery
  void addNewCell(String text, String suggestedUsername, dynamic file, File displayImage){
    Function redo_list_pos = (GalleryCell cell) => _images.indexWhere((element) => element.child == cell);


    var cell = PhotoViewGalleryPageOptions.customChild(
      child: GalleryCell(text, suggestedUsername, file, displayImage, redo_list_pos, onPressed, onLongPress, key: ValueKey(path.basename(file.path))),
      // heroAttributes: const HeroAttributes(tag: "tag1"),
    );

    _images.add(cell);
  }

  void redoCell(String text, String suggestedUsername, int idx){
    Function redo_list_pos = (GalleryCell cell) => _images.indexWhere((element) => element.child == cell);


    GalleryCell replacing = _images[idx].child as GalleryCell;
    var display_image = replacing.src_image;
    var f = replacing.f;
    var key = replacing.key;

    var cell = PhotoViewGalleryPageOptions.customChild(
      child: GalleryCell(text, suggestedUsername, f, display_image, redo_list_pos, onPressed, onLongPress, key: key),
      // heroAttributes: const HeroAttributes(tag: "tag1"),
    );

    _images[idx] = cell;
  }


  void onPressed(String file_name) {
    debugPrint("Entering onPressed()...");
    selected.contains(file_name) ? selected.remove(file_name) : selected.add(file_name);

    runSelectImageToast(selected.contains(file_name));

    MyApp.updateFrame(() => null);
    debugPrint("Leaving onPressed()...");
  }

  void onLongPress(String file_name){
    Clipboard.setData(ClipboardData(text: file_name));
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