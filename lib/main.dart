import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:image/image.dart' as crop_image;
import 'package:image_size_getter/file_input.dart';
import 'package:image_size_getter/image_size_getter.dart';
import 'package:isolate_handler/isolate_handler.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:progress_dialog/progress_dialog.dart';
// import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:photo_view/photo_view.dart';
import 'package:device_apps/device_apps.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';



void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // final prefs = SharedPreferences.getInstance().then((prefs) => prefs.clear());
  runApp(MyApp()); 
}


// Extracts text from image
Future<String> OCR(String path) async {

  final inputImage = InputImage.fromFilePath(path);
  final textDetector = GoogleMlKit.vision.textDetector();
  final RecognisedText recognisedText = await textDetector.processImage(inputImage);
  textDetector.close();
  return recognisedText.text;
  // return await FlutterTesseractOcr.extractText(path, language: 'eng');
}

// Scans in file as the Image object with adjustable features
crop_image.Image getImage(String filePath){

  List<int> bytes = File(filePath).readAsBytesSync();
  return crop_image.decodeImage(bytes);

}

// Crops image (ideally in the section of the image that has the bio)
crop_image.Image crop(crop_image.Image image, String filePath, ui.Size screenSize){

  Size size = ImageSizeGetter.getSize(FileInput(File(filePath)));

  int originX = 0, originY = min(size.height, (2.5 * screenSize.height).toInt() ),
      width = size.width,
      height = min(size.height, (1.5 * screenSize.height).toInt() );


  return crop_image.copyCrop(image, originX, originY, width, height);
}

/// Creates a cropped and resized image by passing the file and the `parent` directory to save the temporary image
File createCroppedImage(String filePath, Directory parent, ui.Size size){

  crop_image.Image image = getImage(filePath);

  // Separate the cropping and resize opperations so that the thread memory isn't used up
  crop_image.Image croppedFile = crop(image, filePath, size);
  croppedFile = crop_image.copyResize(croppedFile, height: croppedFile.height~/3 );

  // Save temp image
  String file_name = filePath.split("/").last;
  File temp_cropped = File('${parent.path}/temp-${file_name}');
  temp_cropped.writeAsBytesSync(crop_image.encodeNamedImage(croppedFile, filePath));

  return temp_cropped;
}

Future<String> runOCR(String filePath, ui.Size size, {bool crop = true}) async {

  File temp_cropped = crop ? createCroppedImage(
      filePath, Directory.systemTemp, size) : new File(filePath);



  return OCR(temp_cropped.path);
}

List<String> splitFileNameByDots(String f){
  List<String> split = f.split("/").last.split(".");

  return split;
}

