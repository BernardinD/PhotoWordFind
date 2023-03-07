import 'dart:convert';
import 'dart:io';

import 'package:PhotoWordFind/gallery/gallery_cell.dart';
import 'package:PhotoWordFind/utils/files_utils.dart';
import 'package:PhotoWordFind/utils/storage_utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:shared_preferences/shared_preferences.dart';

Sorts _currentSortBy = Sorts.Date, _currentGroupBy = null;
Sorts get currentSortBy => _currentSortBy;
Sorts get currentGroupBy => _currentGroupBy;

Future<SharedPreferences> _localPrefs = SharedPreferences.getInstance();
Map<String, Map<String, dynamic>> localCache = {};

enum Sorts {
  Date,
  Insertion,
  AddedOnSnap,
  AddedOnInsta,
  Filename,
  DateAddedOnSnap,
  DateFoundOnBumble,
  GroupByTitle,
  SortByTitle,
  SnapDetected,
}

Set<Sorts> sortsTitles = {
  Sorts.GroupByTitle,
  Sorts.SortByTitle,
};

Set<Sorts> sortBy = {
  Sorts.Date,
  Sorts.Insertion,
  Sorts.Filename,
  Sorts.DateFoundOnBumble,
  Sorts.DateAddedOnSnap,
  Sorts.SnapDetected,
};

Set<Sorts> groupBy = {
  Sorts.AddedOnSnap,
  Sorts.AddedOnInsta,
};

class Sortings {
  // The direction of the sort
  static bool _reverseSortBy = false, _reverseGroupBy = false;
  static get reverseSortBy => _reverseSortBy;
  static get reverseGroupBy => _reverseGroupBy;

  static updateSortType(Sorts s, {bool resetGroupBy = true}) {
    // Reverse recently selected sort
    if (s != null && (_currentSortBy == s || _currentGroupBy == s)) {
      if (sortBy.contains(s))
        _reverseSortBy = !_reverseSortBy;
      else
        _reverseGroupBy = !_reverseGroupBy;
    }
    // If selected a currently unused sort
    else {
      // If s is null then it's a groupBy sort that's being disabled
      if (s == null) {
        _reverseGroupBy = false;
        _currentGroupBy = null;
      }
      // If new groupBy sort
      else if (groupBy.contains(s)) {
        _reverseGroupBy = false;
        _currentGroupBy = s;
      }
      // If new sortBy sort
      else {
        _reverseSortBy = false;
        _currentSortBy = s;
        if (resetGroupBy)
          _currentGroupBy = null;
      }
    }
  }

  static Future updateCache() async {
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
      } on FormatException catch (e) {
        // Assumes this is an OCR that doesn't exist on this phone yet and was created BEFORE format change
        map = StorageUtils.convertValueToMap(rawJson);
      }

      localCache[key] = map;
    }
    // localCache.entries.where((MapEntry<String, Map> e) => e.value[''])
  }

  static File convertToStdDartFile(file) {
    if (file is PhotoViewGalleryPageOptions) {
      file = file.child;
    }

    File ret;
    if (file is GalleryCell) {
      ret = file.srcImage;
    } else if (file is FileSystemEntity || file is PlatformFile) {
      ret = File(file.path);
    } else {
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
    return aDate.compareTo(bDate) * (_reverseSortBy ? -1 : 1);
  }

  static int _sortByDateAddedOnSnapchat(a, b){
    File aFile = convertToStdDartFile(a);
    File bFile = convertToStdDartFile(b);

    String aKey = getKeyOfFilename(aFile.path);
    String bKey = getKeyOfFilename(bFile.path);

    String aDateStr = localCache[aKey]['dateAddedOnSnap'] ?? "";
    String bDateStr = localCache[bKey]['dateAddedOnSnap'] ?? "";

    int ret;
    if (aDateStr.isEmpty && bDateStr.isEmpty) {
      ret = 0;
    }
    else if (aDateStr.isEmpty) {
      ret = 1;
    }
    else if (bDateStr.isEmpty) {
      ret = -1;
    }
    else {
      DateTime aDate = DateTime.parse(aDateStr);
      DateTime bDate = DateTime.parse(bDateStr);
      ret =  aDate.compareTo(bDate);
    }

    return ret * (_reverseSortBy ? -1 : 1);
  }

  static int _sortByAddedOnSnapchat(a, b) {
    DateTime aDate, bDate;
    File aFile = convertToStdDartFile(a);
    File bFile = convertToStdDartFile(b);

    String aKey = getKeyOfFilename(aFile.path);
    String bKey = getKeyOfFilename(bFile.path);

    bool aSnap = localCache[aKey]['addedOnSnap'] ?? false;
    bool bSnap = localCache[bKey]['addedOnSnap'] ?? false;

    Function secondarySort = getSortBy();
    return (aSnap != bSnap)
        ? (aSnap ? -1 : 1) * (_reverseGroupBy ? -1 : 1)
        : secondarySort(aFile, bFile);
  }

  static int _sortBySnapUser(a, b) {
    DateTime aDate, bDate;
    File aFile = convertToStdDartFile(a);
    File bFile = convertToStdDartFile(b);

    String aKey = getKeyOfFilename(aFile.path);
    String bKey = getKeyOfFilename(bFile.path);

    String aSnap = localCache[aKey]['snap'];
    String bSnap = localCache[bKey]['snap'];

    Function secondarySort = getSortBy();
    // If both exist throw them in the front and sort them, else throw it to the back
    int ret=0;
    if (aSnap.isEmpty && bSnap.isEmpty) {
      ret = 0;
    } else if (aSnap.isEmpty || aSnap.length < 2) {
      ret = 1;
    } else if (bSnap.isEmpty) {
      ret = -1;
    } else {
      ret = aSnap.compareTo(bSnap);
    }

    return ret * (_reverseSortBy ? -1 : 1);
  }

  static Function getSorting() {
    return _sort();
  }

  static Function _sort() {
    Function sort = _currentGroupBy != null ? getGroupBy() : getSortBy();
    return sort;
  }

  static Function getGroupBy() {
    switch (_currentGroupBy) {
      case Sorts.AddedOnSnap:
        return _sortByAddedOnSnapchat;
      case Sorts.AddedOnInsta:
        break;
      default:
        return _sortByAddedOnSnapchat;
    }
  }

  static Function getSortBy() {
    switch (_currentSortBy) {
      case Sorts.Date:
        return _sortByFileDate;
      case Sorts.Insertion:
        break;
      case Sorts.Filename:
        break;
      case Sorts.DateAddedOnSnap:
        return _sortByDateAddedOnSnapchat;
      case Sorts.DateFoundOnBumble:
        break;
      case Sorts.SnapDetected:
        return _sortBySnapUser;
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
