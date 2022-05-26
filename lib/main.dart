import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:PhotoWordFind/gallery/gallery.dart';
import 'package:PhotoWordFind/utils/files_utils.dart';
import 'package:PhotoWordFind/utils/image_utils.dart';
import 'package:PhotoWordFind/utils/toast_utils.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:image/image.dart' as crop_image;
import 'package:image_size_getter/file_input.dart';
import 'package:image_size_getter/image_size_getter.dart';
import 'package:isolate_handler/isolate_handler.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:progress_dialog/progress_dialog.dart';
// import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:photo_view/photo_view.dart';
import 'package:device_apps/device_apps.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

import 'constants/constants.dart';



void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // final prefs = SharedPreferences.getInstance().then((prefs) => prefs.clear());
  runApp(MyApp());
}

Future<String> runOCR(String filePath, ui.Size size, {bool crop = true}) async {

  File temp_cropped = crop ? createCroppedImage(
      filePath, Directory.systemTemp, size) : new File(filePath);

  return OCR(temp_cropped.path);
}

List<String> getFileNameAndExtension(String f){
  List<String> split = path.basename(f).split(".");

  return split;
}

String generateKeyFromFilename(String f){
  List<String> split = getFileNameAndExtension(f);
  String key = split.first;

  return key;
}

