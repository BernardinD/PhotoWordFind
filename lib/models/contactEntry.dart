import 'dart:io';
import 'package:mobx/mobx.dart';
import 'package:PhotoWordFind/models/location.dart';
import 'package:PhotoWordFind/utils/storage_utils.dart';
import 'package:path/path.dart' as path;

part 'contactEntry.g.dart';

ObservableMap<String, List<String>>? fromJsonObservableMapOfLists(
    Map<String, List<String>>? json) {
  if (json == null) {
    return null; // Handle the null input case, returning null
  }
  return ObservableMap<String, List<String>>.of(
      json); // Return the converted ObservableMap
}

Map<String, List<String>>? toJsonObservableMapOfLists(
    ObservableMap<String, List<String>>? object) {
  if (object == null) {
    return null; // Handle the null input case, returning null
  }
  return Map<String, List<String>>.of(
      object); // Convert ObservableMap to regular Map
}

ObservableMap<String, String>? fromJsonObservableMapOfStrings(
    Map<String, String>? json) {
  if (json == null) {
    return null; // Handle the null input case, returning null
  }
  return ObservableMap<String, String>.of(
      json); // Return the converted ObservableMap
}

Map<String, String?>? toJsonObservableMapOfStrings(
    ObservableMap<String, String?>? object) {
  if (object == null) {
    return null; // Handle the null input case, returning null
  }
  return Map<String, String?>.of(
      object); // Convert ObservableMap to regular Map
}

ObservableList<Map<String, String?>>? fromJsonObservableListOfMaps(
    List<Map<String, String?>>? json) {
  if (json == null) {
    return null; // Handle the null input case, returning null
  }
  return ObservableList<Map<String, String?>>.of(
      json); // Return the converted ObservableList
}

List<Map<String, String>>? toJsonObservableListOfMaps(
    ObservableList<Map<String, String>>? object) {
  if (object == null) {
    return null; // Handle the null input case, returning null
  }
  return List<Map<String, String>>.of(
      object); // Convert ObservableList to regular List
}

typedef FieldUpdater<T> = void Function(T model, dynamic value);
final Map<String, FieldUpdater<_ContactEntry>> fieldUpdaters = {
  SubKeys.Name: (model, value) {
    model.name =
        (value is String && value.trim().isNotEmpty) ? value : model.name;
  },
  SubKeys.Age: (model, value) {
    if (value is int) {
      model.age = value;
    } else if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) model.age = parsed;
    }
  },
  SubKeys.Sections: (model, value) {
    if (value is List && value.isNotEmpty) {
      final listOfMaps = value.map((item) {
        if (item is Map) {
          final safeMap = item.map(
            (ky, vl) => MapEntry(
              ky.toString(),
              vl?.toString() ?? "",
            ),
          );
          return ObservableMap<String, String>.of(safeMap);
        }
        return ObservableMap<String, String>();
      }).toList();
      model.sections = ObservableList.of(listOfMaps);
    } else {
      model.sections = null;
    }
  },
  SubKeys.Location: (model, value) {
    if (value is Map) {
      model.location = Location(
        rawLocation: value['name'],
        timezone: value['timezone'] as String?,
      );
    } else {
      model.location = null;
    }
  },
  SubKeys.SocialMediaHandles: (model, value) => model.socialMediaHandles =
      value != null
          ? ObservableMap.of((value as Map<String, dynamic>)
              .map((key, value) => MapEntry(key, value as String?)))
          : null,
  SubKeys.State: (model, value) => model.state = value as String?,
  // Optional verification dates (ISO 8601 strings). These indicate that a
  // handle has been verified by the user, distinct from "addedOn*" flags.
  SubKeys.VerifiedSnapDate: (model, value) {
    if (value == null || (value is String && value.isEmpty)) {
      model.verifiedOnSnapAt = null;
    } else if (value is String) {
      model.verifiedOnSnapAt = DateTime.tryParse(value);
    } else if (value is DateTime) {
      model.verifiedOnSnapAt = value;
    }
  },
  SubKeys.VerifiedInstaDate: (model, value) {
    if (value == null || (value is String && value.isEmpty)) {
      model.verifiedOnInstaAt = null;
    } else if (value is String) {
      model.verifiedOnInstaAt = DateTime.tryParse(value);
    } else if (value is DateTime) {
      model.verifiedOnInstaAt = value;
    }
  },
  SubKeys.VerifiedDiscordDate: (model, value) {
    if (value == null || (value is String && value.isEmpty)) {
      model.verifiedOnDiscordAt = null;
    } else if (value is String) {
      model.verifiedOnDiscordAt = DateTime.tryParse(value);
    } else if (value is DateTime) {
      model.verifiedOnDiscordAt = value;
    }
  },
  // Moved-to date (neutral key only)
  SubKeys.MovedToArchiveBucketDate: (model, value) {
    if (value == null || (value is String && value.isEmpty)) {
      model.movedToArchiveBucketAt = null;
    } else if (value is String) {
      model.movedToArchiveBucketAt = DateTime.tryParse(value);
    } else if (value is DateTime) {
      model.movedToArchiveBucketAt = value;
    }
  },
};

