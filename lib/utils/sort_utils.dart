import 'dart:convert';
import 'dart:io';

import 'package:PhotoWordFind/gallery/gallery_cell.dart';
import 'package:PhotoWordFind/utils/files_utils.dart';
import 'package:PhotoWordFind/utils/storage_utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:shared_preferences/shared_preferences.dart';


Sorts _current_sort = Sorts.Default;
get current_sort => _current_sort;

// The direction of the sort
bool _reverse = true;
get reverse => _reverse;

Future<SharedPreferences> _localPrefs = SharedPreferences.getInstance();
Map<String, Map<String, dynamic>> localCache = {};

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

  static Future updateCache() async{
    if (_localPrefs == null) {
      await _localPrefs;
    }

    SharedPreferences localPrefs = await _localPrefs;
    localPrefs.reload();

    for (String key in localPrefs.getKeys()) {
      String rawJson = localPrefs.getString(key);
      Map<String, dynamic> map;
      try {
        map = json.decode(rawJson);
      }
      on FormatException catch (e) {
        // Assumes this is an OCR that doesn't exist on this phone yet and was created BEFORE format change
        map = await StorageUtils.convertValueToMap(rawJson);
      }

      localCache[key] = map;
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

    DateTime aDate, bDate;
    File aFile = convertToStdDartFile(a);
    File bFile = convertToStdDartFile(b);

    aDate = aFile.lastModifiedSync();
    bDate = bFile.lastModifiedSync();
    return aDate.compareTo(bDate) * (_reverse ? -1 : 1);
  }

  static int _sortByAddedOnSnapchat(a, b) {

    DateTime aDate, bDate;
    File aFile = convertToStdDartFile(a);
    File bFile = convertToStdDartFile(b);

    String aKey = getKeyOfFilename(aFile.path);
    String bKey = getKeyOfFilename(bFile.path);

    bool aSnap = localCache[aKey]['addedOnSnap']??false;
    bool bSnap = localCache[bKey]['addedOnSnap']??false;


    Function internalSorting = getSorting();
    return (aSnap != bSnap) ? (aSnap ? 1 : -1) : _sortByFileDate(a, b);
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
