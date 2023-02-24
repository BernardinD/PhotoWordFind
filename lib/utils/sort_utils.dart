import 'dart:io';

import 'package:PhotoWordFind/gallery/gallery_cell.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view_gallery.dart';


Sorts _current_sort = Sorts.Default;
get current_sort => _current_sort;

// The direction of the sort
bool _reverse = true;
get reverse => _reverse;

enum Sorts{
  Default,
  Date,
  Insertion,
  AddedOnSnap,
  AddedOnInsta,
  Filename,
  DateFriendOnSocials,
  DateFoundOnBumble,
}
class Sortings{

  static updateSortType(Sorts s){
    if(_current_sort == s){
      _reverse = !_reverse;
    }
    else {
      _current_sort = s;
      _reverse = false;
    }
  }

  static File convertToStdDartFile(file){

    if (file is PhotoViewGalleryPageOptions){
      file = file.child;
    }

    File ret;
    if(file is GalleryCell) {
      ret = file.src_image;
    }
    else if (file is FileSystemEntity || file is PlatformFile){
      ret = File(file.path);
    }
    else{
      ret = File(file as String);
    }

    return ret;
  }

  static int _sortByFileDate(a, b) {

    if (a is PhotoViewGalleryPageOptions && b is PhotoViewGalleryPageOptions){
      a = a.child;
      b = b.child;
    }

    DateTime aDate, bDate;
    File aFile = convertToStdDartFile(a);
    File bFile = convertToStdDartFile(b);

    aDate = aFile.lastModifiedSync();
    bDate = bFile.lastModifiedSync();
    return aDate.compareTo(bDate) * (_reverse ? -1 : 1);
  }
  
  static Function getSorting(){
    return _sort();
  }

  static Function _sort(){
    switch(_current_sort) {
      case Sorts.Date:
        return _sortByFileDate;
      case Sorts.Insertion:

        break;
      case Sorts.AddedOnSnap:

        break;
      case Sorts.AddedOnInsta:

        break;
      case Sorts.Filename:

        break;
      case Sorts.DateFriendOnSocials:

        break;
      case Sorts.DateFoundOnBumble:

        break;
        // case :
        //
        //   break;
        // case :
        //
        //   break;
        // case :

        break;
      default:
        return _sortByFileDate;
    }

  }
}
