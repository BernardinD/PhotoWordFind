import 'dart:async';
import 'dart:io';

import 'package:PhotoWordFind/screens/gallery/image_gallery_screen.dart';
import 'package:PhotoWordFind/gallery/gallery.dart';
import 'package:PhotoWordFind/services/chat_gpt_service.dart';
import 'package:PhotoWordFind/social_icons.dart';
import 'package:PhotoWordFind/utils/cloud_utils.dart';
import 'package:PhotoWordFind/utils/operations_utils.dart';
import 'package:PhotoWordFind/utils/sort_utils.dart';
import 'package:PhotoWordFind/utils/storage_utils.dart';
import 'package:PhotoWordFind/utils/toast_utils.dart';
import 'package:PhotoWordFind/widgets/confirmation_dialog.dart';
import 'package:catcher/catcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:permission_handler/permission_handler.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:device_apps/device_apps.dart';
import 'package:path/path.dart' as path;
import 'package:sn_progress_dialog/sn_progress_dialog.dart';
import 'package:timezone/data/latest.dart' as tz;

// import 'package:image_picker/image_picker.dart';

void main() {
  CatcherOptions debugOptions =
      CatcherOptions(PageReportMode(), [ConsoleHandler()]);
  CatcherOptions releaseOptions = CatcherOptions(PageReportMode(), [
    EmailManualHandler(["bdezius@gmail.com"],
        emailTitle: "Photo Word Find - Crashed", emailHeader: "Error message")
  ]);

  Catcher(
    rootWidget: MyRootWidget(key: MyRootWidget.globalKey),
    debugConfig: debugOptions,
    releaseConfig: releaseOptions,
    ensureInitialized: true,
  );
}

/// Helper to allow either UI to toggle between legacy/new modes.
class UiMode {
  static Future<bool> isNewUi() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(MyRootWidget.prefUseNewUi) ?? true;
  }

  static Future<void> switchTo(bool useNew) async {
    final state = MyRootWidget.globalKey.currentState;
    if (state != null) {
      await state.switchUi(useNew); // live swap
      return;
    }
    final prefs = await SharedPreferences.getInstance(); // fallback
    await prefs.setBool(MyRootWidget.prefUseNewUi, useNew);
  }
}

/// Handles all the inititalization of the app
Future<void> initializeApp() async {
  ChatGPTService.initialize();

  tz.initializeTimeZones();

  await StorageUtils.init();

  // Ensure cloud backup is ready before any optional migration-triggered sync
  await CloudUtils.firstSignIn();

  // One-time migration: copy platform added dates to verification dates where missing
  try {
    final migrated = await StorageUtils.migrateVerificationDatesIfNeeded();
    if (migrated > 0) {
      debugPrint('Verification migration updated $migrated entries.');
    }
  } catch (e) {
    debugPrint('Verification migration error: $e');
  }

  // await StorageUtils.resetImagePaths();
}

class MyRootWidget extends StatefulWidget {
  const MyRootWidget({Key? key}) : super(key: key);

  static const String prefUseNewUi = 'use_new_ui_candidate';
  static final GlobalKey<MyRootWidgetState> globalKey =
      GlobalKey<MyRootWidgetState>();

  @override
  State<MyRootWidget> createState() => MyRootWidgetState();
}

class MyRootWidgetState extends State<MyRootWidget> {
  bool _initialized = false;
  bool _useNew = true; // default to new

  bool get useNewUi => _useNew;

  static Future<bool> _readPref() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(MyRootWidget.prefUseNewUi) ?? true;
  }

  Future<void> _writePref(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(MyRootWidget.prefUseNewUi, v);
  }

  Future<void> switchUi(bool useNew) async {
    if (_useNew == useNew) return;
    setState(() => _useNew = useNew);
    await _writePref(useNew);
  }

  @override
  void initState() {
    super.initState();
    (() async {
      await initializeApp();
      _useNew = await _readPref();
      if (mounted) setState(() => _initialized = true);
    })();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(primarySwatch: Colors.blue);
    return MaterialApp(
      navigatorKey: Catcher.navigatorKey,
      title: 'Photo Word Find',
      theme: theme,
      home: !_initialized
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : (_useNew
              ? ImageGalleryScreen()
              : MyHomePage(title: 'Photo Word Find')),
    );
  }
}

