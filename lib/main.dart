import 'dart:async';
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


void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp());
}


// Extracts text from image
Future<String> OCR(String path) async {
  debugPrint("path: $path");

  final inputImage = InputImage.fromFilePath(path);
  final textDetector = GoogleMlKit.vision.textDetector();
  final RecognisedText recognisedText = await textDetector.processImage(inputImage);
  return recognisedText.text;
  // return await FlutterTesseractOcr.extractText(path, language: 'eng');
}

// Scans in file as the Image object with adjustable features
crop_image.Image getImage(dynamic f){

  List<int> bytes = File(f.path).readAsBytesSync();
  return crop_image.decodeImage(bytes);

}

// Crops image (ideally in the section of the image that has the bio)
crop_image.Image crop(crop_image.Image image, f, ui.Size screenSize){

  Size size = ImageSizeGetter.getSize(FileInput(File(f.path)));

  int originX = 0, originY = min(size.height, (2.5 * screenSize.height).toInt() ),
      width = size.width,
      height = min(size.height, (1.5 * screenSize.height).toInt() );
  debugPrint("screenH: ${screenSize.height.toInt()}");
  debugPrint("y: $originY, height: $height");
  debugPrint("x: $originX, width: $width");


  return crop_image.copyCrop(image, originX, originY, width, height);
}

/// Creates a cropped and resized image by passing the file and the `parent` directory to save the temporary image
File createCroppedImage(dynamic f, Directory parent, ui.Size size){

  crop_image.Image image = getImage(f);

  // Separate the cropping and resize opperations so that the thread memory isn't used up
  crop_image.Image croppedFile = crop(image, f, size);
  croppedFile = crop_image.copyResize(croppedFile, height: croppedFile.height~/3 );

  // Save temp image
  String file_name = f.path.split("/").last;
  File temp_cropped = File('${parent.path}/temp-${file_name}');
  temp_cropped.writeAsBytesSync(crop_image.encodeNamedImage(croppedFile, f.path));

  return temp_cropped;
}

Future<String> find(dynamic f, String name, ui.Size size) async {

  // debugPrint("tesseertact path: ${(await getApplicationDocumentsDirectory())}");
  debugPrint("screen size(in find): ${size}");
  File temp_cropped = createCroppedImage(
      f, Directory.systemTemp, size);



  return OCR(temp_cropped.path);
}

