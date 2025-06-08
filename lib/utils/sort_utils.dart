import 'dart:convert';
import 'dart:io';

import 'package:PhotoWordFind/gallery/gallery_cell.dart';
import 'package:PhotoWordFind/models/contactEntry.dart';
import 'package:PhotoWordFind/utils/files_utils.dart';
import 'package:PhotoWordFind/utils/storage_utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:photo_view/photo_view_gallery.dart';

final DateTime maxDateTime = DateTime(9999, 12, 31);

Sorts _currentSortBy = Sorts.Date;
Sorts? _currentGroupBy;
Sorts get currentSortBy => _currentSortBy;
Sorts? get currentGroupBy => _currentGroupBy;

Map<String, ContactEntry?> localCache = {};

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
    if (newSort != null &&
        (_currentSortBy == newSort || _currentGroupBy == newSort)) {
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
        if (resetGroupBy) _currentGroupBy = null;
      }
    }
  }

  static Future updateCache() async {
    // Use StorageUtils.toMap() to get all keys
    Map<String, String?> allEntries = await StorageUtils.toMap();
    for (String key in allEntries.keys) {
      ContactEntry? entry;
      try {
        entry = await StorageUtils.get(key);
      } catch (e) {
        debugPrint("Failed to load ContactEntry for $key: $e");
        entry = null;
      }
      if (entry == null) {
        debugPrint("Entry is null for key: $key");
        localCache[key] = null;
        continue;
      }
      // Check if the file exists
      if (!File(entry.imagePath).existsSync()) {
        debugPrint(
            "File does not exist for key: $key, path: ${entry.imagePath}");
        localCache[key] = null;
        continue;
      }
      localCache[key] = entry;
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

    String aKey = getKeyOfFilename(aFile.path);
    String bKey = getKeyOfFilename(bFile.path);

    // Defensive: If file doesn't exist or cache entry is missing, use maxDateTime
    if (!aFile.existsSync() || localCache[aKey] == null) {
      aDate = maxDateTime;
    } else {
      aDate = localCache[aKey]!.dateFound;
    }
    if (!bFile.existsSync() || localCache[bKey] == null) {
      bDate = maxDateTime;
    } else {
      bDate = localCache[bKey]!.dateFound;
    }
    return aDate.compareTo(bDate) * (_reverseSortBy ? -1 : 1);
  }

  static int _sortByFileName(a, b) {
    File aFile = convertToStdDartFile(a);
    File bFile = convertToStdDartFile(b);

    return aFile.path.compareTo(bFile.path) * (_reverseSortBy ? -1 : 1);
  }

  static int _sortByDateAddedOnSocial(
      a, b, DateTime? Function(ContactEntry?) getter) {
    File aFile = convertToStdDartFile(a);
    File bFile = convertToStdDartFile(b);

    String aKey = getKeyOfFilename(aFile.path);
    String bKey = getKeyOfFilename(bFile.path);

    DateTime aDate =
        (localCache[aKey] != null ? getter(localCache[aKey]) : null) ??
            maxDateTime;
    DateTime bDate =
        (localCache[bKey] != null ? getter(localCache[bKey]) : null) ??
            maxDateTime;

    int ret;
    ret = aDate.compareTo(bDate);

    return ret * (_reverseSortBy ? -1 : 1);
  }

  static int _sortByDateAddedOnSnapchat(a, b) {
    return _sortByDateAddedOnSocial(
        a, b, (ContactEntry? e) => e?.dateAddedOnSnap);
  }

  static int _sortByDateAddedOnInstagram(a, b) {
    return _sortByDateAddedOnSocial(
        a, b, (ContactEntry? e) => e?.dateAddedOnInsta);
  }

  static int _sortByAddedOnSocial(a, b, bool? Function(ContactEntry?) getter) {
    File aFile = convertToStdDartFile(a);
    File bFile = convertToStdDartFile(b);

    String aKey = getKeyOfFilename(aFile.path);
    String bKey = getKeyOfFilename(bFile.path);

    bool aSnap =
        (localCache[aKey] != null ? getter(localCache[aKey]) : null) ?? false;
    bool bSnap =
        (localCache[bKey] != null ? getter(localCache[bKey]) : null) ?? false;

    Function secondarySort = getSortBy();
    return (aSnap != bSnap)
        ? (aSnap ? -1 : 1) * (_reverseGroupBy ? -1 : 1)
        : secondarySort(aFile, bFile);
  }

  static int _sortByAddedOnSnapchat(a, b) {
    return _sortByAddedOnSocial(a, b, (ContactEntry? e) => e?.addedOnSnap);
  }

  static int _sortByAddedOnInstagram(a, b) {
    return _sortByAddedOnSocial(a, b, (ContactEntry? e) => e?.addedOnInsta);
  }

  static int _sortBySocialUsername(
      a, b, String? Function(ContactEntry?) getter) {
    File aFile = convertToStdDartFile(a);
    File bFile = convertToStdDartFile(b);

    String aKey = getKeyOfFilename(aFile.path);
    String bKey = getKeyOfFilename(bFile.path);

    String aSnap =
        (localCache[aKey] != null ? getter(localCache[aKey]) : null) ?? "";
    String bSnap =
        (localCache[bKey] != null ? getter(localCache[bKey]) : null) ?? "";

    // If both exist throw them in the front and sort them, else throw it to the back
    int ret = 0;
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
    return _sortBySocialUsername(a, b, (ContactEntry? e) => e?.snapUsername);
  }

  static int _sortByInstaUsername(a, b) {
    return _sortBySocialUsername(a, b, (ContactEntry? e) => e?.instaUsername);
  }

  static int _sortByDiscordUsername(a, b) {
    return _sortBySocialUsername(a, b, (ContactEntry? e) => e?.discordUsername);
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
      // return sortUser();
      case Sorts.AddedOnInsta:
        return _sortByAddedOnInstagram;
      // return sortUser();
      default:
        return _sortByAddedOnSnapchat;
      // return sortUser();
    }
  }

  static Function sortUser(Function getField) {
    return ((ContactEntry a, ContactEntry b) {
      Function secondarySort = getSortBy();
      compareBool(getField(a), getField(b)) ??
          secondarySort(a.imagePath, b.imagePath);
    });
  }

  static int? compareBool(bool a, bool b) {
    return (a != b) ? (a ? -1 : 1) * (_reverseGroupBy ? -1 : 1) : null;
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