/// ContactEntry autosave contract
///
/// - Autosave is implemented via a MobX `reaction` watching `toJson()`. When
///   any observable field changes, the reaction runs and persists the entry
///   if and only if `_suppressAutoSave == false`.
///
/// - Storage writes are coalesced: `StorageUtils.save(...)` debounces per
///   entry (currently ~600ms). Rapid, successive updates are merged into a
///   single write once changes go idle, reducing disk churn.
///
/// - Single-field actions (e.g., `updateSnapchat/Instagram/Discord`,
///   `add*`, `reset*`) explicitly set `_suppressAutoSave = false` and LEAVE it
///   enabled at the end. This allows the reaction to schedule a debounced
///   save automatically after small user-driven changes.
///
/// - Batch/merge operations (e.g., `mergeFromJson`) temporarily set
///   `_suppressAutoSave = true` while applying multiple field updates, then
///   restore it to `false` once finished. Optionally, they may also trigger
///   an explicit save for immediate persistence.
///
/// Guidance:
/// - Prefer keeping `_suppressAutoSave = false` during normal UI updates so
///   the reaction persists via the debounced save.
/// - Only set `_suppressAutoSave = true` to silence autosave during a bounded
///   batch of changes; always restore it to `false` when done.
/// - Avoid flipping suppression back to `true` at the end of single-field
///   actions; the debouncer already prevents excessive writes.
class ContactEntry extends _ContactEntry with _$ContactEntry {
  ContactEntry(
      {required this.identifier,
      required String imagePath,
      required this.dateFound,
      required Map<String, dynamic> json,
      bool isNewImport = false})
      : isNewImport = isNewImport,
        super(
          imagePath: imagePath,
          ocr: json[SubKeys.OCR],
          state: json[SubKeys.State] ?? path.basename(path.dirname(imagePath)),
          name: (json[SubKeys.Name] as String?)?.isNotEmpty ?? false
              ? json[SubKeys.Name]
              : null,
          age: json[SubKeys.Age] is int ? json[SubKeys.Age] : null,
          dateAddedOnSnap: json[SubKeys.SnapDate] != null &&
                  json[SubKeys.SnapDate].isNotEmpty
              ? DateTime.parse(json[SubKeys.SnapDate])
              : null,
          instaUsername: json[SubKeys.InstaUsername],
          discordUsername: json[SubKeys.DiscordUsername],
          snapUsername: json[SubKeys.SnapUsername],
          dateAddedOnInsta: json[SubKeys.InstaDate] != null &&
                  json[SubKeys.InstaDate].isNotEmpty
              ? DateTime.parse(json[SubKeys.InstaDate])
              : null,
          dateAddedOnDiscord: json[SubKeys.DiscordDate] != null &&
                  json[SubKeys.DiscordDate].isNotEmpty
              ? DateTime.parse(json[SubKeys.DiscordDate])
              : null,
          // Verification dates are separate from platform add flags
          verifiedOnSnapAt: (json[SubKeys.VerifiedSnapDate] is String &&
                  (json[SubKeys.VerifiedSnapDate] as String).isNotEmpty)
              ? DateTime.parse(json[SubKeys.VerifiedSnapDate])
              : null,
          verifiedOnInstaAt: (json[SubKeys.VerifiedInstaDate] is String &&
                  (json[SubKeys.VerifiedInstaDate] as String).isNotEmpty)
              ? DateTime.parse(json[SubKeys.VerifiedInstaDate])
              : null,
          verifiedOnDiscordAt: (json[SubKeys.VerifiedDiscordDate] is String &&
                  (json[SubKeys.VerifiedDiscordDate] as String).isNotEmpty)
              ? DateTime.parse(json[SubKeys.VerifiedDiscordDate])
              : null,
          addedOnSnap: json[SubKeys.AddedOnSnap] ?? false,
          addedOnInsta: json[SubKeys.AddedOnInsta] ?? false,
          addedOnDiscord: json[SubKeys.AddedOnDiscord] ?? false,
          previousHandles: ObservableMap.of(
              (json[SubKeys.PreviousUsernames] as Map<String, dynamic>?)?.map(
                    (key, value) => MapEntry(
                        key,
                        value != null
                            ? ObservableList<String>.of((value as List<dynamic>)
                                .nonNulls
                                .cast<String>())
                            : ObservableList<String>()),
                  ) ??
                  <String, ObservableList<String>>{
                    SubKeys.SnapUsername: ObservableList<String>(),
                    SubKeys.InstaUsername: ObservableList<String>(),
                  }),
          notes: json[SubKeys.Notes],
        ) {
    _setupAutoSave();
  }
  final String identifier;
  final DateTime dateFound;
  // Transient flag: true when this instance was just created during import.
  // Not persisted; used to gate first-time post-processing behavior.
  final bool isNewImport;

