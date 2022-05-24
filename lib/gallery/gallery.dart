

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:PhotoWordFind/constants/constants.dart';
import 'package:PhotoWordFind/gallery/gallery_cell.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:photo_view/photo_view_gallery.dart';

class Gallery{

  List<PhotoViewGalleryPageOptions> _images;

  List<PhotoViewGalleryPageOptions> get images => _images;

  set images(List<PhotoViewGalleryPageOptions> images) {
    _images = images;
  }
  Set _selected;

  Set get selected => _selected;

  set selected(Set selected) {
    _selected = selected;
  }

  var _galleryController;

  get galleryController => _galleryController;

  set galleryController(galleryController) {
    _galleryController = galleryController;
  }

  Gallery(){

    // Initalize indicator for selected photos
    selected = new Set();

    galleryController = new PageController(initialPage: 0, keepPage: false, viewportFraction: 1.0);
    images = [];
  }

  bool addNewCell(){
    String file_name = f.path.split("/").last;
    int list_pos = position?? gallery.images.length;


    PhotoViewGalleryPageOptions.customChild(
      child: Container(
        key: ValueKey(file_name),
        width: MediaQuery.of(context).size.width * 0.95,
        child: GalleryCell(),
      ),
      // heroAttributes: const HeroAttributes(tag: "tag1"),
    );
  }


  void onPressed(String file_name) {
    selected.contains(file_name) ? selected.remove(
    file_name) : selected.add(file_name);
    selectImage(selected.contains(file_name));
  }

  void onLongPress(String file_name){
    Clipboard.setData(ClipboardData(text: file_name));
    filenameCopiedMessage();
  }
}