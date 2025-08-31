
import 'dart:io';
// import 'dart:convert';

import 'package:PhotoWordFind/main.dart';
import 'package:PhotoWordFind/utils/files_utils.dart';
import 'package:PhotoWordFind/models/contactEntry.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/material.dart';
// import 'package:hive/hive.dart';

enum Operations{
  MOVE,
  FIND,
  DISPLAY_ALL,
  DISPLAY_SELECT
}

class Operation{

  static Operations? retry;
  static late Function? retryOp, _envChange;
  static run(Operations operation, Function? envChange, {
    BuildContext? context,
    Function? directoryPath,
    String? findQuery,
    List? displayImagesList,
    List<ContactEntry>? moveSrcList,
    String? moveDesDir,
  }){

    retry = operation;
    _envChange = envChange;

    switch(operation){
      case(Operations.MOVE):
        move(moveSrcList!, moveDesDir!);
        break;
      case(Operations.FIND):
        retryOp = () {
          LegacyAppShell.updateFrame?.call((){
            find(directoryPath!, findQuery!, context);
          });
        };
        retryOp!();
        return;
      case(Operations.DISPLAY_ALL):
        retryOp = (){
          _displayImages(displayImagesList, context);
        };
        retryOp!();
        break;
      case(Operations.DISPLAY_SELECT):
        _displayImages(displayImagesList, context);
        return;
      default:
        break;

    }
    retry = null;
  }

  static bool isRetryOp(){
    return retry != null;
  }

  static void find(Function directoryPath, String query, BuildContext? context) async{
    debugPrint("Entering find()...");

    List<dynamic> paths;
    paths = Directory(directoryPath()).listSync(recursive: false, followLinks:false);


    debugPrint("paths: " + paths.toString());
    // If the paths list is empty, close progress and return
    if(paths.isEmpty) {
      LegacyAppShell.pr.close();
      return;
    }

    // Remove prompt
    if(ModalRoute.of(context!)?.isCurrent != true)
      Navigator.pop(context);

    debugPrint("Query: $query");
    await ocrParallel(paths, MediaQuery.of(context).size, query: query);

    debugPrint("Leaving find()...");
  }

  static void move(List<ContactEntry> srcList, String destDir) {
    for (final entry in srcList) {
      final src = entry.imagePath;
      final fileName = path.basename(src);
      final dst = path.join(destDir, fileName);

      // Move the physical file first
      File(src).renameSync(dst);

      // Update only the in-memory ContactEntry path per request
      entry.imagePath = dst;
    }
  }

  static _displayImages(List? paths, BuildContext? context) async{
    debugPrint("Entering _displayImages()...");

    if(paths == null) {
  LegacyAppShell.pr.close();
      return;
    }

    ocrParallel(paths, MediaQuery.of(context!).size);
    debugPrint("Leaving _displayImages()...");
  }

  static Widget? displayRetry(){
    if(!isRetryOp()) return null;

    return Expanded(
      flex: 2,
      child: Container(
        child: Center(
          child: Column(
            children: [
              Text("The last operation did not return any files. Would you like to try a different folder?"),
              ElevatedButton(onPressed: ()async {await _envChange!(); await retryOp!();}, child: Text("Yes")),
              ElevatedButton(onPressed: (){retry = null; LegacyAppShell.updateFrame?.call(() => null);}, child: Text("No.")),
            ],
          )
        )
      ),
    );
  }
}