  /// Factory constructor to create a ContactEntry from JSON data.
  /// But note, this version is meant for the initial migration from the shared preferences implementation,
  /// so eventually the input parameter `[imagePath]` will be removed, since it should
  /// be in the stored json data.
  factory ContactEntry.fromJson(
      String storageKey, String imagePath, Map<String, dynamic> json,
      {bool save = false}) {
    var instance = ContactEntry(
        identifier: storageKey,
        imagePath: imagePath,
        dateFound: File(imagePath).lastModifiedSync(),
        json: json);

    instance.mergeFromJson(json, save);

    return instance;
  }

  /// Factory constructor to create a ContactEntry from JSON data.
  /// This version of the factory constructor is meant to be used with the
  /// new implementation of the ContactEntry, which already stores the image path
  /// the Json data
  factory ContactEntry.fromJson2(String storageKey, Map<String, dynamic> json,
      {bool save = false}) {
    final imageFilePath = json['imagePath'] as String;
    var instance = ContactEntry(
        identifier: storageKey,
        imagePath: imageFilePath,
        dateFound: File(imageFilePath).lastModifiedSync(),
        json: json);

    instance.mergeFromJson(json, save);

    return instance;
  }

  void mergeFromJson(Map<String, dynamic> json_, bool save) {
    _suppressAutoSave = true;

    json_.forEach((key, value) {
      final updater = fieldUpdaters[key];
      if (updater != null) {
        updater(this, value);
      }
    });
    extractedText = extractedText ?? ocr;
    snapUsername = socialMediaHandles?[SubKeys.SnapUsername] ?? snapUsername;
    instaUsername = socialMediaHandles?[SubKeys.InstaUsername] ?? instaUsername;
    discordUsername =
        socialMediaHandles?[SubKeys.DiscordUsername] ?? discordUsername;

    _suppressAutoSave = false;
    if (save) {
      _saveToPreferences();
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'imagePath': imagePath,
      SubKeys.OCR: ocr,
      SubKeys.SnapUsername: snapUsername,
      SubKeys.InstaUsername: instaUsername,
      SubKeys.DiscordUsername: discordUsername,
      SubKeys.AddedOnSnap: addedOnSnap,
      SubKeys.AddedOnInsta: addedOnInsta,
      SubKeys.AddedOnDiscord: addedOnDiscord,
      SubKeys.SnapDate: dateAddedOnSnap?.toIso8601String(),
      SubKeys.InstaDate: dateAddedOnInsta?.toIso8601String(),
      SubKeys.DiscordDate: dateAddedOnDiscord?.toIso8601String(),
      // Persist verification separate from add flags
      SubKeys.VerifiedSnapDate: verifiedOnSnapAt?.toIso8601String(),
      SubKeys.VerifiedInstaDate: verifiedOnInstaAt?.toIso8601String(),
      SubKeys.VerifiedDiscordDate: verifiedOnDiscordAt?.toIso8601String(),
      SubKeys.PreviousUsernames: previousHandles?.isNotEmpty ?? false
          ? Map.from(previousHandles!
              .map((key, value) => MapEntry(key, value.toList())))
          : null,
      SubKeys.Notes: notes,
      SubKeys.SocialMediaHandles: socialMediaHandles?.isNotEmpty ?? false
          ? Map.from(socialMediaHandles!)
          : null,
      SubKeys.Sections: sections?.isNotEmpty ?? false
          ? sections!.toList().map(Map.from).toList()
          : null,
      SubKeys.State: state,
      SubKeys.Name: name,
      SubKeys.Age: age,
      SubKeys.Location: location?.toJson(),
  // Track when entry was moved into the archive bucket via a neutral key.
  SubKeys.MovedToArchiveBucketDate: movedToArchiveBucketAt?.toIso8601String(),
    };
  }

