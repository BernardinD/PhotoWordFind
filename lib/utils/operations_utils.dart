
import 'dart:io';

import 'package:PhotoWordFind/main.dart';
import 'package:PhotoWordFind/utils/files_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum Operations{
  MOVE,
  FIND,
  DISPLAY_ALL,
  DISPLAY_SELECT
}

class Operation{

  static Operations retry = null;
  static Function retryOp, _envChange;
  static run(Operations operation, Function envChange, {
    BuildContext context,
    Function directoryPath,
    String findQuery,
    List displayImagesList,
    List<String> moveSrcList,
    String moveDesDir,
  }){

    retry = operation;
    _envChange = envChange;

    switch(operation){
      case(Operations.MOVE):
        move(moveSrcList, moveDesDir, directoryPath);
        break;
      case(Operations.FIND):
        retryOp = () {
          find(directoryPath, findQuery, context);
        };
        retryOp();
        return;
      case(Operations.DISPLAY_ALL):
        retryOp = (){
          _displayImages(displayImagesList, context);
        };
        retryOp();
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

  static void find(Function directoryPath, String query, BuildContext context) async{
    debugPrint("Entering find()...");

    List<dynamic> paths;
    paths = Directory(directoryPath()).listSync(recursive: false, followLinks:false);


    debugPrint("paths: " + paths.toString());
    if(paths == null) {
      await MyApp.pr.close();
      return;
    }

    Function post = (String text, query){

      // If query word has been found
      return text.toString().toLowerCase().contains(query.toLowerCase()) ? query : null;
    };

    // Remove prompt
    if(ModalRoute.of(context)?.isCurrent != true)
      Navigator.pop(context);

    debugPrint("Query: $query");
    await ocrParallel(paths, MediaQuery.of(context).size, query: query);

    debugPrint("Leaving find()...");
  }

  static void move(List<String> srcList, String destDir, Function directoryPath){

    var lst = srcList.map((x) => [(directoryPath().toString() +"/"+ x), (destDir +"/"+ x)] ).toList();

    debugPrint("List:" + lst.toString());
    String src, dst;
    for(List<String> pair in lst){
      src = pair[0];
      dst = pair[1];
      File(src).renameSync(dst);
    }
  }

  static _displayImages(List paths, BuildContext context) async{
    debugPrint("Entering _displayImages()...");

    if(paths == null) {
      await MyApp.pr.close();
      return;
    }

    ocrParallel(paths, MediaQuery.of(context).size);
    debugPrint("Leaving _displayImages()...");
  }

  static Widget displayRetry(){
    if(!isRetryOp()) return null;

    return Expanded(
      flex: 2,
      child: Container(
        child: Center(
          child: Column(
            children: [
              Text("The last operation did not return any files. Would you like to try a different folder?"),
              ElevatedButton(onPressed: ()async {await _envChange(); await retryOp();}, child: Text("Yes")),
              ElevatedButton(onPressed: (){retry = null; MyApp.updateFrame(() => null);}, child: Text("No.")),
            ],
          )
        )
      ),
    );
  }
}