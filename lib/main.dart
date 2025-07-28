import 'dart:async';
import 'dart:io';

import 'package:PhotoWordFind/gallery/gallery.dart';
import 'package:PhotoWordFind/services/chat_gpt_service.dart';
import 'package:PhotoWordFind/social_icons.dart';
import 'package:PhotoWordFind/utils/cloud_utils.dart';
import 'package:PhotoWordFind/utils/operations_utils.dart';
import 'package:PhotoWordFind/utils/sort_utils.dart';
import 'package:PhotoWordFind/utils/toast_utils.dart';
import 'package:PhotoWordFind/widgets/confirmation_dialog.dart';
import 'package:PhotoWordFind/widgets/settings_screen.dart';
import 'package:catcher/catcher.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:permission_handler/permission_handler.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:device_apps/device_apps.dart';
import 'package:path/path.dart' as path;
import 'package:sn_progress_dialog/sn_progress_dialog.dart';

// import 'package:image_picker/image_picker.dart';

void main() {
  ChatGPTService.initialize();

  CatcherOptions debugOptions =
      CatcherOptions(PageReportMode(), [ConsoleHandler()]);
  CatcherOptions releaseOptions = CatcherOptions(PageReportMode(), [
    EmailManualHandler(["bdezius@gmail.com"],
        emailTitle: "Photo Word Find - Crashed", emailHeader: "Error message")
  ]);

  Catcher(
      rootWidget: MyApp(title: 'Flutter Demo Home Page'),
      debugConfig: debugOptions,
      releaseConfig: releaseOptions,
      ensureInitialized: true);

  // final prefs = SharedPreferences.getInstance().then((prefs) => prefs.clear());
  // runApp(MyApp('Flutter Demo Home Page'));
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  static ProgressDialog? _pr;

  final String title;
  static ProgressDialog get pr => _pr!;

  static late final Gallery _gallery = Gallery();
  static Gallery get gallery => _gallery;
  static late Function updateFrame;

  MyApp({required this.title});

  /// Initalizes SharedPreferences [_pref] object and gives default values
  Future init(BuildContext context) async {
    if (_pr == null) {
      _pr = new ProgressDialog(context: context);
    }
  }

  static showProgress({required bool autoComplete, int limit = 1}) {
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
      msgColor: Colors.black, msgFontSize: 19.0, msgFontWeight: FontWeight.w600,
      // progressValueColor: Colors.black,
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: MaterialApp(
        title: 'Flutter Demo',
        theme: ThemeData(
          // This is the theme of your application.
          //
          // Try running your application with "flutter run". You'll see the
          // application has a blue toolbar. Then, without quitting the app, try
          // changing the primarySwatch below to Colors.green and then invoke
          // "hot reload" (press "r" in the console where you ran "flutter run",
          // or simply save your changes to "hot reload" in a Flutter IDE).
          // Notice that the counter didn't reset back to zero; the application
          // is not restarted.
          primarySwatch: Colors.blue,
        ),
        navigatorKey: Catcher.navigatorKey,
        home: Builder(builder: (context) {
          init(context);
          return MyHomePage(title: title);
        }),
      ),
    );
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
  late Future<bool> _isSignedInFuture;
  bool _isSyncing = false;

  // TODO: Delete after testing
  void debugPrintLargeString(String message, {int chunkSize = 1000}) {
    final pattern = RegExp('.{1,$chunkSize}', dotAll: true);
    pattern.allMatches(message).forEach((match) => debugPrint(match.group(0)));
  }

  /// Ensures user is signed in before performing operations
  Future<bool> _ensureSignedIn() async {
    bool isSignedIn = await CloudUtils.isSignedin();
    if (!isSignedIn) {
      isSignedIn = await CloudUtils.firstSignIn();
    }
    return isSignedIn;
  }

  /// Forces sync with cloud storage
  Future<void> _forceSync() async {
    if (_isSyncing) return;
    
    setState(() {
      _isSyncing = true;
    });

    try {
      // Ensure we're signed in
      bool signedIn = await _ensureSignedIn();
      if (!signedIn) {
        throw Exception("Sign-in failed");
      }

      MyApp.pr.show(max: 2);
      MyApp.pr.update(value: 0, msg: "Downloading from cloud...");
      
      // Download from cloud
      bool foundCloudData = await CloudUtils.getCloudJson();
      MyApp.pr.update(value: 1, msg: "Uploading to cloud...");
      
      // Upload current data to cloud
      await CloudUtils.updateCloudJson();
      MyApp.pr.update(value: 2, msg: "Sync complete!");
      
      Toasts.showToast(true, (_) => "Cloud sync completed successfully");
    } catch (e) {
      debugPrint("Sync error: $e");
      Toasts.showToast(false, (_) => "Sync failed: ${e.toString()}");
    } finally {
      MyApp.pr.close();
      setState(() {
        _isSyncing = false;
      });
    }
  }

  /// Toggles sign in/out status
  Future<void> _toggleSignInOut() async {
    bool isSignedIn = await CloudUtils.isSignedin();
    
    if (isSignedIn) {
      // Sign out
      bool confirmed = await showDialog(
        context: context,
        builder: (BuildContext context) {
          return ConfirmationDialog(
              message: "Are you sure you want to sign out?");
        },
      );

      if (confirmed) {
        await CloudUtils.possibleSignOut();
        setState(() {
          _isSignedInFuture = Future.value(false);
        });
      }
    } else {
      // Sign in
      bool success = await CloudUtils.firstSignIn();
      setState(() {
        _isSignedInFuture = Future.value(success);
      });
    }
  }

  Future<void> _sendToChatGPT() async {
    MyApp.pr.show(max: _images.length);

    try {
      // Get full path
      final srcList = gallery.selected.toList();
      var lst = srcList
          .map((x) => (getDirectoryPath().toString() + "/" + x))
          .toList();
      _images = lst.map((path) => File(path)).toList();

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
    MyApp.pr.close();
  }

  String? _directoryPath;
  Gallery gallery = MyApp._gallery;

  Map<Sorts?, String> sortings = Map.from({
    Sorts.SortByTitle: "Sort By",
    Sorts.Date: "Date Found",
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

  void initState() {
    super.initState();

    MyApp.updateFrame = setState;
    
    // Initialize sign-in state
    _isSignedInFuture = CloudUtils.isSignedin();

    // Initalize toast for user alerts
    Toasts.initToasts(context);

    // Request storage permissions
    requestPermissions().then((value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Sign into cloud account
        MyApp.pr.show(max: 1);
        MyApp.pr.update(value: 0, msg: "Setting up...");

        CloudUtils.firstSignIn()
            .then((bool signedIn) {
              setState(() {
                _isSignedInFuture = Future.value(signedIn);
              });
              if(!signedIn){
                throw Exception("Sign-in failed");
              }
            })
            .onError((dynamic error, stackTrace) async =>
                debugPrint("Sign in error: $error \n$stackTrace")
                    as FutureOr<Null>)
            .whenComplete(() => MyApp.pr.update(value: 1));
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

  /// Navigate to settings screen
  void _navigateToSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          currentDirectory: _directoryPath,
          onDirectoryChanged: (String? newDirectory) {
            setState(() {
              _directoryPath = newDirectory;
            });
          },
        ),
      ),
    );
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
          // Settings button
          IconButton(
            onPressed: _navigateToSettings,
            icon: Icon(Icons.settings),
            tooltip: 'Settings',
          ),
          // Sync button
          FutureBuilder<bool>(
            future: _isSignedInFuture,
            builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
              bool isSignedIn = snapshot.hasData && snapshot.data == true;
              return IconButton(
                onPressed: (isSignedIn && !_isSyncing) ? _forceSync : null,
                icon: _isSyncing 
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.sync,
                        color: isSignedIn ? null : Colors.grey,
                      ),
                tooltip: isSignedIn 
                    ? (_isSyncing ? 'Syncing...' : 'Sync with cloud') 
                    : 'Sign in to sync',
              );
            },
          ),
          // Sign in/out button
          FutureBuilder<bool>(
            future: _isSignedInFuture,
            builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
              if (snapshot.hasError) {
                return IconButton(
                  onPressed: null,
                  icon: Icon(Icons.error_outline, color: Colors.red),
                  tooltip: 'Sign-in error',
                );
              }
              
              if (!snapshot.hasData) {
                return SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                );
              }
              
              bool isSignedIn = snapshot.data == true;
              return IconButton(
                onPressed: _toggleSignInOut,
                icon: Icon(isSignedIn ? Icons.logout : Icons.login),
                tooltip: isSignedIn ? 'Sign out' : 'Sign in',
              );
            },
          ),
        ],
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
      Stopwatch timer = new Stopwatch();
      await MyApp.showProgress(autoComplete: true);
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
      await MyApp.showProgress(autoComplete: true);
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
