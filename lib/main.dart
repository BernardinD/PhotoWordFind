import 'dart:async';
import 'dart:io';

import 'package:PhotoWordFind/gallery/gallery.dart';
import 'package:PhotoWordFind/social_icons.dart';
import 'package:PhotoWordFind/utils/files_utils.dart';
import 'package:PhotoWordFind/utils/operations_utils.dart';
import 'package:PhotoWordFind/utils/toast_utils.dart';
import 'package:catcher/catcher.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:permission_handler/permission_handler.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:device_apps/device_apps.dart';
import 'package:path/path.dart' as path;
import 'package:sn_progress_dialog/sn_progress_dialog.dart';

import 'constants/constants.dart';



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
  static ProgressDialog _pr;

  String title;
  static ProgressDialog get pr => _pr;

  static Gallery _gallery;
  static Gallery get gallery => _gallery;
  static Function updateFrame;

  MyApp({@required this.title});


  /// Initalizes SharedPreferences [_pref] object and gives default values
  Future init(BuildContext context)async{

    if (_pr == null) {
      _pr = new ProgressDialog(context: context);
    }

    if(_gallery == null) {
      _gallery = Gallery();
    }
  }

  static showProgress({int limit=1}) async{
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
      completed: Completed(
        completedMsg: "Done!",
        closedDelay: 1000,
      ),
    );
    debugPrint("show return: $temp");
    // MyApp._pr.style(
    //     borderRadius: 10.0,
    //     progressWidget: CircularProgressIndicator(),
    //     insetAnimCurve: Curves.easeInOut,
    //     progress: 0.0,
    //     maxProgress: 100.0,
    //     progressTextStyle: TextStyle(
    //         color:  fontSize: 13.0, fontWeight: FontWeight.w400),
    //     messageTextStyle: TextStyle(
    //         color: )
    // );
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
  MyHomePage({Key key, this.title}) : super(key: key);

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;
  String _directoryPath;
  Gallery gallery = MyApp._gallery;
  var snapchat_icon, gallery_icon, bumble_icon, instagram_icon, discord_icon;

  String snapchat_uri = 'com.snapchat.android',
  gallery_uri = 'com.sec.android.gallery3d',
  bumble_uri = 'com.bumble.app',
  instagram_uri = 'com.instagram.android',
  discord_uri = 'com.discord';


  void requestPermissions() async{
    var status = await Permission.manageExternalStorage.status;
    if(!status.isGranted){
      await Permission.manageExternalStorage.request();
    }
  }

  void initState() {
    super.initState();

    MyApp.updateFrame = setState;

    snapchat_icon = SocialIcon(snapchat_uri);
    gallery_icon = SocialIcon(gallery_uri);
    bumble_icon = SocialIcon(bumble_uri);
    instagram_icon = SocialIcon(instagram_uri);
    discord_icon = SocialIcon(discord_uri);

    // Initalize toast for user alerts
    Toasts.initToasts(context);

    // Request storage permissions
    requestPermissions();

    // Load app images and links
    DeviceApps.getInstalledApplications(onlyAppsWithLaunchIntent: true, includeSystemApps: true).then((apps) {

      for(var app in apps){
        if(app.appName.toLowerCase().contains("discord"))
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
        title: Text(widget.title),
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
              if (gallery.images.isNotEmpty) Expanded(
                flex: 8,
                child: Container(
                  child: Column(
                    children: [
                      Expanded(
                        flex: 1,
                        child: Text("${gallery.galleryController.positions.isNotEmpty ?
                            gallery.galleryController.page.round()+1 :
                            gallery.galleryController.initialPage+1}"
                          "/${gallery.images.length}"),
                      ),
                      Expanded(
                        flex: 19,
                        child: Scrollbar(
                          isAlwaysShown: true,
                          showTrackOnHover: true,
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
              ),
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
                (snapchat_icon),
                (gallery_icon),
                (bumble_icon),
                FloatingActionButton(
                  heroTag: null,
                  tooltip: 'Change current directory',
                  onPressed: changeDir,
                  child: Icon(Icons.drive_folder_upload),
                ),
                (instagram_icon),
                (discord_icon),
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
      String new_dir = await FilePicker.platform.getDirectoryPath();

      if(new_dir != null) {
        var lst = gallery.selected.toList().map((x) => [(_directoryPath +"/"+ x), (new_dir +"/"+ x)] ).toList();

        debugPrint("List:" + lst.toString());
        String src, dst;
        for(List<String> pair in lst){
          src = pair[0];
          dst = pair[1];
          File(src).renameSync(dst);
        }
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
  Future<List> selectImages(bool individual) async {
    List paths;


    // If directory path isn't set, have `changeDir` handle picking the files
    if (_directoryPath == null || _directoryPath.length < 1) {
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
      await MyApp.showProgress();
      paths = (await FilePicker.platform.pickFiles(
          type: _pickingType,
          allowMultiple: _multiPick
      ))?.files;

      if(paths != null && !File(path.join(_directoryPath, paths.first.path.split("/").last)).existsSync()){
        // TODO: Show error (selected files didn't exist in directory)
        // ...

        return null;
      }
    }
    else{
      await MyApp.showProgress();
      paths = Directory(_directoryPath).listSync(recursive: false, followLinks:false);
    }


    if(paths!= null)
      if(!(paths.first is PlatformFile) && !(paths.first is FileSystemEntity)) throw("List of path is is not a PlatformFile or File");

    return paths;
  }

  /// Displays a dialog box for input to the `find` feature
  void showFindPrompt(){
    final formKey = GlobalKey<FormState>();

    Function validatePhrase = (){
      if (formKey.currentState.validate()) {
        formKey.currentState.save();
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
                    validator: (input) => input.length < 3? 'Too short. Enter more than 2 letters': null,
                    onSaved: (input) => findSnap(input.trim()),
                    onFieldSubmitted: (String) => validatePhrase(),
                  ),
                  ElevatedButton(
                    onPressed: validatePhrase,
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
  Future findSnap(String query)async{

    // Get all files from directory
    List<dynamic> paths;
    // paths = await pick();

    // If directory path isn't set, have `changeDir` handle picking the files
    if (_directoryPath == null || _directoryPath.length < 1) {
      await changeDir();
      print("After changeDir");
    }
    //
    // paths = Directory(_directoryPath).listSync(recursive: false, followLinks:false);
    //
    //
    // debugPrint("paths: " + paths.toString());
    // if(paths == null) {
    //   await MyApp._pr.close();
    //   return;
    // }
    //
    // Function post = (String text, query){
    //
    //   // If query word has been found
    //   return text.toString().toLowerCase().contains(query.toLowerCase()) ? query : null;
    // };
    //
    // // Remove prompt
    // Navigator.pop(context);
    //
    // await ocrParallel(paths, post, MediaQuery.of(context).size, query: query);

    Operation.run(Operations.FIND, findQuery: query, context: context, directoryPath: _directoryPath);



    return;
  }


  // Displays all images with a detectable snapchat username in their bio
  Future displaySnaps(bool select) async{

    // _pr.show();

    // Choose files to extract text from
    List paths = await selectImages(select);

    // Returns suggested snap username or empty string
    Function post = (String text, String _){
      String result = findSnapKeyword(keys, text)?? "";

      debugPrint("ran display Post");

      return result;
    };

    if(paths == null) {
      await MyApp._pr.close();
      return;
    }

    ocrParallel(paths, post, MediaQuery.of(context).size);

  }


  Future changeDir() async{

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

  }

  @override
  void dispose() {
    // TODO: implement dispose
    super.dispose();

    if( !Platform.environment.containsKey('FLUTTER_TEST'))
      FilePicker.platform.clearTemporaryFiles();
  }

}