  void _setupAutoSave() {
    reaction((_) => toJson(),
        (_) => !_suppressAutoSave ? _saveToPreferences() : null);
  }

  Future<void> _saveToPreferences() async {
    await StorageUtils.save(this);
  }
}

/// This class represents the data parsed from each image and has an update tracking
/// on each fail as to allow for syncing the sharedPreferences (presistent data)
/// with the update values. Also, each field is able to be nullable as to account
/// for failed transcribing and still wanting to display the image in the UI
/// for reprocessing or optical feedback to the user.
abstract class _ContactEntry with Store {
  // _ContactEntry();

  // Variable used for disabling auto updating of persistence
  bool _suppressAutoSave = true;

  /// Holds all the transcribed data. For other entries this will be the ocr.
  /// And for newer ones this will be all the values of "sections" for now.
  /// In the future will possible be just "my bio" or removed all togeter
  /// in place of image overlaying.
  @observable
  String? extractedText;

  @observable
  DateTime? movedToArchiveBucketAt;

  @observable
  String imagePath;

  /// The ocr scanned from images BEFORE switching over to chatGPT approach.
  final String? ocr;

  @observable
  String? snapUsername;

  @observable
  String? instaUsername;

  @observable
  String? discordUsername;

  @observable
  DateTime? dateAddedOnSnap;

  @observable
  DateTime? dateAddedOnInsta;

  @observable
  DateTime? dateAddedOnDiscord;

  // Verification dates (distinct from "addedOn*" flags). If set, the handle
  // has been verified by the user for the respective platform.
  @observable
  DateTime? verifiedOnSnapAt;
  @observable
  DateTime? verifiedOnInstaAt;
  @observable
  DateTime? verifiedOnDiscordAt;

  @observable

  /// Indicates that a friend request on Snapchat was believed to succeed.
  /// Because the app cannot verify the add directly, this may need to be
  /// reset manually if the request was never accepted.
  bool addedOnSnap;

