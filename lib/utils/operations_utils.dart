
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
  static run(Operations operation, Function envChange, {BuildContext context, String directoryPath, String findQuery}){

    retry = operation;
    _envChange = envChange;

    switch(operation){
      case(Operations.MOVE):
        retryOp = (){

        };
        return;
      case(Operations.FIND):
        retryOp = () {
          find(directoryPath, findQuery, context);
        };
        retryOp();
        return;
      case(Operations.DISPLAY_ALL):
        break;
      case(Operations.DISPLAY_SELECT):
        return;
      default:
        break;

    }
    retry = null;
  }

  bool isRetyOp(){
    return retry != null;
  }

  static void find(String directoryPath, String query, BuildContext context) async{

    List<dynamic> paths;
    paths = Directory(directoryPath).listSync(recursive: false, followLinks:false);


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
    Navigator.pop(context);

    await ocrParallel(paths, post, MediaQuery.of(context).size, query: query);

  }

  Widget displayRetry(){
    return Container(
      child: Center(
        child: Column(
          children: [
            Text("The last operation did not return any files. Would you like to try a different folder?"),
            ElevatedButton(onPressed: _envChange, child: Text("Yes")),
            ElevatedButton(onPressed: (){retry = null; MyApp.updateFrame();}, child: Text("No.")),
          ],
        )
      )
    );
  }
}