// LegacyAppShell replaces the old MyApp widget wrapper. All static legacy
// utilities (progress dialog, gallery reference, frame updates) now live here
// without creating a nested MaterialApp.
class LegacyAppShell {
  static ProgressDialog? _pr;
  static ProgressDialog get pr {
    if (_pr == null) {
      throw StateError('ProgressDialog accessed before initialization');
    }
    return _pr!;
  }

  static late final Gallery _gallery = Gallery();
  static Gallery get gallery => _gallery;
  static Function? updateFrame; // may be null until legacy UI initializes
  static void invokeFrame(VoidCallback fn) {
    try {
      updateFrame?.call(fn);
    } catch (e, s) {
      debugPrint('invokeFrame error: $e\n$s');
    }
  }

  static Future<void> init(BuildContext context) async {
    // Always recreate on init to avoid stale context after UI mode switch.
    _pr = ProgressDialog(context: context);
  }

  static Future<void> showProgress(
      {required bool autoComplete, int limit = 1}) async {
    debugPrint("Entering showProgress()...");
    if (pr.isOpen()) {
      debugPrint("Closing.");
      pr.close();
    } else {
      debugPrint("Not open.");
      pr.update(value: 0);
    }

    debugPrint("limit: $limit");
    var temp = pr.show(
      msg: 'Please Waiting...',
      max: limit,
      backgroundColor: Colors.white,
      elevation: 10.0,
      msgColor: Colors.black,
      msgFontSize: 19.0,
      msgFontWeight: FontWeight.w600,
      completed: autoComplete
          ? Completed(
              completedMsg: "Done!",
              completionDelay: 1000,
            )
          : null,
    );
    debugPrint("show return: $temp");
    debugPrint("Leaving showProgress()...");
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key? key, this.title}) : super(key: key);

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String? title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<File> _images = [];
  List<String> _results = [];

  // TODO: Delete after testing
  void debugPrintLargeString(String message, {int chunkSize = 1000}) {
    final pattern = RegExp('.{1,$chunkSize}', dotAll: true);
    pattern.allMatches(message).forEach((match) => debugPrint(match.group(0)));
  }

  Future<void> _sendToChatGPT() async {
    LegacyAppShell.pr.show(max: _images.length);

    try {
      // Build File list from selected ContactEntry image paths
      final srcEntries = gallery.selected.toList();
      final paths = srcEntries.map((e) => e.imagePath).toList();
      _images = paths.map((p) => File(p)).toList();

      var result = await ChatGPTService.processMultipleImages(
          imageFiles: _images, useMiniModel: true);

      setState(() {
        _results.add(result.toString());
        debugPrintLargeString("ChatGPT results: ${result.toString()}");

        // final galleryImages = gallery.images;
        // for (int idx = 0; idx < gallery.images.length; idx++) {
        //   final galleryPage = galleryImages[idx];
        //   final cell = galleryPage.child as GalleryCell;
        //   final geminiResponse = geminiResponseList![idx];
        //   if (gallery.selected.contains(
        //       ((galleryPage.child as GalleryCell).key as ValueKey<String>)
        //           .value)) {
        //     gallery.redoCell(cell.text, geminiResponse[0], geminiResponse[1],
        //         cell.discordUsername, idx);
        //   }
        // }
      });
    } catch (e, s) {
      Catcher.reportCheckedError(e, s);
    }
    LegacyAppShell.pr.close();
  }

  String? _directoryPath;
  Gallery gallery = LegacyAppShell._gallery;

  Map<Sorts?, String> sortings = Map.from({
    Sorts.SortByTitle: "Sort By",
    Sorts.Date: "Date found",
    Sorts.DateAddedOnSnap: "Date Added on Snap",
    Sorts.DateAddedOnInsta: "Date Added on Instagram",
    Sorts.SnapDetected: "Snap Handle",
    Sorts.InstaDetected: "Instagram Handle",
    Sorts.DiscordDetected: "Discord Handle",
    Sorts.GroupByTitle: "Group By",
    null: "None", // Disable GroupBy
    Sorts.AddedOnSnap: "Snap Added",
    Sorts.AddedOnInsta: "Insta Added"
  });
  Sorts? dropdownValue = Sorts.Date;

  String? get directoryPath => _directoryPath;
  String? getDirectoryPath() {
    return directoryPath;
  }

  Future requestPermissions() async {
    var status = await Permission.manageExternalStorage.status;
    if (!status.isGranted) {
      await Permission.manageExternalStorage.request();
    }
  }

  void _attachLegacyProgress() {
    CloudUtils.progressCallback = (
        {double? value,
        String? message,
        bool done = false,
        bool error = false}) {
      try {
        if (message != null) {
          if (!LegacyAppShell.pr.isOpen()) {
            LegacyAppShell.pr.show(max: 1);
          }
          LegacyAppShell.pr.update(value: (value ?? 0).toInt(), msg: message);
        }
        if (done) {
          Future.delayed(const Duration(milliseconds: 400), () {
            if (LegacyAppShell.pr.isOpen()) LegacyAppShell.pr.close();
          });
        }
      } catch (_) {}
    };
  }

  void initState() {
    super.initState();
    _attachLegacyProgress();

    // Ensure ProgressDialog is initialized with context
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await LegacyAppShell.init(context);
    });

    LegacyAppShell.updateFrame = setState;

    // Initalize toast for user alerts
    Toasts.initToasts(context);

    // Request storage permissions
    requestPermissions().then((value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Sign into cloud account
        LegacyAppShell.pr.show(max: 1);
        LegacyAppShell.pr.update(value: 0, msg: "Setting up...");

        CloudUtils.firstSignIn()
            .then((bool signedIn) {
              if (!signedIn) {
                throw Exception("Sign-in failed");
              }
            })
            .onError((dynamic error, stackTrace) async =>
                debugPrint("Sign in error: $error \n$stackTrace")
                    as FutureOr<Null>)
            .whenComplete(() => LegacyAppShell.pr.update(value: 1));
      });
    });

    // Load app images and links
    DeviceApps.getInstalledApplications(
            onlyAppsWithLaunchIntent: true, includeSystemApps: true)
        .then((apps) {
      for (var app in apps) {
        if (app.appName.toLowerCase().contains("kik")) debugPrint("$app");
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Recreate progress dialog if needed when dependencies (context) change after UI mode swap.
    if (LegacyAppShell._pr == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted) await LegacyAppShell.init(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title!),
        actions: [
          IconButton(
            tooltip:
                'Switch to ${MyRootWidget.globalKey.currentState?.useNewUi == true ? 'Legacy' : 'New'} UI',
            icon: Icon(Icons.swap_horiz),
            onPressed: () async {
              final current =
                  MyRootWidget.globalKey.currentState?.useNewUi ?? true;
              final proceed = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Confirm UI Switch'),
                  content: Text('You are about to switch to the ' +
                      (!current ? 'new' : 'legacy') +
                      ' interface. Continue?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel')),
                    TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Switch')),
                  ],
                ),
              );
              if (proceed == true) {
                await UiMode.switchTo(!current);
              }
            },
          ),
        ],
        leading: FutureBuilder(
          future: CloudUtils.isSignedin(),
          builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
            if (snapshot.hasError) throw Exception(snapshot.error);
            if (!snapshot.hasData) {
              debugPrint("Sign-in hasn't finished. Skipping...");
              return Icon(Icons.sync_disabled_rounded);
            }
            return (!snapshot.data!)
                ? ElevatedButton(
                    key: ValueKey(snapshot.data.toString()),
                    child: IconButton(
                      onPressed: null,
                      icon: Icon(Icons.cloud_upload_rounded),
                    ),
                    onPressed: () => CloudUtils.firstSignIn().then((value) =>
                        LegacyAppShell.updateFrame?.call(() => null)),
                  )
                : ElevatedButton(
                    key: ValueKey(snapshot.data.toString()),
                    onPressed: () async {
                      bool result = await showDialog(
                        context: context,
                        builder: (BuildContext context) {
                          return ConfirmationDialog(
                              message: "Are you sure you want to sign out?");
                        },
                      );

                      if (!result) return;
                      CloudUtils.possibleSignOut().then((value) =>
                          LegacyAppShell.updateFrame?.call(() => null));
                    },
                    child: IconButton(
                      onPressed: null,
                      icon: Icon(Icons.logout),
                    ));
          },
        ),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Container(
          height: MediaQuery.of(context).size.height,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Expanded(
                flex: 1,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ElevatedButton(
                      onPressed: showFindPrompt,
                      child: Text("Find"),
                    ),
                    ElevatedButton(
                      // key: ValueKey("Display"),
                      onPressed: () => displaySnaps(true),
                      child: Text("Display"),
                      onLongPress: () => displaySnaps(false),
                    ),
                    ElevatedButton(
                      key: ValueKey("Move"),
                      onPressed: gallery.selected.isNotEmpty ? move : null,
                      child: Text("Move"),
                    ),
                  ],
                ),
              ),
              if (gallery.images.isNotEmpty)
                showGallery()
              // ImageListScreen()
              else if (Operation.isRetryOp())
                showRetry(),
            ],
          ),
        ),
      ),
      persistentFooterButtons: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            width: MediaQuery.of(context).size.width * 1.20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SocialIcon.snapchatIconButton!,
                Spacer(),
                SocialIcon.galleryIconButton!,
                Spacer(),
                SocialIcon.bumbleIconButton!,
                Spacer(),
                FloatingActionButton(
                  heroTag: null,
                  tooltip: 'Change current directory',
                  onPressed: changeDir,
                  child: Icon(Icons.drive_folder_upload),
                ),
                Spacer(),
                SocialIcon.instagramIconButton!,
                Spacer(),
                SocialIcon.discordIconButton!,
                Spacer(),
                SocialIcon.kikIconButton!,
              ],
            ),
          ),
        ),
      ],
      floatingActionButton: FloatingActionButton(
        onPressed: gallery.selected.isEmpty ? null : _sendToChatGPT,
        tooltip: 'Pick Image',
        child: const Icon(Icons.camera_alt),
      ),
    );
  }

  void move() async {
    // Move selected images to new directory
    if (gallery.selected.isNotEmpty) {
      // Choose new directory
      String? newDir = await FilePicker.platform.getDirectoryPath();

      if (newDir != null) {
        Operation.run(Operations.MOVE, null,
            moveSrcList: gallery.selected.toList(),
            moveDesDir: newDir,
            directoryPath: getDirectoryPath);

        setState(() {
          gallery.removeSelected();
        });
      }
    } else {
      throw Exception("There are no selected files to move");
    }
  }

  // Select picture(s) and run through OCR
  Future<List?> selectImages(bool individual) async {
    late List? paths;

    // If directory path isn't set, have `changeDir` handle picking the files
    if (_directoryPath == null || _directoryPath!.length < 1) {
      await changeDir();
      if (_directoryPath == null) {
        // TODO: Show error message "Must select a Directory"
        // ...

        return null;
      }
      print("After changeDir");
    }

    // Select file(s)
    if (individual) {
      bool _multiPick = true;
      FileType _pickingType = FileType.image;
      // Stopwatch timer = Stopwatch(); // removed (unused)
      await LegacyAppShell.showProgress(autoComplete: true);
      paths = (await FilePicker.platform
              .pickFiles(type: _pickingType, allowMultiple: _multiPick))
          ?.files;

      if (paths != null &&
          !File(path.join(_directoryPath!, paths.first.path.split("/").last))
              .existsSync()) {
        // TODO: Show error (selected files didn't exist in directory)
        // ...

        return null;
      }
    } else {
      await LegacyAppShell.showProgress(autoComplete: true);
      paths = Directory(_directoryPath!)
          .listSync(recursive: false, followLinks: false);
    }

    // Assure that list is of right file type
    if (paths != null && paths.isNotEmpty) {
      if (!(paths.first is PlatformFile) && !(paths.first is FileSystemEntity))
        throw ("List of path is is not a PlatformFile or File");
    }

    return paths;
  }

  /// Displays a dialog box for input to the `find` feature
  void showFindPrompt() {
    final formKey = GlobalKey<FormState>();

    Function validatePhrase = (_) {
      if (formKey.currentState!.validate()) {
        formKey.currentState!.save();
      }
    };
    showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
              content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                children: <Widget>[
                  TextFormField(
                    autofocus: true,
                    decoration: InputDecoration(labelText: "Input name"),
                    // TODO: Make validation failure message dynamic
                    validator: (input) => input!.length < 3
                        ? 'Too short. Enter more than 2 letters'
                        : null,
                    onSaved: findSnap,
                    onFieldSubmitted: validatePhrase as void Function(String)?,
                  ),
                  ElevatedButton(
                    onPressed: () => validatePhrase(null),
                    child: Text('Find'),
                  ),
                ],
              ),
            ),
          ));
        });
  }

  /// Looks for the snap name in the directory
  Future findSnap(String? query) async {
    query = query!.trim();

    // If directory path isn't set, have `changeDir` handle picking the files
    if (_directoryPath == null || _directoryPath!.length < 1) {
      await changeDir();
      print("After changeDir");
    }
    Operation.run(Operations.FIND, changeDir,
        findQuery: query, context: context, directoryPath: getDirectoryPath);

    return;
  }

  // Displays all images with a detectable snapchat username in their bio
  Future displaySnaps(bool select) async {
    debugPrint("Entering displaySnaps()...");

    Operations op = select ? Operations.DISPLAY_SELECT : Operations.DISPLAY_ALL;

    // _pr.show();

    // Choose files to extract text from
    List? paths = await selectImages(select);

    Operation.run(op, changeDir, displayImagesList: paths, context: context);

    debugPrint("Leaving displaySnaps()...");
  }

  Future changeDir() async {
    debugPrint("Entering changeDir()...");

    // Reset callback function
    try {
      await FilePicker.platform.pickFiles(
          type: FileType.image,
          onFileLoading: (_) => debugPrint(""),
          allowedExtensions: ["fail"]);
    } catch (e) {
      debugPrint("changeDir >> $e");
    }
    // To get path and default to this location for file pick
    // sleep(Duration(seconds:1));
    _directoryPath = await FilePicker.platform.getDirectoryPath();

    debugPrint("Leaving changeDir()...");
  }

  @override
  void dispose() {
    // TODO: implement dispose
    super.dispose();

    if (!Platform.environment.containsKey('FLUTTER_TEST'))
      FilePicker.platform.clearTemporaryFiles();
  }

  showGallery() {
    return Expanded(
      flex: 8,
      child: Container(
        child: Column(
          children: [
            Expanded(
              flex: 2,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                // crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: MediaQuery.of(context).size.width / 3,
                  ),
                  VerticalDivider(width: 1.0),
                  SizedBox(
                    width: MediaQuery.of(context).size.width / 3,
                    child: Center(
                      child: Text(
                          "${gallery.galleryController.positions.isNotEmpty ? gallery.galleryController.page!.round() + 1 : gallery.galleryController.initialPage + 1}"
                          "/${gallery.images.length}"),
                    ),
                  ),
                  VerticalDivider(width: 1.0),
                  Center(
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width / 3 - 2,
                      child: FittedBox(
                        child: DropdownButton<String>(
                          value: sortings[dropdownValue],
                          alignment: AlignmentDirectional.topEnd,
                          items: sortings.entries.map<DropdownMenuItem<String>>(
                              (MapEntry<Sorts?, String> entry) {
                            if (sortsTitles.contains(entry.key)) {
                              return DropdownMenuItem(
                                  enabled: false,
                                  child: Column(
                                    children: [
                                      // Divider(),
                                      Text(entry.value),
                                      Divider(),
                                    ],
                                  ));
                            } else {
                              return DropdownMenuItem<String>(
                                value: entry.value,
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(entry.value),
                                    if (dropdownValue == entry.key ||
                                        (entry.key == currentSortBy &&
                                            dropdownValue == currentGroupBy))
                                      groupBy.contains(entry.key)
                                          ? Icon(Sortings.reverseGroupBy
                                              ? Icons.arrow_back
                                              : Icons.arrow_forward)
                                          : Icon(Sortings.reverseSortBy
                                              ? Icons.arrow_back
                                              : Icons.arrow_forward),
                                  ],
                                ),
                              );
                            }
                          }).toList(),
                          onChanged: (String? value) {
                            // This is called when the user selects an item.
                            setState(() {
                              dropdownValue = sortings.entries
                                  .firstWhere((entry) => entry.value == value)
                                  .key;
                              Sortings.updateSortType(dropdownValue,
                                  resetGroupBy: false);
                              // Debounced cache refresh to avoid stutter while keeping cache current
                              Sortings.scheduleCacheUpdate();
                              gallery.sort();
                              if (dropdownValue == null) {
                                dropdownValue = currentSortBy;
                              } else if (currentGroupBy != null &&
                                  sortBy.contains(dropdownValue))
                                dropdownValue = currentGroupBy!;
                            });
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 19,
              child: Scrollbar(
                thumbVisibility: true,
                trackVisibility: true,
                thickness: 15,
                interactive: true,
                controller: gallery.galleryController,
                child: PhotoViewGallery(
                  onPageChanged: (_) => setState(() {}),
                  scrollPhysics: const BouncingScrollPhysics(),
                  pageOptions: gallery.images,
                  pageController: gallery.galleryController,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  showRetry() {
    return Operation.displayRetry();
  }
}