  @observable

  /// Same as [addedOnSnap] but for Instagram.
  bool addedOnInsta;

  @observable

  /// Same as [addedOnSnap] but for Discord.
  bool addedOnDiscord;

  @observable
  String? state;

  @observable
  // @JsonKey(
  //     fromJson: fromJsonObservableMapOfLists,
  //     toJson: toJsonObservableMapOfLists)
  ObservableMap<String, ObservableList<String>>? previousHandles;

  /// Stored text of user notes and reminders for this person
  @observable
  String? notes;

  // New chatGPT responses (mutable to allow post-processing fill-in)
  String? name;

  int? age;

  Location? location;

  /// The chatGPT response of the handles seen in the sent image. All though
  /// there are specific entries for each common handle type, this entry is
  /// kept as to make it much easier to combine maps of the pre-existing map
  /// and all new reiteration for this image.
  @observable
  ObservableMap<String, String?>? socialMediaHandles;

  @observable
  ObservableList<ObservableMap<String, String>>? sections;

  @action
  updateSnapchat(String snapchat) {
    // Enable autosave for this action; we intentionally LEAVE it enabled
    // at the end so the reaction can trigger a debounced save.
    _suppressAutoSave = false;
    // Track previous handle
    if (snapUsername != null && snapUsername!.isNotEmpty) {
      _ensurePrevList(SubKeys.SnapUsername).add(snapUsername!);
    }
    // Update primary field
    snapUsername = snapchat;
    // Keep aggregated map in sync
    _ensureHandlesMap()[SubKeys.SnapUsername] = snapchat;
    // Changing the handle invalidates any prior verification
    verifiedOnSnapAt = null;
  }

  @action
  updateInstagram(String instagram) {
    // Enable autosave and keep it enabled for reaction/debounced persistence.
    _suppressAutoSave = false;
    if (instaUsername != null && instaUsername!.isNotEmpty) {
      _ensurePrevList(SubKeys.InstaUsername).add(instaUsername!);
    }
    instaUsername = instagram;
    _ensureHandlesMap()[SubKeys.InstaUsername] = instagram;
    verifiedOnInstaAt = null;
  }

  @action
  updateDiscord(String discord) {
    // Enable autosave and keep it enabled for reaction/debounced persistence.
    _suppressAutoSave = false;
    if (discordUsername != null && discordUsername!.isNotEmpty) {
      _ensurePrevList(SubKeys.DiscordUsername).add(discordUsername!);
    }
    discordUsername = discord;
    _ensureHandlesMap()[SubKeys.DiscordUsername] = discord;
    verifiedOnDiscordAt = null;
  }

  @action
  addSnapchat() {
    // Keep autosave enabled so both fields get persisted in a single debounced save.
    _suppressAutoSave = false;
    dateAddedOnSnap = DateTime.now();
    addedOnSnap = true;
  }

  // Verification toggles (separate from platform add status)
  @action
  verifySnapchat() {
    _suppressAutoSave = false;
    verifiedOnSnapAt = DateTime.now();
  }

  @action
  unverifySnapchat() {
    _suppressAutoSave = false;
    verifiedOnSnapAt = null;
  }

  @action
  addInstagram() {
    // Keep autosave enabled so both fields get persisted in a single debounced save.
    _suppressAutoSave = false;
    dateAddedOnInsta = DateTime.now();
    addedOnInsta = true;
  }

  @action
  verifyInstagram() {
    _suppressAutoSave = false;
    verifiedOnInstaAt = DateTime.now();
  }

  @action
  unverifyInstagram() {
    _suppressAutoSave = false;
    verifiedOnInstaAt = null;
  }

  @action
  addDiscord() {
    // Keep autosave enabled so both fields get persisted in a single debounced save.
    _suppressAutoSave = false;
    dateAddedOnDiscord = DateTime.now();
    addedOnDiscord = true;
  }