// Runs the `find` operation in a Isolate thread
void threadFunction(Map<String, dynamic> context) {
  debugPrint("came in.");

  final messenger = HandledIsolate.initialize(context);


  // Operation that should happen when the Isolate receives a message
  messenger.listen((message) async {
    if(message is testy) {

      dynamic f = message.f;
      String name = message.name;
      ui.Size size = message.screenSize;
      debugPrint("parsed messages");

      find(f, name, size).then((result) {
        if (result is String) {

          // Send back result to main thread
          messenger.send(result);
        }
      });
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
  FToast fToast;

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

    // Initalize toast for user alerts
    fToast = FToast();
    fToast.init(context);
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
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
                    onPressed: () => displaySnaps(false),
                    child: Text("Display"),
                    onLongPress: () => displaySnaps(true),
                  ),
                  ElevatedButton(
                    onPressed: move,
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
          child: FloatingActionButton(
            // tooltip: 'Get Text',
            child: Icon(Icons.drive_folder_upload),
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
                                      onPressed: () {
                                        selected.contains(file_name) ? selected.remove(
                                            file_name) : selected.add(file_name);
                                        _showToast(selected.contains(file_name));
                                      },
                                    ),
                                    Text(
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
                                      title: Text(result, style: TextStyle(color: Colors.redAccent),),
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
    bool _multiPick = true;
    FileType _pickingType = FileType.image;


    // If directory path isn't set, have `changeDir` handle picking the files
    if (_directoryPath == null || _directoryPath.length < 1) {
      await changeDir();
      print("After changeDir");
    }

    // Select file(s)
    if(select) {
      paths = (await FilePicker.platform.pickFiles(
          type: _pickingType,
          allowMultiple: _multiPick,
          onFileLoading: (status) async {
            if (status == FilePickerStatus.picking) {
              print("inside picking");
              await _pr.show();
            }
            if (status == FilePickerStatus.done) {
              print("inside DONE");
              await _pr.hide();
            }
          }))
          ?.files;
    }
    else{
      await _pr.show();
      paths = Directory(_directoryPath).listSync(recursive: false, followLinks:false);
    }

    // sleep(Duration(seconds: 2));
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
                    onSaved: (input) => findSnap(input),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      debugPrint("button pressed.");
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
  Future findSnap(String name)async{

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

    await _pr.show();




    /////////////// Testing Isolates //////////////////
    // // List<Isolate> isolates = [];
    // final isolates = IsolateHandler();
    // int completed = 0;
    // for(var f in paths) {
    //   debugPrint("create sub-thread");
    //
    //   testy test = new testy(
    //       f,
    //       name,
    //       MediaQuery.of(context).size);
    //     // Start up the thread and configures the callbacks
    //     isolates.spawn<testy>(threadFunction, name: f.path.split("/").last,onInitialized: () => isolates.send(test, to: f.path.split("/").last), onReceive: (dynamic signal) {
    //     print('Data from new isolate : $signal');
    //
    //     // Return port for sending message to thread
    //     // if (signal is SendPort) {
    //     //   SendPort sendPortOfNewIsolate = signal;
    //     //   sendPortOfNewIsolate.send(test);
    //     // }
    //     // Retrieve result of search
    //     // else if(signal is String){
    //     if(signal is String){
    //       String text = signal;
    //       debugPrint("text: " + text.toString());
    //
    //       if(text.toString().toLowerCase().contains(name.toLowerCase())) {
    //         images.add(newGalleryCell(text, name, f, new File(f.path)));
    //
    //         // Stop creation of new isolates
    //         paths.clear();
    //
    //         // Terminate running isolates
    //         isolates.isolates.clear();
    //         // receivePort.sendPort.send(true);
    //
    //         // Set the counter to the end to force closing dialogs
    //         completed = paths.length;
    //       }
    //
    //       // Close dialogs once finished with all images
    //       if(completed++ >= paths.length){
    //         _pr.hide().then((value) => Navigator.pop(context));
    //       }
    //
    //     }
    //     // // Terminate all running threads
    //     // else if(signal is bool && signal){
    //     //   //Kill new Isolate
    //     //   isolate.kill(priority: Isolate.immediate);
    //     //   isolate=null;
    //     // }
    //     // Else throw error
    //     else{
    //       debugPrint("------- ERROR >> receivePort Listener ------");
    //     }
    //
    //   });
    //
    //   // Save isolate so that it isn't deleted
    //   // isolates.add(isolate);
    // }

    // // Testing await for-each
    // Future.forEach(paths, (f) async{
    //   find(f, name, ).then((value) {
    //       _pr.hide().then((value) => Navigator.pop(context));;
    // });

    //////// Original ///////////////
    for(var f in paths) {
      // await Future.forEach(paths, (f) async{
      File file = new File(f.path);
      Stopwatch intervals = new Stopwatch(),
          timer = new Stopwatch();
      intervals.start();
      timer.start();
      File temp_cropped = createCroppedImage(f, Directory.systemTemp, MediaQuery.of(context).size);
      String text = (await OCR(temp_cropped.path));
      debugPrint("text: " + text.toString());

      if (text.toString().toLowerCase().contains(name.toLowerCase())) {
        images.add(newGalleryCell(text, name, f, new File(f.path)));
        // break;
      }
      // });
    }
    await _pr.hide();
    debugPrint("here.");
    Navigator.pop(context);

    return;
  }

  // Future<bool> find(dynamic f, String name) async{
  //
  //   File file = new File(f.path);
  //   Stopwatch intervals = new Stopwatch(),
  //       timer = new Stopwatch();
  //   intervals.start();
  //   timer.start();
  //   File temp_cropped = createCroppedImage(
  //       file, f, Directory.systemTemp, intervals, timer, size);
  //
  //   return OCR(temp_cropped.path).then((text) {
  //     debugPrint("text: " + text.toString());
  //
  //     if (text.toString().toLowerCase().contains(name.toLowerCase())) {
  //       images.add(newGalleryCell(text, name, f, new File(f.path)));
  //
  //       // Break search progress
  //       _pr.hide().then((bool) {
  //         debugPrint("here.");
  //         Navigator.pop(context);
  //       });
  //
  //       return true;
  //     }
  //
  //     return false;
  //   });
  // }


  // Displays all images with a detectable snapchat username in their bio
  Future displaySnaps(bool select) async{

    // Choose files to extract text from
    List paths = await pick(select);
    if(paths == null) {
      _pr.hide();
      return;
    }

    print("file path = " + paths[0].path);
    // _pr.show();
    images = [];
    int length = paths.length;
    int i = 0;
    _pr.update(progress: 0);
    selected.clear();

    // Run the files through OCR process
    for(var f in paths) {
      if(!(f is PlatformFile) && !(f is FileSystemEntity)) throw("$f is not a PlatformFile or File");

      String real_path =  _directoryPath+"/"+f.path.split("/").last;
      print("Real directory: " + real_path);
      if(File(real_path).existsSync()) {
        /*
         *Get text from image
         */
        // Load original file details
        File file = File(f.path);
        Directory parent = file.parent,
          cache_dir = Directory.systemTemp;
        // Load file to crop and resize
        Stopwatch intervals = new Stopwatch(), timer = new Stopwatch();
        timer.start();
        intervals.start();

        File temp_cropped = createCroppedImage(f, cache_dir, MediaQuery.of(context).size);

        // Run OCR
        intervals.reset();
        String text = (await OCR(temp_cropped.path));
        debugPrint("OCR: ${intervals.elapsedMilliseconds}ms | ${timer.elapsedMilliseconds}ms");

        // Search pick for keyword in pic
        intervals.reset();
        String result = findSnapKeyword(key, text)?? "";
        debugPrint("search time: ${intervals.elapsedMilliseconds}ms | ${timer.elapsedMilliseconds}ms");

        timer.stop();
        intervals.stop();
        debugPrint("Elasped: ${timer.elapsedMilliseconds}ms");

        // Add new Cell to gallery
        images.add(newGalleryCell(text, result, f, new File(f.path)));
      }

      // Increase progress bar
      int update = ++i*100~/length;
      print("Increasing... " + update.toString());
      _pr.update(maxProgress: 100.0, progress: update/1.0);

    }
    await _pr.hide();
    setState(() {});

  }

  Future changeDir() async{

    // To get path and default to this location for file pick
    _directoryPath =  await FilePicker.platform.getDirectoryPath();
  }

  void select(String path){

  }

  /// Moves the selected files to a new chosen Directory
  void move() async{
    // Move selected images to new directory
    if(selected.isNotEmpty) {
      // Choose new directory
      String new_dir = await FilePicker.platform.getDirectoryPath();

      if(new_dir != null) {
        var lst = selected.toList().map((x) => _directoryPath +"/"+ x).toList();
        print("List:" + lst.toString());
        // FileUtils.move(selected.toList(), new_dir);

        selected.clear();
      }
    }
    else{
      // Pop up detailing no files selected
    }
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
        if(keys.contains(word.replaceAll(new RegExp('[^A-Za-z0-9]'),'').trim())) return words[++i].trim();
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

  /// Displays a Toast of the `selection` state of the current visible Cell in the gallery
  void _showToast(bool selected){

    // Make sure last toast has eneded
    fToast.removeCustomToast();

    Widget toast = Container(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25.0),
        color: selected ? Colors.greenAccent : Colors.grey,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          selected ? Icon(Icons.check) : Icon(Icons.not_interested_outlined),
          SizedBox(
            width: 12.0,
          ),
          Text(selected ? "Selected." : "Unselected."),
        ],
      ),
    );


    fToast.showToast(
      child: toast,
      gravity: ToastGravity.BOTTOM,
      toastDuration: Duration(seconds: 1),
    );
  }
}

/// Experimental class for passing data message into Isolate
class testy{

  File f;
  String name;
  ui.Size screenSize;

  testy(
  f,
  name, size){
    this.f = f;
    this.name = name;
    this.screenSize = size;
  }
}
