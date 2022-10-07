
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:PhotoWordFind/utils/image_utils.dart';
import 'package:PhotoWordFind/utils/storate_utils.dart';
import 'package:path/path.dart' as path;
import 'package:PhotoWordFind/main.dart';
import 'package:flutter/widgets.dart';
import 'package:isolate_handler/isolate_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';


Future<String> runOCR(String filePath, {bool crop=true, ui.Size size}) async {
  print("Entering runOCR()...");
  debugPrint("Running OCR on $filePath}");
  File temp_cropped = crop ? createCroppedImage(
      filePath, Directory.systemTemp, size) : new File(filePath);

  debugPrint("Leaving runOCR()");
  return OCR(temp_cropped.path);
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

List<String> getFileNameAndExtension(String f){
  List<String> split = path.basename(f).split(".");

  return split;
}

String getKeyOfFilename(String f){
  List<String> split = getFileNameAndExtension(f);
  String key = split.first;

  return key;
}

Future ocrParallel(List filesList, Function post, Size size, {String query, bool findFirst = false, Map<int, String> replace}) async{

  // MyApp.pr.update(value: 0);
  await MyApp.showProgress(limit: filesList.length);

  // Reset Gallery
  if(replace == null) {
    if(MyApp.gallery.length() > 0)
      MyApp.gallery.galleryController.jumpToPage(0);
    MyApp.gallery.clear();
  }

  // Time search
  Stopwatch time_elasped = new Stopwatch();


  final isolates = IsolateHandler();
  int completed = 0;
  int files_idx = 0;
  time_elasped.start();

  // Make sure latest thread cached updates exist in main thread
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();


  for(files_idx = 0; files_idx < filesList.length; files_idx++){


    // Prepare data to be sent to thread
    var srcFile = filesList[files_idx];

    Map<String, dynamic> message = {
      "f": srcFile.path,
      "height": size.height,
      "width" : size.width
    };
    String rawJson = jsonEncode(message);
    String iso_name = path.basename(srcFile.path);
    debugPrint("srcFilePath [${srcFile.path}] :: isolate name $iso_name :: rawJson -> $rawJson");

    // Define callback
    void onEachOcrResult (dynamic signal) {
      debugPrint("Entering onOCRResult...");
      debugPrint("Checking type of OCR result: ${signal.runtimeType}");
      if(signal is String){
        String text = signal;
        // If query word has been found
        String suggestedUsername = post(text, query);
        if(suggestedUsername != null) {

          if(replace == null)
            MyApp.gallery.addNewCell(text, suggestedUsername, srcFile, new File(srcFile.path));
          else{
            var pair = replace.entries.first;
            int idx = pair.key;
            MyApp.gallery.redoCell(text, suggestedUsername, idx);
            // Note: scrFile will always be a File for redo and ONLY redo
            (srcFile as File).delete();
          }

          debugPrint("Elasped: ${time_elasped.elapsedMilliseconds}ms");

          // Stop creation of new isolates and to close dialogs
          if(findFirst) {
            files_idx = filesList.length;
            completed = filesList.length;
          }
        }

        // isolates.kill(iso_name);
      }
      else{
        // Dispose of finished isolate
        debugPrint("Killing isolate...");
        isolates.kill(iso_name, priority: Isolate.immediate);
      }

      debugPrint("before `completed`... $completed <= ${filesList.length}");
      debugPrint("before `path_idx`... $files_idx <= ${filesList.length}");


      increaseProgressBar(completed, filesList);

      // Close dialogs once finished with all images
      if(++completed >= filesList.length){

        debugPrint("Terminate all running isolates...");

        terminateRunningThreads(iso_name, isolates);

        debugPrint("popping...");

        // Quick fix for this callback being called twice
        // TODO: Find way to stop isolates immediately so they don't get to this point
        if(MyApp.pr.isOpen()) {
          MyApp.pr.close();
          MyApp.pr.close();

          MyApp.updateFrame(() => null);
          debugPrint(">>> getting in.");
        }
      }
      else{
        isolates.kill(iso_name, priority: Isolate.immediate);
      }
    };

    await createOCRJob(iso_name, srcFile, rawJson, onEachOcrResult, isolates, replace != null);

  }
}

createOCRJob(String iso_name, dynamic src_filePath, String rawJson, Function onEachOcrResult, IsolateHandler isolates, bool replacing) async{
  debugPrint("Entering createOCRJob()...");
  final prefs = await SharedPreferences.getInstance();

  List<String> split = getFileNameAndExtension(src_filePath.path);
  String key = getKeyOfFilename(src_filePath.path);
  // bool replacing = split.length == 3;

  if(replacing) {
    debugPrint(">>> Removing cached OCR result");
    prefs.remove(key);

    debugPrint("Running OCR redo in main thread...");
    String result = await runOCR(src_filePath.path, crop: false);

    StorageUtils.save(key, result);
    onEachOcrResult(result);
  }

  // Check if this file needs to OCR or has been cached
  else if(await StorageUtils.get(key, reload: true) != null){
    debugPrint("This file[$key]'s result has been cached. Skipping OCR threading and directly processing result.");
    String result = await StorageUtils.get(key, reload: false);
    onEachOcrResult(result);
  }
  else {
    // Start up the thread and configures the callbacks
    debugPrint("Spawning new iso for [$key]....");
    isolates.spawn<String>(
        ocrThread,
        name: iso_name,
        onInitialized:() => isolates.send(rawJson, to: iso_name),
        onReceive: (dynamic signal) => onEachOcrResult(signal));
  }
  debugPrint("Leaving createOCRJob()...");
}

void increaseProgressBar(int completed, List paths){
  int update = (completed+1)*100~/paths.length;
  update = update.clamp(0, 100);
  print("Increasing... " + update.toString());
  MyApp.pr.update(value: completed);
  MyApp.pr.update(value: completed, msg: "Loading...");
}

void terminateRunningThreads(String currentThead, IsolateHandler isolates){
  debugPrint("Entering terminateRunningThreads()...");
  List names = isolates.isolates.keys.toList();
  for(String name in names){
    // Don't kill current thread
    if(name == currentThead) continue;

    debugPrint("next iso-name: ${name}");
    if(isolates.isolates[name].messenger.connectionEstablished ) {
      try {
        isolates.kill(name, priority: Isolate.immediate);
      }
      catch(e){
        debugPrint("ERROR >> while terminating isolate, $e");
      }
    }
  }

  debugPrint("Leaving terminateRunningThreads()...");
}

void ocrThread(Map<String, dynamic> context) {

  debugPrint("Initializing new thread...");
  final messenger = HandledIsolate.initialize(context);


  // Operation that should happen when the Isolate receives a message
  messenger.listen((receivedData) async {
    if(receivedData is String) {

      final prefs = await SharedPreferences.getInstance();

      Map<String, dynamic> message = json.decode(receivedData);
      String filePath = message["f"];
      ui.Size size = ui.Size(
          message['width'].toDouble(),
          message['height'].toDouble()
      );

      debugPrint("Running thread for >> $filePath");

      dynamic result;
      try {
        result = await runOCR(filePath, size: size);
      }
      catch(error, stackTrace){
        result = null;
        debugPrint("File ($filePath) failed");
        debugPrint("$error \n $stackTrace");
        debugPrint("Leaving try-catch");
      }
      if (result is String) {
          String key = getKeyOfFilename(filePath);
          // Save OCR result
          debugPrint("Save OCR result of key:[$key] >> ${result.replaceAll("\n", " ")}");

          StorageUtils.save(key, result);

          // Send back result to main thread
          debugPrint("Sending OCR result...");
          messenger.send(result);
      }
      else{
        messenger.send("");
      }
    }
    else{
      debugPrint("did NOT detect string...");
      messenger.send(null);
    }

  });

}