  @action
  verifyDiscord() {
    _suppressAutoSave = false;
    verifiedOnDiscordAt = DateTime.now();
  }

  @action
  unverifyDiscord() {
    _suppressAutoSave = false;
    verifiedOnDiscordAt = null;
  }

  @action
  /// Resets Snapchat "Added" state for this entry.
  ///
  /// Intended use: platform-level reset when you are actively undoing a
  /// Snapchat add (e.g., removing/updating the handle). This will clear BOTH
  /// the boolean flag and the date to allow clean reuse.
  ///
  /// Do not use this for the "never friended back" archive flow that happens
  /// when moving to the archive bucket (Strings/Stings). In that flow, we only
  /// flip the boolean (addedOnSnap=false) and preserve dateAddedOnSnap to keep
  /// historical context.
  ///
  /// Keep autosave enabled so both fields get persisted in a single debounced save.
  resetSnapchatAdd() {
    // Called when removing a Snapchat username.
    _suppressAutoSave = false;
    dateAddedOnSnap = null;
    addedOnSnap = false;
  }

  @action
  /// Resets Instagram "Added" state for this entry.
  ///
  /// Intended use: platform-level reset when you are actively undoing an
  /// Instagram add. Clears BOTH the boolean and the date for clean reuse.
  ///
  /// For the archive/"never friended back" flow, only toggle
  /// [addedOnInsta=false] and preserve [dateAddedOnInsta].
  ///
  /// Keep autosave enabled so both fields get persisted in a single debounced save.
  resetInstagramAdd() {
    _suppressAutoSave = false;
    dateAddedOnInsta = null;
    addedOnInsta = false;
  }

  @action
  /// Resets Discord "Added" state for this entry.
  ///
  /// Intended use: platform-level reset when you are actively undoing a
  /// Discord add. Clears BOTH the boolean and the date for clean reuse.
  ///
  /// For the archive/"never friended back" flow, only toggle
  /// [addedOnDiscord=false] and preserve [dateAddedOnDiscord].
  ///
  /// Keep autosave enabled so both fields get persisted in a single debounced save.
  resetDiscordAdd() {
    _suppressAutoSave = false;
    dateAddedOnDiscord = null;
    addedOnDiscord = false;
  }

  _ContactEntry({
    required this.name,
    required this.age,
    required this.ocr,
    required this.imagePath,
    this.state,

    /// If this exists it will be accounted for from the beginning and shouldn't need to be updated
    // this.extractedText,
    this.addedOnSnap = false,
    this.addedOnInsta = false,
    this.addedOnDiscord = false,
    this.snapUsername,
    this.instaUsername,
    this.discordUsername,
    this.dateAddedOnSnap,
    this.dateAddedOnInsta,
    this.dateAddedOnDiscord,
    this.verifiedOnSnapAt,
    this.verifiedOnInstaAt,
    this.verifiedOnDiscordAt,
    this.previousHandles,
    this.notes,
  this.movedToArchiveBucketAt,
    // this.sections,
    // this.socialMediaHandles,
    // this.location,
  }) {
    this.previousHandles = ObservableMap.of(previousHandles ?? {});
    // this.sections = ObservableList.of(sections ?? []);
  }

  // ---- Helpers to ensure observable containers are initialized ----
  ObservableMap<String, String?> _ensureHandlesMap() {
    return socialMediaHandles ??= ObservableMap<String, String?>();
  }

  ObservableList<String> _ensurePrevList(String key) {
    previousHandles ??= ObservableMap<String, ObservableList<String>>();
    final list = previousHandles![key];
    if (list == null) {
      final newList = ObservableList<String>();
      previousHandles![key] = newList;
      return newList;
    }
    return list;
  }

  // Helper to set the moved-to date based on current/future state naming
  @action
  void markMovedToArchiveBucket(DateTime when, {String? targetState}) {
    _suppressAutoSave = false;
  movedToArchiveBucketAt = when; // neutral, survives rename
  }
}
