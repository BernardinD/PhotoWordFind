import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:PhotoWordFind/main.dart';
import 'package:PhotoWordFind/social_icons.dart';
import 'package:PhotoWordFind/utils/files_utils.dart';
import 'package:PhotoWordFind/utils/sort_utils.dart';
import 'package:PhotoWordFind/utils/storage_utils.dart';
import 'package:PhotoWordFind/utils/toast_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:photo_view/photo_view.dart';
import 'package:url_launcher/url_launcher.dart';

class GalleryCell extends StatefulWidget {
  const GalleryCell(
      this.text,
      this.snapUsername,
      this.instaUsername,
      this.f,
      this.srcImage,
      this.list_pos,
      this.onPressedHandler,
      this.onLongPressedHandler,
      {@required ValueKey<String> key})
      : super(key: key);

  final String text;
  final String snapUsername;
  final String instaUsername;
  final dynamic f;
  final File srcImage;
  final int Function(GalleryCell cell) list_pos;
  final void Function(String file_name) onPressedHandler;
  final void Function(String file_name) onLongPressedHandler;
  String get storageKey => getKeyOfFilename(srcImage.path);

  @override
  _GalleryCellState createState() => _GalleryCellState();
}

class _GalleryCellState extends State<GalleryCell> {
  GlobalKey cropBoxKey;
  Key cellKey;
  String file_name;
  var _photo;