// Runs the `find` operation in a Isolate thread
void threadFunction(Map<String, dynamic> context) {

  final messenger = HandledIsolate.initialize(context);


  // Operation that should happen when the Isolate receives a message
  messenger.listen((receivedData) async {
    if(receivedData is String) {

      final prefs = await SharedPreferences.getInstance();

      Map<String, dynamic> message = json.decode(receivedData);
      String f = message["f"];
      ui.Size size = ui.Size(
          message['width'].toDouble(),
          message['height'].toDouble()
      );

      List<String> split = getFileNameAndExtension(f);
      String key = generateKeyFromFilename(f);
      bool replacing = split.length == 3;
      
      if(replacing) {
        prefs.remove(key);
      }

      runOCR(f, size, crop: !replacing ).then((result) {
        if (result is String) {
          // Save OCR result
          prefs.setString(key, result);
          // Send back result to main thread
          messenger.send(result);
        }
      });
    }
    else{
      debugPrint("did NOT detect string...");
      messenger.send(null);
    }

  });

  // sendPortOfOldIsolate.send(receivePort.sendPort);
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  static ProgressDialog _pr;
  static ProgressDialog get pr => _pr;

  static Gallery _gallery;
  static Gallery get gallery => _gallery;

  @override
  Widget build(BuildContext context) {

    _pr = new ProgressDialog(context, type: ProgressDialogType.Download, isDismissible: false);
    _gallery = Gallery();
    return MaterialApp(
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
      home: MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<ProgressDialog>('_pr', _pr));
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
  var snapchat_icon, gallery_icon, bumble_icon, instagram_icon;

  String snapchat_uri = 'com.snapchat.android',
  gallery_uri = 'com.sec.android.gallery3d',
  bumble_uri = 'com.bumble.app',
  instagram_uri = 'com.instagram.android';


  void requestPermissions() async{
    var status = await Permission.manageExternalStorage.status;
    if(!status.isGranted){
      await Permission.manageExternalStorage.request();
    }
  }

  void initState() {
    super.initState();

    // Initalize toast for user alerts
    Toasts.initToasts(context);

    // Request storage permissions
    requestPermissions();

    // Load app images and links
    DeviceApps.getInstalledApplications(onlyAppsWithLaunchIntent: true, includeSystemApps: true).then((apps) {

      for(var app in apps){
        if(app.appName.toLowerCase().contains("instagram"))
          debugPrint("$app");
      }
    });

    MyApp._pr.style(
        message: 'Please Waiting...',
        borderRadius: 10.0,
        backgroundColor: Colors.white,
        progressWidget: CircularProgressIndicator(),
        elevation: 10.0,
        insetAnimCurve: Curves.easeInOut,
        progress: 0.0,
        maxProgress: 100.0,
        progressTextStyle: TextStyle(
            color: Colors.black, fontSize: 13.0, fontWeight: FontWeight.w400),
        messageTextStyle: TextStyle(
            color: Colors.black, fontSize: 19.0, fontWeight: FontWeight.w600)
    );


  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
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
                    onPressed: () => displaySnaps(true),
                    child: Text("Display"),
                    onLongPress: () => displaySnaps(false),
                  ),
                  ElevatedButton(
                    onPressed: gallery.selected.isNotEmpty ? move : null,
                    child: Text("Move"),
                  ),
                ],
              ),
            ),
            if (gallery.images.isNotEmpty) Expanded(
              flex: 8,
              child: Container(
                child: Scrollbar(
                  isAlwaysShown: true,
                  showTrackOnHover: true,
                  thickness: 15,
                  interactive: true,
                  controller: gallery.galleryController,
                  child: PhotoViewGallery(
                    scrollPhysics: const BouncingScrollPhysics(),
                    pageOptions: gallery.images,
                    pageController: gallery.galleryController,
                  ),
                ),
              ),
            ),
          ],
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
                FloatingActionButton(
                  backgroundColor: Colors.white,
                  onPressed: () => DeviceApps.openApp(snapchat_uri),
                  child: snapchat_icon?? FutureBuilder(
                    // Get icon
                    future: DeviceApps.getApp(snapchat_uri, true),
                    // Build icon when retrieved
                    builder: (context, snapshot) {
                      if(snapshot.connectionState == ConnectionState.done){
                        var value = snapshot.data;
                        ApplicationWithIcon app;
                        app = (value as ApplicationWithIcon);
                        snapchat_icon = Image.memory(app.icon);
                        return snapchat_icon;
                      }
                      else{
                        return CircularProgressIndicator();
                      }
                    }
                  ),
                ),
                FloatingActionButton(
                  backgroundColor: Colors.white,
                  onPressed: () => DeviceApps.openApp(gallery_uri),
                  child: gallery_icon?? FutureBuilder(
                    // Get icon
                    future: DeviceApps.getApp(gallery_uri, true),
                    // Build icon when retrieved
                    builder: (context, snapshot) {
                      if(snapshot.connectionState == ConnectionState.done){
                        var value = snapshot.data;
                        ApplicationWithIcon app;
                        app = (value as ApplicationWithIcon);
                        gallery_icon = Image.memory(app.icon);
                        return gallery_icon;
                      }
                      else{
                        return CircularProgressIndicator();
                      }
                    }
                  ),
                ),
                FloatingActionButton(
                  backgroundColor: Colors.white,
                  onPressed: () => DeviceApps.openApp(bumble_uri),
                  child: bumble_icon?? FutureBuilder(
                    // Get icon
                    future: DeviceApps.getApp(bumble_uri, true),
                    // Build icon when retrieved
                    builder: (context, snapshot) {
                      if(snapshot.connectionState == ConnectionState.done){
                        var value = snapshot.data;
                        ApplicationWithIcon app;
                        app = (value as ApplicationWithIcon);
                        bumble_icon = Image.memory(app.icon);
                        return bumble_icon;
                      }
                      else{
                        return CircularProgressIndicator();
                      }
                    }
                  ),
                ),
                FloatingActionButton(
                  // tooltip: 'Get Text',
                  onPressed: changeDir,
                  child: Icon(Icons.drive_folder_upload),
                ),
                FloatingActionButton(
                  backgroundColor: Colors.white,
                  onPressed: () => DeviceApps.openApp(instagram_uri),
                  child: instagram_icon?? FutureBuilder(
                    // Get icon
                      future: DeviceApps.getApp(instagram_uri, true),
                      // Build icon when retrieved
                      builder: (context, snapshot) {
                        if(snapshot.connectionState == ConnectionState.done){
                          var value = snapshot.data;
                          ApplicationWithIcon app;
                          app = (value as ApplicationWithIcon);
                          instagram_icon = Image.memory(app.icon);
                          return instagram_icon;
                        }
                        else{
                          return CircularProgressIndicator();
                        }
                      }
                  ),
                ),
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

        print("List:" + lst.toString());
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
      // Pop up detailing no files selected
    }
  }


  // Select picture(s) and run through OCR
  Future<List> pick(bool select) async {
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
    if(select) {

      bool _multiPick = true;
      FileType _pickingType = FileType.image;
      Stopwatch timer = new Stopwatch();
      await MyApp._pr.show();
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
      await MyApp._pr.show();
      paths = Directory(_directoryPath).listSync(recursive: false, followLinks:false);
    }


    if(paths!= null)
      if(!(paths.first is PlatformFile) && !(paths.first is FileSystemEntity)) throw("List of path is is not a PlatformFile or File");

    return paths;
  }

  /// Displays a dialog box for input to the `find` feature
  void showFindPrompt(){
    final formKey = GlobalKey<FormState>();

    Function submit = (){
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
                    onFieldSubmitted: (String) => submit(),
                  ),
                  ElevatedButton(
                    onPressed: submit,
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

    paths = Directory(_directoryPath).listSync(recursive: false, followLinks:false);


    debugPrint("paths: " + paths.toString());
    if(paths == null) {
      await MyApp._pr.hide();
      return;
    }

    Function post = (String text, query){

      // If query word has been found
      return text.toString().toLowerCase().contains(query.toLowerCase()) ? query : null;
    };

    // Remove prompt
    Navigator.pop(context);

    await ocrParallel(paths, post, MediaQuery.of(context).size, query: query);



    return;
  }


  // Displays all images with a detectable snapchat username in their bio
  Future displaySnaps(bool select) async{

    // _pr.show();

    // Choose files to extract text from
    List paths = await pick(select);

    // Returns suggested snap username or empty string
    Function post = (String text, String _){
      String result = findSnapKeyword(keys, text)?? "";

      debugPrint("ran display Post");

      return result;
    };

    if(paths == null) {
      await MyApp._pr.hide();
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

  /// ???
  void show(text){
    showDialog(context: context, builder: (BuildContext context)
    {
      return AlertDialog(
          content: Stack(
            children: <Widget>[
              Text(
                text,
                textAlign: TextAlign.center,
              )
            ],
          )
      );
    });
  }

}
