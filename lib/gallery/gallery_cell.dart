
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:PhotoWordFind/constants/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:photo_view/photo_view.dart';

class GalleryCell extends StatefulWidget {
  const GalleryCell(File this.image, int this.list_pos, dynamic this.f, this.onPressedHandler, this.onLongPressedHandler, {Key key}) : super(key: key);

  final File image;
  final int list_pos;
  final dynamic f;
  final void Function(String file_name) onPressedHandler;
  final void Function(String file_name) onLongPressedHandler;

  @override
  _GalleryCellState createState() => _GalleryCellState();
}

class _GalleryCellState extends State<GalleryCell>{

  GlobalKey globalKey;
  String file_name;

  @override
  Widget build(BuildContext context) {

    // Used for controlling when to take screenshot
    globalKey = new GlobalKey();

    file_name = widget.f.path.split("/").last;

    return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Photo
          Expanded(
            flex: 1,
            child: Container(
              height: 450,
              child: Column(
                children: [
                  Expanded(
                    flex: 1,
                    child: ElevatedButton(
                      child: Text("REDO", style: TextStyle(color: Colors.white),),
                      onPressed: () => redo(file_name, f),
                    ),
                  ),
                  Expanded(
                    flex : 9,
                    child: RepaintBoundary(
                      key: globalKey,
                      child: Container(
                        child: PhotoView(
                          imageProvider: FileImage(widget.image),
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
                    Spacer(

                    ),
                    Expanded(
                        child: ElevatedButton(
                          child: Text("Select"),
                          onPressed: () => widget.onPressedHandler(file_name),
                          onLongPress: () => widget.onLongPressedHandler(file_name),
                        )
                    ),
                    Spacer(

                    ),

                    // Snap suggestion
                    Expanded(
                      flex: 1,
                      child: Container(
                        child: ListTile(
                          title: SelectableText(suggestedUsername, style: TextStyle(color: Colors.redAccent),),
                        ),
                      ),
                    ),

                    Spacer(

                    ),

                    // Entire OCR
                    Expanded(
                      flex: 3,
                      child: Container(
                          color: Colors.white,
                          child: SelectableText(
                            text.toString(),
                            showCursor: true,
                          )
                      ),
                    ),
                    Spacer(

                    )
                  ],
                ),
              ),
            ),
          ),
        ]);
  }

  void redo(String file_name, dynamic f) async{
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


    // Run OCR
    // Returns suggested snap username or empty string
    Function post = (String text, String _){
      String result = findSnapKeyword(keys, text)?? "";

      debugPrint("ran display Post");

      return result;
    };
    ocrParallel([new File(file.path)], post, replace: f.path).then((value) => setState((){}));
  }

}