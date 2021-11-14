import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

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

  runApp(MyApp());
}


// Extracts text from image
Future<String> OCR(String path) async {

  final inputImage = InputImage.fromFilePath(path);
  final textDetector = GoogleMlKit.vision.textDetector();
  final RecognisedText recognisedText = await textDetector.processImage(inputImage);
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

Future<String> runOCR(String filePath, ui.Size size) async {

  File temp_cropped = createCroppedImage(
      filePath, Directory.systemTemp, size);



  return OCR(temp_cropped.path);
}

// Runs the `find` operation in a Isolate thread
void threadFunction(Map<String, dynamic> context) {

  final messenger = HandledIsolate.initialize(context);


  // Operation that should happen when the Isolate receives a message
  messenger.listen((receivedData) async {
    if(receivedData is String) {

      final prefs = await SharedPreferences.getInstance();

      Map<String, dynamic> message = json.decode(receivedData);
      dynamic f = message["f"];
      ui.Size size = ui.Size(message['width'].toDouble(), message['height'].toDouble());

      if(prefs.getString(f) != null){
        String result = prefs.getString(f);
        messenger.send(result);
      }
      else {
        runOCR(f, size).then((result) {
          if (result is String) {
            // Save OCR result
            prefs.setString(f, result);
            // Send back result to main thread
            messenger.send(result);
          }
        });
      }
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
  var icon;

  void initState() {
    super.initState();

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
              flex: 9,
              child: SingleChildScrollView(
                child: Container(
                  height: MediaQuery.of(context).size.height,
                  child: PhotoViewGallery(
                    scrollPhysics: const BouncingScrollPhysics(),
                    pageOptions: images,
                    pageController:PageController(viewportFraction: 1.1),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      persistentFooterButtons: [
        GestureDetector(
          onTap: changeDir,
          child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              FloatingActionButton(
                onPressed: () => DeviceApps.openApp('com.snapchat.android'),
                child: icon?? FutureBuilder(
                  // Get icon
                  future: DeviceApps.getApp('com.snapchat.android', true),
                  // Build icon when retrieved
                  builder: (context, snapshot) {
                    if(snapshot.connectionState == ConnectionState.done){
                      var value = snapshot.data;
                      ApplicationWithIcon app;
                      app = (value as ApplicationWithIcon);
                      icon = Image.memory(app.icon);
                      return icon;
                    }
                    else{
                      return CircularProgressIndicator();
                    }
                  }
                ),
              ),
              FloatingActionButton(
                // tooltip: 'Get Text',
                child: Icon(Icons.drive_folder_upload),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Creates standardized Widget that will seen in gallery
  PhotoViewGalleryPageOptions newGalleryCell(String text, String result, dynamic f, File image){
    String file_name = f.path.split("/").last;
    return PhotoViewGalleryPageOptions.customChild(
      child: Container(
        child: Column(
          children: [
            Expanded(
              flex: 6,
              child: Container(
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Photo
                      Container(
                        height: 450,
                        width: 200,
                        child: PhotoView(
                          imageProvider: FileImage(image),
                          initialScale: PhotoViewComputedScale.contained,
                          minScale: PhotoViewComputedScale.contained *
                              (0.5 + images.length / 10),
                          maxScale: PhotoViewComputedScale.covered * 4.1,
                        ),
                      ),
                      // Options
                      Container(
                        child: Center(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Selecting image
                              Container(
                                child: Column(
                                  children: [
                                    Checkbox(
                                      value: selected.contains(file_name),
                                      onChanged: (bool newVal){
                                        print(newVal);
                                        setState(() {
                                          selected.contains(file_name) ? selected.remove(
                                              file_name) : selected.add(file_name);

                                          print("setState: file - " + file_name);
                                          print("files status: " + selected.contains(file_name).toString());
                                        });
                                      },
                                      activeColor: Colors.amber,
                                      checkColor: Colors.cyanAccent,
                                    ),
                                    ElevatedButton(
                                      child: Text("Select"),
                                      // onPressed: () => move(file_name),
                                    ),
                                    SelectableText(
                                      file_name,
                                      style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 7),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                width: MediaQuery.of(context).size.width/2,
                                child: Column(
                                  children: [
                                    // Snap name
                                    ListTile(
                                      // leading: Text("Found:"),
                                      title: SelectableText(result, style: TextStyle(color: Colors.redAccent),),
                                    ),
                                    // Copy button
                                    ElevatedButton(
                                        // Add to clipboard if not already there
                                      // ...
                                    ),

                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ]),
              ),
            ),
            Expanded(
              flex: 4,
              child: Container(
                  height: 100,
                  color: Colors.white,
                  child: SelectableText(
                    text.toString(),
                    showCursor: true,

                  )
              ),
            ),
          ],
        ),
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

  Future ocrParallel(List paths, Function post, {String query, bool findFirst = false}) async{

    await _pr.show();

    // Reset Gallery
    images= [];

    // Time search
    Stopwatch time_elasped = new Stopwatch();

    _pr.update(progress: 0);

    final isolates = IsolateHandler();
    int completed = 0;
    int path_idx = 0;
    time_elasped.start();
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

      // Start up the thread and configures the callbacks
      debugPrint("spawning new iso....");
      isolates.spawn<String>(
          threadFunction,
          name: iso_name,
          onInitialized: () => isolates.send(rawJson, to: iso_name),
          onReceive: (dynamic signal) {
            if(signal is String){
              String text = signal;
              // If query word has been found
              String result = post(text, query);
              if(result != null) {

                images.add(newGalleryCell(text, result, f, new File(f.path)));

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
          });

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