String filenameToKey(String f){
  List<String> split = splitFileNameByDots(f);
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
      ui.Size size = ui.Size(message['width'].toDouble(), message['height'].toDouble());

      List<String> split = splitFileNameByDots(f);
      String key = filenameToKey(f);
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
  @override
  Widget build(BuildContext context) {
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
    static ProgressDialog _pr;
  List<String> key = ["sc", "snap", "snapchat"];
  List<PhotoViewGalleryPageOptions> images = [];
  String _directoryPath;
  Set selected;
  var snapchat_icon, gallery_icon, bumble_icon, instagram_icon;

  String snapchat_uri = 'com.snapchat.android',
  gallery_uri = 'com.sec.android.gallery3d',
  bumble_uri = 'com.bumble.app',
  instagram_uri = 'com.instagram.android';

  var galleryController = new PageController(initialPage: 0, keepPage: false, viewportFraction: 1.0);



  void initState() {
    super.initState();

    DeviceApps.getInstalledApplications(onlyAppsWithLaunchIntent: true, includeSystemApps: true).then((apps) {

      for(var app in apps){
        if(app.appName.toLowerCase().contains("instagram"))
          debugPrint("$app");
      }
    });

    _pr = new ProgressDialog(context, type: ProgressDialogType.Download, isDismissible: false);
    _pr.style(
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

    // Initalize indicator for selected photos
    selected = new Set();

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
                    // onPressed: move,
                    child: Text("Move"),
                  ),
                ],
              ),
            ),
            if (images.isNotEmpty) Expanded(
              flex: 8,
              child: Container(
                child: Scrollbar(
                  isAlwaysShown: true,
                  showTrackOnHover: true,
                  thickness: 35,
                  interactive: true,
                  controller: galleryController,
                  child: PhotoViewGallery(
                    scrollPhysics: const BouncingScrollPhysics(),
                    pageOptions: images,
                    pageController: galleryController,
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

  // Creates standardized Widget that will seen in gallery
  PhotoViewGalleryPageOptions newGalleryCell(String text, String suggestion, dynamic f, File image, {int position}){
    String file_name = f.path.split("/").last;
    int list_pos = position?? images.length;

    // Used for controlling when to take screenshot
    GlobalKey globalKey = new GlobalKey();

    return PhotoViewGalleryPageOptions.customChild(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.95,
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Photo
              Expanded(
                flex: 1,
                child: Container(
                  height: 450,
                  // width: 200,
                  child: Column(
                    children: [
                      Expanded(
                        flex: 1,
                        child: ElevatedButton(
                          child: Text("test", style: TextStyle(color: Colors.white),),
                          onPressed: () async{
                            // return null;
                            // Grab QR code image (ref: https://stackoverflow.com/questions/63312348/how-can-i-save-a-qrimage-in-flutter)
                            RenderRepaintBoundary boundary = globalKey.currentContext.findRenderObject();
                            var image = await boundary.toImage();
                            ByteData byteData = await image.toByteData(format: ImageByteFormat.png);
                            Uint8List pngBytes = byteData.buffer.asUint8List();

                            // Create file location for image
                            final tempDir = Directory.systemTemp;
                            print("tempDir = ${tempDir.path}");
                            final file = await new File('${tempDir.path}/${file_name.split(".").first}.repl.png').create().catchError((e){
                              print("file creation failed.");
                              print(e);
                            });

                            // Save image locally
                            await file.writeAsBytes(pngBytes).catchError((e){
                              print("file writing failed.");
                              print(e);
                            });
                            print("image file exists: " + (await file.exists()).toString());
                            print("image file path: " + (await file.path));

                            /*
                             * [Testing]
                             */
                            // Add image to gallery
                            // setState(() {
                            //   // images[list_pos] = newGalleryCell(text, "result", file, new File(file.path), position: list_pos);
                            // });

                            // Run OCR
                            // Returns suggested snap username or empty string
                            Function post = (String text, String _){
                              String result = findSnapKeyword(key, text)?? "";

                              debugPrint("ran display Post");

                              return result;
                            };
                            ocrParallel([new File(file.path)], post, replace: {list_pos : f.path}).then((value) => setState((){}));
                          },
                        ),
                      ),
                      Expanded(
                        flex : 9,
                        child: RepaintBoundary(
                          key: globalKey,
                          child: Container(
                            child: PhotoView(
                              imageProvider: FileImage(image),
                              initialScale: PhotoViewComputedScale.contained,
                              minScale: PhotoViewComputedScale.contained *
                                  (0.5 + images.length / 10),
                              maxScale: PhotoViewComputedScale.covered * 4.1,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Analysis
              Expanded(
                flex : 1,
                child: Container(
                  child: Center(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Filename
                        Container(
                          width: MediaQuery.of(context).size.width/2,
                          child: ListTile(
                            title: SelectableText(
                              file_name,
                              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 7),
                            ),
                          ),
                        ),
                        // Snap suggestion
                        Container(
                          width: MediaQuery.of(context).size.width/2,
                          child: ListTile(
                            title: SelectableText(suggestion, style: TextStyle(color: Colors.redAccent),),
                          ),
                        ),
                        // Entire OCR
                        Container(
                            height: MediaQuery.of(context).size.height * 0.25,
                            color: Colors.white,
                            child: SelectableText(
                              text.toString(),
                              showCursor: true,
                            )
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ]),
      ),
      // heroAttributes: const HeroAttributes(tag: "tag1"),
    );
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
      await _pr.show();
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
      await _pr.show();
      paths = Directory(_directoryPath).listSync(recursive: false, followLinks:false);
    }


    if(paths!= null)
      if(!(paths.first is PlatformFile) && !(paths.first is FileSystemEntity)) throw("List of path is is not a PlatformFile or File");

    return paths;
  }

  /// Displays a dialog box for input to the `find` feature
  void showFindPrompt(){
    final formKey = GlobalKey<FormState>();
    showDialog(context: context, builder: (BuildContext context)
    {
      return AlertDialog(
          content: Container(
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
                  ),
                  ElevatedButton(
                    onPressed: () {
                      if (formKey.currentState.validate()) {
                        formKey.currentState.save();
                      }
                    },
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
      await _pr.hide();
      return;
    }

    Function post = (String text, query){

      // If query word has been found
      return text.toString().toLowerCase().contains(query.toLowerCase()) ? query : null;
    };

    // Remove prompt
    Navigator.pop(context);

    await ocrParallel(paths, post, query: query);



    return;
  }


  // Displays all images with a detectable snapchat username in their bio
  Future displaySnaps(bool select) async{

    // _pr.show();

    // Choose files to extract text from
    List paths = await pick(select);

    // Returns suggested snap username or empty string
    Function post = (String text, String _){
      String result = findSnapKeyword(key, text)?? "";

      debugPrint("ran display Post");

      return result;
    };

    if(paths == null) {
      await _pr.hide();
      return;
    }

    ocrParallel(paths, post);

  }

  Future ocrParallel(List paths, Function post, {String query, bool findFirst = false, Map<int, String> replace}) async{

    _pr.update(progress: 0);
    await _pr.show();

    // Reset Gallery
    if(replace == null) {
      if(images.length > 0)
        galleryController.jumpToPage(0);
      images.clear();
    }

    // Time search
    Stopwatch time_elasped = new Stopwatch();


    final isolates = IsolateHandler();
    int completed = 0;
    int path_idx = 0;
    time_elasped.start();
    final prefs = await SharedPreferences.getInstance();

    for(path_idx = 0; path_idx < paths.length; path_idx++){


      // Prepare data to be sent to thread
      var f = paths[path_idx];
      var size = MediaQuery.of(context).size;
      Map<String, dynamic> message = {
        "f": f.path,
        "height": size.height,
        "width" : size.width
      };
      String rawJson = jsonEncode(message);
      final Map<String, dynamic> data = json.decode(rawJson);
      String iso_name = f.path.split("/").last;

      // Define callback
      Function onReceive = (dynamic signal) {
        if(signal is String){
          String text = signal;
          // If query word has been found
          String result = post(text, query);
          if(result != null) {

            if(replace == null)
              images.add(newGalleryCell(text, result, f, new File(f.path)));
            else{
              var pair = replace.entries.first;
              int idx = pair.key;
              String file = pair.value;
              debugPrint("f.path: ${f.path}");
              debugPrint("file path: $file");
              images[idx] = newGalleryCell(text, result, f, new File(file), position: idx);
            }

            debugPrint("Elasped: ${time_elasped.elapsedMilliseconds}ms");

            // Stop creation of new isolates and to close dialogs
            if(findFirst) {
              path_idx = paths.length;
              completed = paths.length;
            }
          }

        }
        else{
          // Dispose of finished isolate
          isolates.kill(iso_name);
        }

        debugPrint("before `completed`... $completed <= ${paths.length}");
        debugPrint("before `path_idx`... $path_idx <= ${paths.length}");


        // Increase progress bar
        int update = (completed+1)*100~/paths.length;
        update = update.clamp(0, 100);
        print("Increasing... " + update.toString());
        _pr.update(maxProgress: 100.0, progress: update/1.0);

        // Close dialogs once finished with all images
        if(++completed >= paths.length){
          // Terminate running isolates
          List names = isolates.isolates.keys.toList();
          for(String name in names){
            // Don't kill current thread
            if(name == iso_name) continue;

            debugPrint("iso-name: ${name}");
            if(isolates.isolates[name].messenger.connectionEstablished ) {
              try {
                isolates.kill(name);
              }
              catch(e){
                debugPrint("pass kill error");
              }
            }
          }
          debugPrint("popping...");

          // Quick fix for this callback being called twice
          // TODO: Find way to stop isolates immediately so they don't get to this point
          if(_pr.isShowing())
            _pr.hide().then((value) {
              setState(() => {});
            });
        }
      };

      List<String> split = splitFileNameByDots(f.path);
      String key = filenameToKey(f.path);
      bool replacing = split.length == 3;

      if(replacing) {
        prefs.remove(key);
      }

      if(prefs.getString(key) != null){
        String result = prefs.getString(key);
        onReceive(result);
      }
      else {
        // Start up the thread and configures the callbacks
        debugPrint("spawning new iso....");
        isolates.spawn<String>(
            threadFunction,
            name: iso_name,
            onInitialized: () => isolates.send(rawJson, to: iso_name),
            onReceive: (dynamic signal) => onReceive(signal));
      }

    }
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

  /// Searches for the occurance of a keyword meaning there is a snapchat username and returns a suggestion for the user name
  String findSnapKeyword(List<String> keys, String text){
    // TODO: Change so tha it finds the next word in the series, not the row
    text = text.toLowerCase();
    // text = text.replaceAll(new RegExp('[-+.^:,|!]'),'');
    // text = text.replaceAll(new RegExp('[^A-Za-z0-9]'),'');
    // Remove all non-alphanumeric characters
    debugPrint("text: " + text.replaceAll(new RegExp('[^A-Za-z0-9]'),''));

    // Split up lines
    for(String line in text.split("\n")){
      // Split up words
      int i = 0;
      List<String> words= line.split(" ");
      for(String word in words){
        // word;
        if(keys.contains(word.replaceAll(new RegExp('[^A-Za-z0-9]'),'').trim())) return (i+1 < words.length) ? words[++i].trim() : "";
        i++;
      }
    }
    return null;
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