  @override
  void initState() {
    // TODO: implement initState
    super.initState();

    // Used for controlling when to take screenshot
    cropBoxKey = new GlobalKey();
    file_name = widget.f.path.split("/").last;
    cellKey = ValueKey(file_name);
    _photo = PhotoView(
      imageProvider: FileImage(widget.srcImage),
      initialScale: PhotoViewComputedScale.covered,
      minScale: PhotoViewComputedScale.contained * 0.4,
      maxScale: PhotoViewComputedScale.covered * 1.5,
      basePosition: Alignment.topCenter,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: cellKey,
      width: MediaQuery.of(context).size.width * 0.95,
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
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
                    child: Text(
                      "REDO",
                      style: TextStyle(color: Colors.white),
                    ),
                    onPressed: redo,
                  ),
                ),
                Expanded(
                  flex: 9,
                    child: Container(
                      child: _photo,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Analysis
        Expanded(
          flex: 1,
          child: Container(
            child: Center(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Spacer(),
                  Expanded(
                      flex: 1,
                      child: ElevatedButton(
                        child: Text("Select"),
                        onPressed: () => widget.onPressedHandler(file_name),
                        onLongPress: () =>
                            widget.onLongPressedHandler(file_name),
                      )),

                  Spacer(),

                  // Snap suggestion
                  Expanded(
                    flex: 2,
                    child: Container(
                      child: Table(
                        defaultVerticalAlignment:
                            TableCellVerticalAlignment.middle,
                        columnWidths: {
                          0: FlexColumnWidth(1),
                          1: IntrinsicColumnWidth(flex: 2),
                          2: FlexColumnWidth(2),
                        },
                        children: [
                          getSocialRow((widget.snapUsername.isNotEmpty &&
                              SocialIcon.snapchatIconButton != null), SocialType.Snapchat),
                          getSocialRow((widget.instaUsername.isNotEmpty &&
                              SocialIcon.instagramIconButton != null), SocialType.Instagram),
                        ],
                      ),
                    ),
                  ),

                  Spacer(
                    flex: 1,
                  ),

                  // Entire OCR
                  Expanded(
                    flex: 3,
                    child: Container(
                        color: Colors.white,
                        child: SelectableText(
                          widget.text.toString(),
                          showCursor: true,
                          contextMenuBuilder: (context, editableTextState) {
                            final TextEditingValue value =
                                editableTextState.textEditingValue;
                            final List<ContextMenuButtonItem> buttonItems =
                                editableTextState.contextMenuButtonItems;
                            buttonItems.insert(
                                0,
                                ContextMenuButtonItem(
                                  label: 'Select snap',
                                  onPressed: () {
                                    ContextMenuController.removeAny();
                                    String snap = value.selection.textInside(value.text);
                                    StorageUtils.save(widget.storageKey, backup: true, snap: snap, overridingUsername: false);
                                    MyApp.gallery.redoCell(widget.text, snap, widget.instaUsername, widget.list_pos(widget));
                                    Sortings.updateCache();
                                    MyApp.updateFrame(() => null);
                                  },
                                ));
                            return AdaptiveTextSelectionToolbar.buttonItems(
                              anchors: editableTextState.contextMenuAnchors,
                              buttonItems: buttonItems,
                            );
                          },
                        )),
                  ),
                  Spacer(
                    flex: 2,
                  )
                ],
              ),
            ),
          ),
        ),
      ]),
    );
  }

  void showRedoWindow(){
    showDialog(context: context, builder: (BuildContext context)
    {
      return AlertDialog(
        content: ClipRect(
          child: RepaintBoundary(
            key: cropBoxKey,
            child: Container(
              child: _photo,
            ),
          ),
        ),
      );
    });
  }

  void redo() async {
    dynamic srcImage = widget.f;
    // Grab QR code image (ref: https://stackoverflow.com/questions/63312348/how-can-i-save-a-qrimage-in-flutter)
    RenderRepaintBoundary boundary =
        cropBoxKey.currentContext.findRenderObject();
    var image = await boundary.toImage();
    ByteData byteData = await image.toByteData(format: ImageByteFormat.png);
    Uint8List pngBytes = byteData.buffer.asUint8List();

    // Create file location for image
    final tempDir = Directory.systemTemp;
    print("tempDir = ${tempDir.path}");
    final file =
        await new File('${tempDir.path}/${file_name.split(".").first}.repl.png')
            .create()
            .catchError((e) {
      print("file creation failed.");
      print(e);
    });

    // Save image locally
    await file.writeAsBytes(pngBytes).catchError((e) {
      print("file writing failed.");
      print(e);
    });
    print("image file exists: " + (await file.exists()).toString());
    print("image file path: " + (await file.path));

    // Run OCR
    ocrParallel([file], MediaQuery.of(context).size,
        replace: {widget.list_pos(widget): srcImage.path})
        .then((value) => setState(() {}));
  }

  unAddUser(bool snap) async {
    Toasts.showToast(true, (_) => "Marked as unadded");
    if (snap)
      await StorageUtils.save(widget.storageKey, backup: true, snapAdded: false, snapAddedDate: null);
    else
      await StorageUtils.save(widget.storageKey, backup: true, instaAdded: false, instaAddedDate: null);
    MyApp.updateFrame(() => null);
  }

  openUserAppPage(bool snap) async {
    await MyApp.showProgress();
    String key = widget.storageKey;
    Uri _site;
    if (snap) {
      _site =  Uri.parse("https://www.snapchat.com/add/${widget.snapUsername.toLowerCase()}");
      await StorageUtils.save(key, backup: true, snapAdded: true, snapAddedDate: DateTime.now());
    } else {
      _site = Uri.parse("https://www.instagram.com/${widget.instaUsername}");
      await StorageUtils.save(key, backup: true, instaAdded: true, instaAddedDate: DateTime.now());
    }
    debugPrint("site URI: $_site");
    await Sortings.updateCache();
    launchUrl(_site, mode: LaunchMode.externalApplication)
        .then((value) => MyApp.pr.close(delay: 500));
  }

  TableRow getSocialRow(bool hasUser, SocialType social) {

    String action = "Open in  ${social == SocialType.Snapchat ? 'snapchat' : 'instagram'}";
    bool app = social == SocialType.Snapchat;
    String username = social == SocialType.Snapchat ? widget.snapUsername : widget.instaUsername;

    if (hasUser) {
      return TableRow(
        children: [
          TableCell(child: social.icon),
          TableCell(
              // verticalAlignment: TableCellVerticalAlignment.middle,
              child: Center(
            child: SelectableText(
              username,
              style: TextStyle(color: Colors.redAccent, fontSize: 10),
              showCursor: true,
              maxLines: 1,
              contextMenuBuilder: overrideContextMenuButton
            ),
          )),
          FutureBuilder(
            future: social.isAdded(widget.storageKey),
            builder: (context, snapshot) {
              if (snapshot.hasError){
                return TableCell(
                  child: ElevatedButton(
                    onPressed: null,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red
                    ),
                    child: Text(
                        "Errored", maxLines: 2, style: TextStyle(fontSize: 8)),
                  ),
                );
              } else {
                bool socialAdded = snapshot.connectionState == ConnectionState.done && snapshot.data;
                if(socialAdded){
                  action = "Mark as Unadded";
                }
                return TableCell(
                  key: ValueKey(socialAdded),
                  child: ElevatedButton(
                    onPressed: () => !socialAdded ? openUserAppPage(app) : unAddUser(app),
                    child: Text(
                        action, maxLines: 2, style: TextStyle(fontSize: 8)),
                  ),
                );
              }/* else{
                return CircularProgressIndicator();
              }*/
            },
          ),
        ],
      );
    }
    else{
      return TableRow(
        children: [
          TableCell(child: social.icon),
          TableCell(
            // verticalAlignment: TableCellVerticalAlignment.middle,
              child: Center(
                child: SelectableText(
                  "[None]",
                  style: TextStyle(color: Colors.redAccent, fontSize: 10),
                  showCursor: true,
                  maxLines: 1,
                  contextMenuBuilder: overrideContextMenuButton
                ),
              )),
          TableCell(
            child: ElevatedButton(
              onPressed: null,
              child: Text(action, maxLines: 2, style: TextStyle(fontSize: 8)),
            ),
          ),
        ],
      );
    }
  }

  AlertDialog _updateUsernameDialog(SocialType social, String username){
    final formKey = GlobalKey<FormState>();
    void Function(String foo) validatePhrase = (_){
      if (formKey.currentState.validate()) {
        formKey.currentState.save();
      }
    };

    return AlertDialog(
      content: SingleChildScrollView(
        child: Center(
          child: Form(
            key: formKey,
            child: Column(
              children: [
                Container(
                  child: Table(
                    columnWidths: {
                      0: FlexColumnWidth(1),
                      1: IntrinsicColumnWidth(flex: 3),
                    },
                    children: [
                      TableRow(
                          children: [
                            TableCell(child: social.icon),
                            TableCell(
                              child: TextFormField(
                                initialValue: username,
                                textAlign: TextAlign.center,
                                validator: (value) => value.isNotEmpty ? null :  "Must input value first",
                                onSaved: (value) => Navigator.pop(context, value),
                                onFieldSubmitted:  validatePhrase,
                              )
                            ),
                          ]
                      ),
                    ],
                  ),
                ),
                ElevatedButton(onPressed: () => validatePhrase(null), child: Text("Save"))
              ],
            ),
          ),
        ),
      ),
    );
  }

  TableRow _manualUpdatingUserRows(SocialType social){
    final _controller = TextEditingController();
    return TableRow(
        children: [
          TableCell(child: social.icon),
          TableCell(child: StreamBuilder(stream: social.getUserName(widget.storageKey).asStream(), builder: (BuildContext context,AsyncSnapshot snapshot) {
            if (snapshot.connectionState == ConnectionState.done && !snapshot.hasError) {
              String username = snapshot.data;
              _controller.text = username;
              return TextField(controller: _controller, readOnly: true);
            } else {
              return Center(
                child: CircularProgressIndicator(),
              );
            }
          },), ),
          TableCell(
              child: IconButton(
                icon: Icon(Icons.edit_note_rounded),
                onPressed: () async {
                  String newValue = await showDialog(context: context, builder: (BuildContext context) {
                    return _updateUsernameDialog(social, _controller.text);
                  });

                  if (newValue != null) {
                    _controller.text = newValue;
                    await social.saveUsername(widget.storageKey, newValue, overriding: true);
                    String snap = widget.snapUsername, insta = widget.instaUsername;
                    switch(social){
                      case SocialType.Snapchat:
                        snap = newValue;
                        break;
                      case SocialType.Instagram:
                        insta = newValue;
                        break;
                    }
                    MyApp.gallery
                        .redoCell(widget.text, snap, insta, widget.list_pos(widget));
                    Sortings.updateCache();
                  }
          },
              )
          )
        ],
    );
  }

  _manuallyUpdateUsername(){
    showDialog(context: context, builder: (BuildContext context)
    {
      return AlertDialog(
        content: SingleChildScrollView(
          child: Table(
            defaultVerticalAlignment:
            TableCellVerticalAlignment.middle,
            columnWidths: {
              0: FlexColumnWidth(1),
              1: FlexColumnWidth(4),
              2: FlexColumnWidth(1),
            },
            children: [
              _manualUpdatingUserRows(SocialType.Snapchat),
              _manualUpdatingUserRows(SocialType.Instagram),
              _manualUpdatingUserRows(SocialType.Discord),
            ],
          ),
        )
      );
    });
  }

  Widget overrideContextMenuButton(context, editableTextState) {
    final List<ContextMenuButtonItem> buttonItems = editableTextState.contextMenuButtonItems;
    buttonItems.insert(
        0,
        ContextMenuButtonItem(
          label: 'Override username',
          onPressed: () {
            ContextMenuController.removeAny();
            _manuallyUpdateUsername();
          },
        ));
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: buttonItems,
    );
  }
}

