import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:fluttertoast/fluttertoast.dart';
import 'package:image/image.dart' as crop_image;
import 'package:image_crop/image_crop.dart';
import 'package:image_size_getter/file_input.dart';
import 'package:image_size_getter/image_size_getter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:progress_dialog/progress_dialog.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:photo_view/photo_view.dart';
import 'package:file_utils/file_utils.dart';

void main() {
  runApp(MyApp());
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

  void _incrementCounter() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
  }

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
      body: SingleChildScrollView(
        child: Center(
          // Center is a layout widget. It takes a single child and positions it
          // in the middle of the parent.
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  RaisedButton(
                    onPressed: move,
                    child: Text("Move"),
                  ),
                ],
              ),
              if (images.isNotEmpty) Container(
                height: 500,
                child: PhotoViewGallery(
                  scrollPhysics: const BouncingScrollPhysics(),
                  pageOptions: images,
                  pageController:PageController(viewportFraction: 1.1),
                ),
              ),Container(
                child: Center(
                  child: Column(
                    children: [
                      DecoratedBox(
                        decoration: const BoxDecoration( color: Colors.white),
                        child: Checkbox(
                          value: selected.contains("Test") ,
                          onChanged: (bool newVal){
                            setState(() {
                              selected.contains("Test") ? selected.remove(
                                  "Test") : selected.add("Test");
                            });
                          },
                          activeColor: Colors.amber,
                          checkColor: Colors.cyanAccent,
                        ),
                      ),
                      RaisedButton(
                        child: Text("Move"),
                        // Toggle check
                        onPressed: () => setState(() {
                          // selected.contains("Test") ? selected.remove("Test") : selected.add("Test");

                        }),
                      ),
                    ],
                  ),
                ),
              ),
              // if (images.isNotEmpty) PhotoViewGallery.builder(
              //   builder: (BuildContext context, int index) {
              //     return PhotoViewGalleryPageOptions(
              //       imageProvider: FileImage(File(images[index])),
              //       initialScale: PhotoViewComputedScale.contained * 0.8,
              //       minScale: PhotoViewComputedScale.contained * 0.8,
              //       maxScale: PhotoViewComputedScale.covered * 1.1,
              //       // heroAttributes: HeroAttributes(tag: galleryItems[index].id),
              //     );
              //   },
              //   itemCount: images.length,
              //   loadingBuilder: (context, _progress) => Center(
              //     child: Container(
              //       width: 20.0,
              //       height: 20.0,
              //       child: CircularProgressIndicator(
              //         value: _progress == null
              //             ? null
              //             : _progress.cumulativeBytesLoaded /
              //             _progress.expectedTotalBytes,
              //       ),
              //     ),
              //   ),
              // ),
            ],
          ),
        ),
      ),
      persistentFooterButtons: [
        GestureDetector(
          onTap: () => pick(),
          onLongPress: () => changeDir() ,
          child: FloatingActionButton(
            // tooltip: 'Get Text',
            child: Icon(Icons.add_to_photos_rounded),
          ),
        ),
      ],
    );
  }

  // Select picture(s) and run through OCR
  Future pick() async{
    List<PlatformFile> _paths;
    bool _multiPick = true;
    FileType _pickingType = FileType.image;


    // If directory path isn't set, have `changeDir` handle picking the files
    if(_directoryPath == null || _directoryPath.length < 1) {
      await changeDir();
      print("After changeDir");
      return;
    }

    // Select file(s)
    _paths = (await FilePicker.platform.pickFiles(
            type: _pickingType,
            allowMultiple: _multiPick,
            onFileLoading: (status) async {
              if (status == FilePickerStatus.picking) {
                print("inside picking");
                await _pr.show();
              }
              if (status == FilePickerStatus.done) {
                print("inside DONE");
                // await _pr.hide();
              }
            }))
        ?.files;

    print("file path = " + _paths[0].path);
    // _pr.show();
    images = [];
    int length = _paths.length;
    int i = 0;
    _pr.update(progress: 0);
    selected.clear();
    for(PlatformFile f in _paths) {
      String real_path =  _directoryPath+"/"+f.name;
      print("Real directory: " + real_path);
      if(File(real_path).existsSync()) {
        /*
         *Get text from image
         */
        // Load original file details
        File file = File(f.path);
        Directory parent = file.parent;
        // Load file to crop and resize
        Stopwatch intervals = new Stopwatch(), timer = new Stopwatch();
        timer.start();
        intervals.start();

        List<int> bytes = file.readAsBytesSync();
        debugPrint("byteRead: ${intervals.elapsedMilliseconds}ms | ${timer.elapsedMilliseconds}ms");

        intervals.reset();
        crop_image.Image image = crop_image.decodeImage(bytes);
        debugPrint("decode: ${intervals.elapsedMilliseconds}ms | ${timer.elapsedMilliseconds}ms");

        intervals.reset();
        final size = ImageSizeGetter.getSize(FileInput(file));
        debugPrint("getSize: ${intervals.elapsedMilliseconds}ms | ${timer.elapsedMilliseconds}ms");

        int originX = 0, originY = min(size.height, (2.5 * MediaQuery.of(context).size.height).toInt() ),
            width = size.width,
            height = min(size.height, (1.5*MediaQuery.of(context).size.height).toInt() );
        debugPrint("screenH: ${MediaQuery.of(context).size.height.toInt()}");
        debugPrint("y: $originY, height: $height");
        debugPrint("x: $originX, width: $width");
        crop_image.Image croppedFile = crop_image.copyCrop(image, originX, originY, width, height);
        croppedFile = crop_image.copyResize(croppedFile, height: height~/3 );

        // Save temp image
        intervals.reset();
        File temp_cropped = File('${parent.path}/temp-${f.name}');
        temp_cropped.writeAsBytesSync(crop_image.encodeNamedImage(croppedFile, f.path));
        debugPrint("save: ${intervals.elapsedMilliseconds}ms | ${timer.elapsedMilliseconds}ms");
        ////////////////////////////////////////////////////////////////////////
        // final size = ImageSizeGetter.getSize(FileInput(file));
        // double originX = 0, originY = 0,
        //     width = MediaQuery.of(context).size.width.toInt().toDouble(),
        //     height = min(size.height, 2 * MediaQuery.of(context).size.height.toInt() ).toDouble();
        // debugPrint("originX, originY, width, height = " + originX.toString() + ", " + originY.toString() + ", " +  width.toString() + ", " +  height.toString());
        //
        // final sampledFile = await ImageCrop.sampleImage(
        //   file: file,
        //   preferredWidth: width.toInt(),
        //   preferredHeight: height.toInt(),
        // );
        // final size2 = ImageSizeGetter.getSize(FileInput(sampledFile));
        // debugPrint("size2.height = " + size2.height.toString());
        // final croppedFile = await ImageCrop.cropImage(
        //   file: sampledFile,
        //   area: Rect.fromLTWH(originX, originY, size2.width.toDouble(), MediaQuery.of(context).size.height/2),
        // );
        // debugPrint("cropped path = " + croppedFile.path );
        ////////////////////////////////////////////////////////////////////////
        // ImageProperties properties = await FlutterNativeImage.getImageProperties(f.path);
        // int originX = 0, originY = 0,
        //     width = MediaQuery.of(context).size.width.toInt(),
        //     height = min(properties.height, 2 * MediaQuery.of(context).size.height.toInt() );
        // File croppedFile = await FlutterNativeImage.cropImage(f.path, originX, originY, width, height);
        // debugPrint("cropped path = " + croppedFile.path );

        // Run OCR
        intervals.reset();
        String text = (await OCR(temp_cropped.path));
        debugPrint("OCR: ${intervals.elapsedMilliseconds}ms | ${timer.elapsedMilliseconds}ms");

        // Search pick for keyword in pic
        intervals.reset();
        String result = search(key, text);
        debugPrint("search time: ${intervals.elapsedMilliseconds}ms | ${timer.elapsedMilliseconds}ms");

        timer.stop();
        intervals.stop();
        debugPrint("Elasped: ${timer.elapsedMilliseconds}ms");
        if (result != null) {
          images.add(PhotoViewGalleryPageOptions.customChild(
            child: Container(
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Photo
                    Container(
                      height: 450,
                      width: 200,
                      child: PhotoView(
                        imageProvider: FileImage(temp_cropped),
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
                                    value: selected.contains(f.name),
                                    onChanged: (bool newVal){
                                      print(newVal);
                                      setState(() {
                                        selected.contains(f.name) ? selected.remove(
                                            f.name) : selected.add(f.name);

                                        print("setState: file - " + f.name);
                                        print("files status: " + selected.contains(f.name).toString());
                                      });
                                    },
                                    activeColor: Colors.amber,
                                    checkColor: Colors.cyanAccent,
                                  ),
                                  RaisedButton(
                                    child: Text("Select"),
                                    // Toggle check
                                    // onPressed: () => setState(() {
                                    //   selected.contains(f.name) ? selected.remove(
                                    //       f.name) : selected.add(f.name);
                                    //   print("files status: " + selected.contains(f.name).toString());
                                    //
                                    // }),
                                    onPressed: () {
                                        selected.contains(f.name) ? selected.remove(
                                            f.name) : selected.add(f.name);
                                        _showToast(selected.contains(f.name));
                                    },
                                  ),
                                  Text(
                                    f.name,
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
                                  RaisedButton(
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
            // heroAttributes: const HeroAttributes(tag: "tag1"),
          ));
        }
      }

      // Increase progress bar
      int update = ++i*100~/length;
      print("Increasing... " + update.toString());
      _pr.update(maxProgress: 100.0, progress: update/1.0);

    }
    await _pr.hide();
    setState(() {});

  }

  // bool setVal(String file){
  //
  //   print("file: " + file);
  //   selected.contains(file) ? selected.remove(file) : selected.add(file);
  //
  //   print("files status: " + selected.contains(file).toString());
  //
  //   return selected.contains(file);
  // }

  Future changeDir() async{

    // To get path and default to this location for file pick
    _directoryPath =  await FilePicker.platform.getDirectoryPath();

    await pick();
  }

  void select(String path){

  }

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

  Future OCR(String path) async {
    return await FlutterTesseractOcr.extractText(path, language: 'eng');
  }

  String search(List<String> keys, String text){
    // TODO: Change so tha it finds the next word in the series, not the row
    text = text.toLowerCase();
    // text = text.replaceAll(new RegExp('[-+.^:,|!]'),'');
    // text = text.replaceAll(new RegExp('[^A-Za-z0-9]'),'');
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
