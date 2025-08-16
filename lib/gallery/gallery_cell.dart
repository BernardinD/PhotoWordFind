import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:PhotoWordFind/constants/constants.dart';
import 'package:PhotoWordFind/gallery/display_dates.dart';
import 'package:PhotoWordFind/main.dart';
import 'package:PhotoWordFind/models/contactEntry.dart';
import 'package:PhotoWordFind/social_icons.dart';
import 'package:PhotoWordFind/utils/files_utils.dart';
import 'package:PhotoWordFind/utils/sort_utils.dart';
import 'package:PhotoWordFind/utils/storage_utils.dart';
import 'package:PhotoWordFind/utils/toast_utils.dart';
import 'package:PhotoWordFind/widgets/confirmation_dialog.dart';
import 'package:PhotoWordFind/widgets/note_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:url_launcher/url_launcher.dart';

class GalleryCell extends StatefulWidget {
  const GalleryCell(
      this.text,
      this.snapUsername,
      this.instaUsername,
      this.discordUsername,
      this.f,
      this.srcImage,
      this.listPos,
      this.onPressedHandler,
      this.onLongPressedHandler,
      this.contact,
      {required ValueKey<String> key})
      : super(key: key);

  final List<Map<String, String>> text;
  final String snapUsername;
  final String instaUsername;
  final String discordUsername;
  final dynamic f;
  final File srcImage;
  final ContactEntry? contact;
  final int Function(GalleryCell cell) listPos;
  final void Function(String fileName) onPressedHandler;
  final void Function(String fileName) onLongPressedHandler;

  String get storageKey => getKeyOfFilename(srcImage.path);

  @override
  _GalleryCellState createState() => _GalleryCellState();
}

class _GalleryCellState extends State<GalleryCell> {
  // Used for controlling when to take screenshot
  GlobalKey? cropBoxKey = new GlobalKey();
  late final Key? cellKey = ValueKey(fileName);
  late final String fileName = widget.f.path.split("/").last;
  late final PhotoView _photo;
  late String? _notes;
  final SplayTreeMap<SocialType?, Text?> _dates =
      SplayTreeMap((a, b) => enumPriorities[a]! - enumPriorities[b]!);
  int _displayDatesCounter = 0;

  @override
  void initState() {
    // TODO: implement initState
    super.initState();

    _photo = PhotoView(
      imageProvider: FileImage(widget.srcImage),
      initialScale: PhotoViewComputedScale.covered,
      minScale: PhotoViewComputedScale.contained * 0.4,
      maxScale: PhotoViewComputedScale.covered * 1.5,
      basePosition: Alignment.topCenter,
    );

    if (widget.contact?.dateAddedOnSnap != null) {
      String text = snapchatDisplayDate(widget.contact!.dateAddedOnSnap!);
      _dates[SocialType.Snapchat] = createTextWidget(text);
    }
    if (widget.contact?.dateAddedOnInsta != null) {
      String text = instagramDisplayDate(widget.contact!.dateAddedOnInsta!);
      _dates[SocialType.Instagram] = createTextWidget(text);
    }
    _dates[null] = createTextWidget(
        "Profile Found on: \n ${dateFormat.format(widget.contact!.dateFound)}");

    _notes = widget.contact?.notes;
  }

