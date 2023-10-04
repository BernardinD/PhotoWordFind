import 'dart:async';
import 'dart:io';

import 'package:PhotoWordFind/gallery/gallery.dart';
import 'package:PhotoWordFind/social_icons.dart';
import 'package:PhotoWordFind/utils/cloud_utils.dart';
import 'package:PhotoWordFind/utils/operations_utils.dart';
import 'package:PhotoWordFind/utils/sort_utils.dart';
import 'package:PhotoWordFind/utils/toast_utils.dart';
import 'package:catcher/catcher.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:permission_handler/permission_handler.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:device_apps/device_apps.dart';
import 'package:path/path.dart' as path;
import 'package:sn_progress_dialog/sn_progress_dialog.dart';



void main() {
  WidgetsFlutterBinding.ensureInitialized();

  CatcherOptions debugOptions = CatcherOptions(PageReportMode(), [ConsoleHandler()]);
  CatcherOptions releaseOptions = CatcherOptions(PageReportMode(), [
    EmailManualHandler(["bdezius@gmail.com"], emailTitle: "Photo Word Find - Crashed", emailHeader: "Error message")
  ]);

  Catcher(rootWidget: MyApp(title: 'Flutter Demo Home Page'), debugConfig: debugOptions, releaseConfig: releaseOptions);

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
  Future init(BuildContext context)async{

    if (_pr == null) {
      _pr = new ProgressDialog(context: context);
    }

  }

  static showProgress({required bool autoComplete, int limit=1}) {
    debugPrint("Entering showProgress()...");
    if(pr.isOpen()){
      debugPrint("Closing.");
      pr.close();
    }
    else{
      debugPrint("Not open.");
      pr.update(value: 0);
    }

    debugPrint("limit: $limit");
    var temp =  pr.show(
      msg: 'Please Waiting...',
      max: limit,
      backgroundColor: Colors.white,
      elevation: 10.0,
      msgColor: Colors.black, msgFontSize: 19.0, msgFontWeight: FontWeight.w600,
      // progressValueColor: Colors.black,
      completed: autoComplete ? Completed(
        completedMsg: "Done!",
        completionDelay: 1000,
      ) : null,
    );
    debugPrint("show return: $temp");
    debugPrint("Leaving showProgress()...");
  }

  @override
  Widget build(BuildContext context) {


    return WillPopScope(
      onWillPop: () async => false,
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
        home: Builder(
          builder: (context) {
            init(context);
            return MyHomePage(title: title);
          }
        ),
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
  String? _directoryPath;
  Gallery gallery = MyApp._gallery;

  Map<Sorts?, String> sortings = Map.from({
    Sorts.SortByTitle: "Sort By",
    Sorts.Date: "Date Found",
    Sorts.DateAddedOnSnap: "Date Added on Snap",
    Sorts.DateAddedOnInsta: "Date Added on Instagram",
    Sorts.SnapDetected : "Snap Handle",
    Sorts.InstaDetected : "Instagram Handle",
    Sorts.DiscordDetected : "Discord Handle",
    Sorts.GroupByTitle: "Group By",
    null: "None", // Disable GroupBy
    Sorts.AddedOnSnap: "Snap Added",
    Sorts.AddedOnInsta: "Insta Added"
  });
  Sorts? dropdownValue = Sorts.Date;


  String? get directoryPath => _directoryPath;
  String? getDirectoryPath(){
    return directoryPath;
  }



  Future requestPermissions() async{
    var status = await Permission.manageExternalStorage.status;
    if(!status.isGranted){
      await Permission.manageExternalStorage.request();
    }
  }

  void initState() {
    super.initState();

    MyApp.updateFrame = setState;

    // Initalize toast for user alerts
    Toasts.initToasts(context);


    // Request storage permissions
    requestPermissions().then((value) {

      WidgetsBinding.instance
          .addPostFrameCallback((_) {
        // Sign into cloud account
        MyApp.pr.show(max: 1);
        MyApp.pr.update(value: 0, msg: "Setting up...");

        CloudUtils.firstSignIn().then((bool value) {}).
        onError((dynamic error, stackTrace) async => debugPrint("Sign in error: $error \n$stackTrace") as FutureOr<Null>).
        whenComplete(() => MyApp.pr.update(value: 1));

      });
    });

    // Load app images and links
    DeviceApps.getInstalledApplications(onlyAppsWithLaunchIntent: true, includeSystemApps: true).then((apps) {

      for(var app in apps){
        if(app.appName.toLowerCase().contains("kik"))
          debugPrint("$app");
      }
    });


  }

  @override
  Widget build(BuildContext context) {


    return Scaffold(
      resizeToAvoidBottomInset : false,
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title!),
        leading: FutureBuilder(
          future: CloudUtils.isSignedin(),
          builder: (BuildContext context, AsyncSnapshot<bool> snapshot){
            if(snapshot.hasError) throw Exception(snapshot.error);
            if(!snapshot.hasData){
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
                    onPressed: () => CloudUtils.firstSignIn().then((value) => MyApp.updateFrame(() => null)),
                  )
                : ElevatedButton(
                    key: ValueKey(snapshot.data.toString()),
                    onPressed: () => CloudUtils.possibleSignOut().then((value) => MyApp.updateFrame(() => null)),
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
              if (gallery.images.isNotEmpty) showGallery() else if(Operation.isRetryOp()) showRetry(),
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
    );
  }

  void move() async{
    // Move selected images to new directory
    if(gallery.selected.isNotEmpty) {
      // Choose new directory
      String? newDir = await FilePicker.platform.getDirectoryPath();

      if(newDir != null) {

        Operation.run(Operations.MOVE, null, moveSrcList: gallery.selected.toList(), moveDesDir: newDir, directoryPath: getDirectoryPath);

        setState(() {
          gallery.removeSelected();
        });
      }
    }
    else{
      throw Exception("There are no selected files to move");
    }

  }


  // Select picture(s) and run through OCR
  Future<List?> selectImages(bool individual) async {
    late List? paths;


    // If directory path isn't set, have `changeDir` handle picking the files
    if (_directoryPath == null || _directoryPath!.length < 1) {
      await changeDir();
      if(_directoryPath == null){
        // TODO: Show error message "Must select a Directory"
        // ...

        return null;
      }
      print("After changeDir");
    }

    // Select file(s)
    if(individual) {

      bool _multiPick = true;
      FileType _pickingType = FileType.image;
      Stopwatch timer = new Stopwatch();
      await MyApp.showProgress(autoComplete: true);
      paths = (await FilePicker.platform.pickFiles(
          type: _pickingType,
          allowMultiple: _multiPick
      ))?.files;

      if(paths != null && !File(path.join(_directoryPath!, paths.first.path.split("/").last)).existsSync()){
        // TODO: Show error (selected files didn't exist in directory)
        // ...

        return null;
      }
    }
    else{
      await MyApp.showProgress(autoComplete: true);
      paths = Directory(_directoryPath!).listSync(recursive: false, followLinks:false);
    }


    // Assure that list is of right file type
    if(paths!= null && paths.isNotEmpty) {
      if (!(paths.first is PlatformFile) && !(paths.first is FileSystemEntity))
        throw ("List of path is is not a PlatformFile or File");
    }

    return paths;
  }

  /// Displays a dialog box for input to the `find` feature
  void showFindPrompt(){
    final formKey = GlobalKey<FormState>();

    Function validatePhrase = (_){
      if (formKey.currentState!.validate()) {
        formKey.currentState!.save();
      }
    };
    showDialog(context: context, builder: (BuildContext context)
    {
      return AlertDialog(
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                children: <Widget>[
                  TextFormField(
                    autofocus: true,
                    decoration: InputDecoration(
                        labelText: "Input name"
                    ),
                    // TODO: Make validation failure message dynamic
                    validator: (input) => input!.length < 3? 'Too short. Enter more than 2 letters': null,
                    onSaved: findSnap,
                    onFieldSubmitted:  validatePhrase as void Function(String)?,
                  ),
                  ElevatedButton(
                    onPressed: () => validatePhrase(null),
                    child: Text('Find'),
                  ),
                ],
              ),
            ),
          )
      );
    });
  }

  /// Looks for the snap name in the directory
  Future findSnap(String? query)async{
    query = query!.trim();

    // If directory path isn't set, have `changeDir` handle picking the files
    if (_directoryPath == null || _directoryPath!.length < 1) {
      await changeDir();
      print("After changeDir");
    }
    Operation.run(Operations.FIND, changeDir, findQuery: query, context: context, directoryPath: getDirectoryPath);



    return;
  }


  // Displays all images with a detectable snapchat username in their bio
  Future
  displaySnaps(bool select) async{
    debugPrint("Entering displaySnaps()...");

    Operations op = select ? Operations.DISPLAY_SELECT : Operations.DISPLAY_ALL;

    // _pr.show();

    // Choose files to extract text from
    List? paths = await selectImages(select);

    Operation.run(op, changeDir, displayImagesList: paths, context: context);

    debugPrint("Leaving displaySnaps()...");
  }


  Future changeDir() async{
    debugPrint("Entering changeDir()...");

    // Reset callback function
    try {
      await FilePicker.platform.pickFiles(
          type: FileType.image,
          onFileLoading: (_) => debugPrint(""), allowedExtensions: ["fail"]);
    }
    catch (e){debugPrint("changeDir >> $e");}
        // To get path and default to this location for file pick
    // sleep(Duration(seconds:1));
    _directoryPath =  await FilePicker.platform.getDirectoryPath();

    debugPrint("Leaving changeDir()...");
  }

  @override
  void dispose() {
    // TODO: implement dispose
    super.dispose();

    if( !Platform.environment.containsKey('FLUTTER_TEST'))
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
                  SizedBox(width: MediaQuery.of(context).size.width/3,),
                  VerticalDivider(width: 1.0),
                  SizedBox(
                    width: MediaQuery.of(context).size.width/3,
                    child: Center(
                      child: Text("${gallery.galleryController.positions.isNotEmpty ?
                      gallery.galleryController.page.round()+1 :
                      gallery.galleryController.initialPage+1}"
                          "/${gallery.images.length}"),
                    ),
                  ),
                  VerticalDivider(width: 1.0),
                  Center(
                    child: SizedBox(
                      width: MediaQuery.of(context).size.width/3-2,
                      child: FittedBox(
                        child: DropdownButton<String>(
                          value: sortings[dropdownValue],
                          alignment: AlignmentDirectional.topEnd,
                          items: sortings.entries.map<DropdownMenuItem<String>>((MapEntry<Sorts?, String> entry) {
                            if (sortsTitles.contains(entry.key) ) {
                              return DropdownMenuItem(
                                enabled: false,
                                  child: Column(
                                    children: [
                                      // Divider(),
                                      Text(entry.value),
                                      Divider(),
                                    ],
                                  )
                              );
                            }
                            else {
                              return DropdownMenuItem<String>(
                                value: entry.value,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(entry.value),
                                    if(dropdownValue == entry.key || (entry.key == currentSortBy && dropdownValue == currentGroupBy) )
                                      groupBy.contains(entry.key) ?
                                        Icon(Sortings.reverseGroupBy  ? Icons.arrow_back : Icons.arrow_forward) :
                                        Icon(Sortings.reverseSortBy ? Icons.arrow_back : Icons.arrow_forward),
                                  ],
                                ),
                              );
                            }
                          }).toList(),
                          onChanged: (String? value) {
                            // This is called when the user selects an item.
                            setState(() {
                              dropdownValue = sortings.entries.firstWhere((entry) => entry.value == value).key;
                              Sortings.updateSortType(dropdownValue, resetGroupBy: false);
                              gallery.sort();
                              if(dropdownValue == null){
                                dropdownValue = currentSortBy;
                              }
                              else if(currentGroupBy != null && sortBy.contains(dropdownValue) )
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
