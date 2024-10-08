import 'dart:convert';
import 'dart:io';

import 'package:PhotoWordFind/gallery/gallery_cell.dart';
import 'package:PhotoWordFind/utils/files_utils.dart';
import 'package:PhotoWordFind/utils/storage_utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:shared_preferences/shared_preferences.dart';

Sorts _currentSortBy = Sorts.Date;
Sorts? _currentGroupBy;
Sorts get currentSortBy => _currentSortBy;
Sorts? get currentGroupBy => _currentGroupBy;

Future<SharedPreferences>? _localPrefs = SharedPreferences.getInstance();
Map<String, Map<String, dynamic>?> localCache = {};

enum Sorts {
  SortByTitle,
  GroupByTitle,
  Date,
  Filename,
  DateAddedOnSnap,
  DateAddedOnInsta,
  SnapDetected,
  InstaDetected,
  DiscordDetected,
  AddedOnSnap,
  AddedOnInsta,
}

Set<Sorts> sortsTitles = {
  Sorts.GroupByTitle,
  Sorts.SortByTitle,
};

Set<Sorts> sortBy = {
  Sorts.Date,
  Sorts.Filename,
  Sorts.DateAddedOnSnap,
  Sorts.DateAddedOnInsta,
  Sorts.SnapDetected,
  Sorts.InstaDetected,
  Sorts.DiscordDetected,
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

  static updateSortType(Sorts? newSort, {bool resetGroupBy = true}) {
    // Reverse recently selected sort
    if (newSort != null && (_currentSortBy == newSort || _currentGroupBy == newSort)) {
      if (sortBy.contains(newSort))
        _reverseSortBy = !_reverseSortBy;
      else
        _reverseGroupBy = !_reverseGroupBy;
    }
    // If selected a currently unused sort
    else {
      // If s is null then it's a groupBy sort that's being disabled
      if (newSort == null) {
        _reverseGroupBy = false;
        _currentGroupBy = null;
      }
      // If new groupBy sort
      else if (groupBy.contains(newSort)) {
        _reverseGroupBy = false;
        _currentGroupBy = newSort;
      }
      // If new sortBy sort
      else {
        _reverseSortBy = false;
        _currentSortBy = newSort;
        // TODO: I believe this can be removed (test at later date)
        if (resetGroupBy)
          _currentGroupBy = null;
      }
    }
  }

  static Future updateCache() async {
    if (_localPrefs == null) {
      await _localPrefs;
    }

    SharedPreferences localPrefs = (await _localPrefs)!;
    localPrefs.reload();

    for (String key in localPrefs.getKeys()) {
      String rawJson = localPrefs.getString(key)!;
      Map<String, dynamic> map = StorageUtils.convertValueToMap(rawJson , enforceMapOutput: true)!;

      if(!map.containsKey("discord") ?? false){
        debugPrint("this key failed: $key");
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

  static int _sortByFileName(a, b) {
    File aFile = convertToStdDartFile(a);
    File bFile = convertToStdDartFile(b);

    return aFile.path.compareTo(bFile.path) * (_reverseSortBy ? -1 : 1);
  }

  static int _sortByDateAddedOnSocial(a, b, String subKey){
    File aFile = convertToStdDartFile(a);
    File bFile = convertToStdDartFile(b);

    String aKey = getKeyOfFilename(aFile.path);
    String bKey = getKeyOfFilename(bFile.path);

    String aDateStr = localCache[aKey]![subKey] ?? "";
    String bDateStr = localCache[bKey]![subKey] ?? "";

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

  static int _sortByDateAddedOnSnapchat(a, b){
    return _sortByDateAddedOnSocial(a, b, SubKeys.SnapDate);
  }

  static int _sortByDateAddedOnInstagram(a, b){
    return _sortByDateAddedOnSocial(a, b, SubKeys.InstaDate);
  }

  static int _sortByAddedOnSocial(a, b, String subKey) {
    File aFile = convertToStdDartFile(a);
    File bFile = convertToStdDartFile(b);

    String aKey = getKeyOfFilename(aFile.path);
    String bKey = getKeyOfFilename(bFile.path);

    bool aSnap = localCache[aKey]![subKey] ?? false;
    bool bSnap = localCache[bKey]![subKey] ?? false;

    Function secondarySort = getSortBy();
    return (aSnap != bSnap)
        ? (aSnap ? -1 : 1) * (_reverseGroupBy ? -1 : 1)
        : secondarySort(aFile, bFile);
  }

  static int _sortByAddedOnSnapchat(a, b) {
    return _sortByAddedOnSocial(a, b, SubKeys.AddedOnSnap);
  }

  static int _sortByAddedOnInstagram(a, b) {
    return _sortByAddedOnSocial(a, b, SubKeys.AddedOnInsta);
  }

  static int _sortBySocialUsername(a, b, String subKey) {
    File aFile = convertToStdDartFile(a);
    File bFile = convertToStdDartFile(b);

    String aKey = getKeyOfFilename(aFile.path);
    String bKey = getKeyOfFilename(bFile.path);

    String aSnap = localCache[aKey]![subKey];
    String bSnap = localCache[bKey]![subKey];

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

  static int _sortBySnapUsername(a, b) {
    return _sortBySocialUsername(a, b, SubKeys.SnapUsername);
  }

  static int _sortByInstaUsername(a, b) {
    return _sortBySocialUsername(a, b, SubKeys.InstaUsername);
  }

  static int _sortByDiscordUsername(a, b) {
    return _sortBySocialUsername(a, b, SubKeys.DiscordUsername);
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
        return _sortByAddedOnInstagram;
      default:
        return _sortByAddedOnSnapchat;
    }
  }

  static Function getSortBy() {
    switch (_currentSortBy) {
      case Sorts.Date:
        return _sortByFileDate;
      case Sorts.Filename:
        return _sortByFileName;
      case Sorts.DateAddedOnSnap:
        return _sortByDateAddedOnSnapchat;
      case Sorts.DateAddedOnInsta:
        return _sortByDateAddedOnInstagram;
      case Sorts.SnapDetected:
        return _sortBySnapUsername;
      case Sorts.InstaDetected:
        return _sortByInstaUsername;
      case Sorts.DiscordDetected:
        return _sortByDiscordUsername;
      default:
        return _sortByFileDate;
    }
  }
}
