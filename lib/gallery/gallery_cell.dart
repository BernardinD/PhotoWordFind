
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:PhotoWordFind/constants/constants.dart';
import 'package:PhotoWordFind/utils/files_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:photo_view/photo_view.dart';

class GalleryCell extends StatefulWidget {
  const GalleryCell(String this.text, String this.suggestedUsername, dynamic this.f, File this.src_image, this.list_pos, this.onPressedHandler, this.onLongPressedHandler, {@required ValueKey<String> key}) : super(key: key);

  final String text;
  final String suggestedUsername;
  final dynamic f;
  final File src_image;
  final int Function(GalleryCell cell) list_pos;
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

    return Container(
      key: ValueKey(file_name),
      width: MediaQuery.of(context).size.width * 0.95,
      child: Row(
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
                        onPressed: () => redo(file_name, widget.f),
                      ),
                    ),
                    Expanded(
                      flex : 9,
                      child: ClipRect(
                        child: RepaintBoundary(
                          key: globalKey,
                          child: Container(
                            child: PhotoView(
                              imageProvider: FileImage(widget.src_image),
                              initialScale: PhotoViewComputedScale.covered,
                              minScale: PhotoViewComputedScale.contained * 0.4,
                              maxScale: PhotoViewComputedScale.covered * 1.5,
                              basePosition: Alignment.topCenter,
                            ),
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
                            title: SelectableText(widget.suggestedUsername, style: TextStyle(color: Colors.redAccent),),
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
                              widget.text.toString(),
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
          ]),
    );
  }

  void redo(String file_name, dynamic src_image) async{
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
    ocrParallel([file], post, MediaQuery.of(context).size, replace: {widget.list_pos(widget) : src_image.path}).then((value) => setState((){}));
  }

}