  createTextWidget(String text) => Text(
        text,
        style: TextStyle(color: Colors.white),
        textAlign: TextAlign.center,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      key: cellKey,
      width: MediaQuery.of(context).size.width * 0.95,
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        /**
         * Left side
          */
        Expanded(
          flex: 1,
          child: Container(
            height: 450,
            child: Column(
              children: [
                Expanded(
                  flex: 1,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    /**
                       * Date
                        */
                    child: Builder(builder: (context) {
                      return Builder(builder: (contextt) {
                        List<Text?> displayDates = _dates.values.toList();
                        displayDates.removeWhere((element) => element == null);

                        return GestureDetector(
                            onTap: () {
                              setState(() {
                                _displayDatesCounter++;
                                _displayDatesCounter %= displayDates.length;
                              });
                            },
                            child: IndexedStack(
                              index: _displayDatesCounter,
                              children: displayDates.map((e) => e!).toList(),
                            ));
                      });
                    }),
                  ),
                ),
                Expanded(
                  flex: 11,
                  child: ClipRect(
                    child: Container(
                      child: _photo,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        /**
         *Analysis
         */
        Expanded(
          flex: 1,
          child: Container(
            child: Center(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  /**
                   * Notes button, right edge shifted
                   */
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          // Use MediaQuery to get the screen height
                          var screenHeight = MediaQuery.of(context).size.height;

                          // Define smaller size for FAB in vertical split-screen mode (based on height)
                          double fabSize = screenHeight < 400
                              ? 40.0
                              : 56.0; // Adjust size when height is below 400

                          return SizedBox(
                            height: fabSize, // Adjust the height of the FAB
                            width: fabSize, // Adjust the width of the FAB
                            child: FloatingActionButton(
                              onPressed: () async {
                                _notes = await showNoteDialog(context,
                                        widget.storageKey, widget.contact,
                                        existingNotes: _notes) ??
                                    _notes;
                              },
                              child: Icon(Icons.note_alt_outlined,
                                  size: fabSize *
                                      0.6), // Scale the icon size with the FAB
                              backgroundColor:
                                  const Color.fromARGB(255, 58, 158, 183),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  /**
                   * "Select" and options
                   */
                  Expanded(
                      flex: 1,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8.0, right: 8.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            ElevatedButton(
                              child: Text("Select"),
                              onPressed: () =>
                                  widget.onPressedHandler(fileName),
                              onLongPress: () =>
                                  widget.onLongPressedHandler(fileName),
                            ),
                            ClipRRect(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(4.0)),
                              child: AspectRatio(
                                aspectRatio: 2 / 3,
                                child: Container(
                                  color: Theme.of(context).primaryColor,
                                  child: FutureBuilder(
                                      future:
                                          StorageUtils.get(widget.storageKey),
                                      builder: (context,
                                          AsyncSnapshot<dynamic> snapshot) {
                                        if (snapshot.connectionState ==
                                            ConnectionState.waiting)
                                          return SizedBox();
                                        if (snapshot.hasData &&
                                            !snapshot.hasError) {
                                          ContactEntry? map =
                                              snapshot.data as ContactEntry?;
                                          return FittedBox(
                                            fit: BoxFit.fitHeight,
                                            child: PopupMenuButton<int>(
                                              color: Theme.of(context)
                                                  .secondaryHeaderColor,
                                              padding: EdgeInsets.zero,
                                              itemBuilder:
                                                  (BuildContext context) => [
                                                OurMenuItem(
                                                  "Redo",
                                                  showRedoWindow,
                                                ),
                                                // Assumes that if map isn't null then it follows the formot STRICTLY
                                                if (map != null) ...[
                                                  if (widget
                                                      .snapUsername.isNotEmpty)
                                                    OurMenuItem(
                                                      "Open on snap",
                                                      () => openUserAppPage(
                                                          SocialType.Snapchat,
                                                          addOnSocial: false),
                                                    ),
                                                  if (widget
                                                      .instaUsername.isNotEmpty)
                                                    OurMenuItem(
                                                      "Open on insta",
                                                      () => openUserAppPage(
                                                          SocialType.Instagram,
                                                          addOnSocial: false),
                                                    ),
                                                  if (widget.discordUsername
                                                      .isNotEmpty)
                                                    OurMenuItem(
                                                      "Open on discord",
                                                      () => openUserAppPage(
                                                          SocialType.Discord,
                                                          addOnSocial: false),
                                                    ),
                                                  if (map.addedOnSnap)
                                                    OurMenuItem(
                                                      "Unadd Snap",
                                                      () => unAddUser(
                                                          SocialType.Snapchat),
                                                    ),
                                                  if (map.addedOnInsta)
                                                    OurMenuItem(
                                                      "Unadd Insta",
                                                      () => unAddUser(
                                                          SocialType.Instagram),
                                                    ),
                                                  if (map.addedOnDiscord)
                                                    OurMenuItem(
                                                      "Unadd Discord",
                                                      () => unAddUser(
                                                          SocialType.Discord),
                                                    ),
                                                ],
                                                OurMenuItem(
                                                  "Override username",
                                                  _manuallyUpdateUsername,
                                                ),
                                              ],
                                            ),
                                          );
                                        }
                                        return PopupMenuButton(
                                          itemBuilder: (BuildContext context) =>
                                              [],
                                        );
                                      }),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),

                  Spacer(),

                  /**
                   * Social media suggestions
                   */
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
                          getSocialRow(
                              ((widget.contact?.snapUsername ?? "")
                                      .isNotEmpty &&
                                  SocialIcon.snapchatIconButton != null),
                              SocialType.Snapchat),
                          getSocialRow(
                              ((widget.contact?.instaUsername ?? "")
                                      .isNotEmpty &&
                                  SocialIcon.instagramIconButton != null),
                              SocialType.Instagram),
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
                                    String snap =
                                        value.selection.textInside(value.text);
                                    // StorageUtils.save(widget.storageKey,
                                    //     backup: true,
                                    //     snap: snap,
                                    //     overridingUsername: false);
                                    widget.contact?.snapUsername = snap;
                                    LegacyAppShell.gallery.redoCell(
                                        widget.text,
                                        snap,
                                        widget.instaUsername,
                                        widget.discordUsername,
                                        widget.listPos(widget));
                                    Sortings.scheduleCacheUpdate();
                                    LegacyAppShell.updateFrame?.call(() => null);
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

  void showRedoWindow() {
    showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(32.0))),
            content: AspectRatio(
              aspectRatio: 1 / 1.5,
              child: Column(
                children: [
                  Expanded(
                    flex: 10,
                    child: Align(
                      child: AspectRatio(
                        aspectRatio: 1 / 1,
                        child: RepaintBoundary(
                          key: cropBoxKey,
                          child: Container(
                            child: ClipRRect(child: _photo),
                            // child: ElevatedButton(),
                          ),
                        ),
                      ),
                    ),
                  ),
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
                ],
              ),
            ),
          );
        });
  }

  void redo() async {
    dynamic srcImage = widget.f;
    // Grab QR code image (ref: https://stackoverflow.com/questions/63312348/how-can-i-save-a-qrimage-in-flutter)
    RenderRepaintBoundary boundary =
        cropBoxKey!.currentContext!.findRenderObject() as RenderRepaintBoundary;
    var image = await boundary.toImage();
    ByteData byteData = (await image.toByteData(format: ImageByteFormat.png))!;
    Uint8List pngBytes = byteData.buffer.asUint8List();

    // Create file location for image
    final tempDir = Directory.systemTemp;
    print("tempDir = ${tempDir.path}");
  final File? file =
    await new File('${tempDir.path}/${fileName.split(".").first}.repl.png')
      .create()
      .catchError((e) {
    print("file creation failed.");
    print(e);
    return File('${tempDir.path}/${fileName.split(".").first}.repl.png');
  });

    // Save image locally
    await file!.writeAsBytes(pngBytes).catchError((e) {
      print("file writing failed.");
      print(e);
      return file;
    });
    print("image file exists: " + (await file.exists()).toString());
    print("image file path: " + (file.path));

    // Run OCR
    ocrParallel([file], MediaQuery.of(context).size,
            replace: {widget.listPos(widget): srcImage.path})
        .then((value) => setState(() {}));
  }

  unAddUser(SocialType social) async {
    bool result = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return ConfirmationDialog(message: "Are you sure you want to unadd?");
      },
    );

    if (!result) return;

    Toasts.showToast(true, (_) => "Marked as unadded");
    switch (social) {
      case SocialType.Snapchat:
        widget.contact!.resetSnapchatAdd();
        break;
      case SocialType.Instagram:
        widget.contact!.resetInstagramAdd();
        break;
      case SocialType.Discord:
      default:
        widget.contact!.resetDiscordAdd();
        break;
    }

    _dates.remove(social);
    if (_displayDatesCounter >= _dates.length) {
      _displayDatesCounter--;
    }
  LegacyAppShell.updateFrame?.call(() {});
  }

  openUserAppPage(SocialType social, {bool addOnSocial = true}) async {
  await LegacyAppShell.showProgress(autoComplete: true);
    Uri _site;
    DateTime? date;

    // TODO: enhance this check to see if the previous `_Added` value has changed and only save then
    if (addOnSocial || await _dates[social] == null) {
      date = DateTime.now();
    }

    Future saving = Future.value();

    switch (social) {
      case (SocialType.Snapchat):
        _site = Uri.parse(
            "https://www.snapchat.com/add/${widget.snapUsername.toLowerCase()}");
        if (addOnSocial) {
          if (date != null) {
            // saving = StorageUtils.save(key, backup: true, snapAddedDate: date);
            widget.contact?.addSnapchat();
            _dates[social] ??= createTextWidget(
                snapchatDisplayDate(widget.contact!.dateAddedOnSnap!));
          }
        }
        break;
      case (SocialType.Instagram):
        _site = Uri.parse("https://www.instagram.com/${widget.instaUsername}");
        if (addOnSocial) {
          if (date != null) {
            // saving = StorageUtils.save(key, backup: true, instaAddedDate: date);
            widget.contact?.addInstagram();
            _dates[social] ??= createTextWidget(
                instagramDisplayDate(widget.contact!.dateAddedOnInsta!));
          }
        }
        break;
      case (SocialType.Discord):
      default:
        _site = Uri.parse("");
        Clipboard.setData(ClipboardData(text: widget.discordUsername));
        SocialIcon.discordIconButton?.openApp();
  if (addOnSocial) {
          if (date != null) {
            // saving =
            //     StorageUtils.save(key, backup: true, discordAddedDate: date);
            widget.contact?.addDiscord();
            _dates[social] ??= createTextWidget(
                discordDisplayDate(widget.contact!.dateAddedOnInsta!));
          }
        }
        break;
    }
    // TODO: Make sure there's some other mechinism to update the
  saving.then((_) => Sortings.scheduleCacheUpdate());

    debugPrint("site URI: $_site");
    if (!_site.hasEmptyPath)
      launchUrl(_site, mode: LaunchMode.externalApplication)
          .then((value) => LegacyAppShell.pr.close(delay: 500));
    // Make sure to close the progress dialog
    else
  LegacyAppShell.pr.close(delay: 500);
  }

  TableRow getSocialRow(bool hasUser, SocialType social) {
    String action =
        "Open in  ${social == SocialType.Snapchat ? 'snapchat' : 'instagram'}";
    String username = social == SocialType.Snapchat
        ? widget.snapUsername
        : widget.instaUsername;

    if (hasUser) {
      return TableRow(
        children: [
          TableCell(child: social.icon!),
          TableCell(
              // verticalAlignment: TableCellVerticalAlignment.middle,
              child: Center(
            child: SelectableText(
              username,
              style: TextStyle(color: Colors.redAccent, fontSize: 10),
              showCursor: true,
              maxLines: 1,
            ),
          )),
          FutureBuilder(
            future: social.isAdded(widget.contact),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return TableCell(
                  child: ElevatedButton(
                    onPressed: null,
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: Text("Errored",
                        maxLines: 2, style: TextStyle(fontSize: 8)),
                  ),
                );
              } else {
                bool socialAdded =
                    snapshot.connectionState == ConnectionState.done &&
                        (snapshot.data as bool);
                if (socialAdded) {
                  action = "Mark as Unadded";
                }
                return TableCell(
                  key: ValueKey(socialAdded),
                  child: ElevatedButton(
                    onPressed: () => !socialAdded
                        ? openUserAppPage(social)
                        : unAddUser(social),
                    child: Text(action,
                        maxLines: 2, style: TextStyle(fontSize: 8)),
                  ),
                );
              } /* else{
                return CircularProgressIndicator();
              }*/
            },
          ),
        ],
      );
    } else {
      return TableRow(
        children: [
          TableCell(child: social.icon!),
          TableCell(
              // verticalAlignment: TableCellVerticalAlignment.middle,
              child: Center(
            child: SelectableText(
              "[None]",
              style: TextStyle(color: Colors.redAccent, fontSize: 10),
              showCursor: true,
              maxLines: 1,
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

  AlertDialog _updateUsernameDialog(SocialType social, String username) {
    final formKey = GlobalKey<FormState>();
    void Function(String? foo) validatePhrase = (_) {
      if (formKey.currentState!.validate()) {
        formKey.currentState!.save();
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
                      TableRow(children: [
                        TableCell(child: social.icon!),
                        TableCell(
                            child: TextFormField(
                          initialValue: username,
                          textAlign: TextAlign.center,
                          validator: (value) => value!.isNotEmpty
                              ? null
                              : "Must input value first",
                          onSaved: (value) => Navigator.pop(context, value),
                          onFieldSubmitted: validatePhrase,
                        )),
                      ]),
                    ],
                  ),
                ),
                ElevatedButton(
                    onPressed: () => validatePhrase(null), child: Text("Save"))
              ],
            ),
          ),
        ),
      ),
    );
  }

  TableRow _manualUpdatingUserRows(SocialType social) {
    final _controller = TextEditingController();
    return TableRow(
      children: [
        TableCell(child: social.icon!),
        TableCell(
          child: StreamBuilder(
            stream: social.getUserName(widget.contact).asStream(),
            builder: (BuildContext context, AsyncSnapshot snapshot) {
              if (snapshot.connectionState == ConnectionState.done &&
                  !snapshot.hasError) {
                String username = snapshot.data ?? "";
                _controller.text = username;
                return TextField(controller: _controller, readOnly: true);
              } else {
                return Center(
                  child: CircularProgressIndicator(),
                );
              }
            },
          ),
        ),
        TableCell(
            child: IconButton(
          icon: Icon(Icons.edit_note_rounded),
          onPressed: () async {
            String? newValue = await showDialog(
                context: context,
                builder: (BuildContext context) {
                  return _updateUsernameDialog(social, _controller.text);
                });

            if (newValue != null) {
              _controller.text = newValue;
              await social.saveUsername(widget.contact!, newValue,
                  overriding: true);
              String snap = widget.snapUsername,
                  insta = widget.instaUsername,
                  discord = widget.discordUsername;
              switch (social) {
                case SocialType.Snapchat:
                  snap = newValue;
                  break;
                case SocialType.Instagram:
                  insta = newValue;
                  break;
                case SocialType.Discord:
                  discord = newValue;
                  break;
                default:
                  break;
              }
              LegacyAppShell.gallery.redoCell(
                  widget.text, snap, insta, discord, widget.listPos(widget));
              Sortings.scheduleCacheUpdate();
            }
          },
        ))
      ],
    );
  }

  _manuallyUpdateUsername() {
    showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
              content: SingleChildScrollView(
            child: Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
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
          ));
        });
  }
}

// ignore: non_constant_identifier_names
PopupMenuItem<int> OurMenuItem(
    final String _displayTxt, final Function _callback) {
  Text text = Text(
    _displayTxt,
    style: TextStyle(fontSize: 12),
  );
  return PopupMenuItem<int>(
    /*value: 0,*/
    child: text,
    onTap: () =>
        WidgetsBinding.instance.addPostFrameCallback((_) => _callback()),
  );
}
