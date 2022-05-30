
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:PhotoWordFind/utils/image_utils.dart';
import 'package:path/path.dart' as path;
import 'package:PhotoWordFind/main.dart';
import 'package:flutter/widgets.dart';
import 'package:isolate_handler/isolate_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';



Future<String> runOCR(String filePath, ui.Size size, {bool crop = true}) async {
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

String generateKeyFromFilename(String f){
  List<String> split = getFileNameAndExtension(f);
  String key = split.first;

  return key;
}

Future ocrParallel(List paths, Function post, Size size, {String query, bool findFirst = false, Map<int, String> replace}) async{

  MyApp.pr.update(progress: 0);
  await MyApp.pr.show();

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
  int path_idx = 0;
  time_elasped.start();

  // Make sure latest thread cached updates exist in main thread
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();


  for(path_idx = 0; path_idx < paths.length; path_idx++){


    // Prepare data to be sent to thread
    var srcFilePath = paths[path_idx];

    Map<String, dynamic> message = {
      "f": srcFilePath.path,
      "height": size.height,
      "width" : size.width
    };
    String rawJson = jsonEncode(message);
    String iso_name = path.basename(srcFilePath.path);
    debugPrint("srcFilePath [${srcFilePath.path}] :: isolate name $iso_name :: rawJson -> $rawJson");

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
            MyApp.gallery.addNewCell(text, suggestedUsername, srcFilePath, new File(srcFilePath.path));
          else{
            var pair = replace.entries.first;
            int idx = pair.key;
            MyApp.gallery.redoCell(text, suggestedUsername, idx);
          }

          debugPrint("Elasped: ${time_elasped.elapsedMilliseconds}ms");

          // Stop creation of new isolates and to close dialogs
          if(findFirst) {
            path_idx = paths.length;
            completed = paths.length;
          }
        }

        // isolates.kill(iso_name);
      }
      else{
        // Dispose of finished isolate
        debugPrint("Killing isolate...");
        isolates.kill(iso_name, priority: Isolate.immediate);
      }

      debugPrint("before `completed`... $completed <= ${paths.length}");
      debugPrint("before `path_idx`... $path_idx <= ${paths.length}");


      increaseProgressBar(completed, paths);

      // Close dialogs once finished with all images
      if(++completed >= paths.length){

        debugPrint("Terminate all running isolates...");

        terminateRunningThreads(iso_name, isolates);

        debugPrint("popping...");

        // Quick fix for this callback being called twice
        // TODO: Find way to stop isolates immediately so they don't get to this point
        if(MyApp.pr.isShowing()) {
          MyApp.pr.hide().then((value) {
            // setState(() => {});
            MyApp.updateFrame(() => null);
            debugPrint(">>> getting in.");
          });
        }
      }
    };

    await createOCRThread(iso_name, srcFilePath, rawJson, onEachOcrResult, isolates, replace != null);

  }
}

createOCRThread(String iso_name, dynamic src_filePath, String rawJson, Function onEachOcrResult, IsolateHandler isolates, bool replacing) async{
  debugPrint("Entering createOCRThread()...");
  final prefs = await SharedPreferences.getInstance();

  List<String> split = getFileNameAndExtension(src_filePath.path);
  String key = generateKeyFromFilename(src_filePath.path);
  // bool replacing = split.length == 3;

  if(replacing) {
    debugPrint(">>> Removing cached OCR result");
    prefs.remove(key);
  }

  // Check if this file needs to OCR or has been cached
  if(prefs.getString(key) != null){
    debugPrint("This file[$key]'s result has been cached. Skipping OCR threading and directly processing result.");
    String result = prefs.getString(key);
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
  debugPrint("Leaving createOCRThread()...");
}

void increaseProgressBar(int completed, List paths){
  int update = (completed+1)*100~/paths.length;
  update = update.clamp(0, 100);
  print("Increasing... " + update.toString());
  MyApp.pr.update(maxProgress: 100.0, progress: update/1.0);
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
      String f = message["f"];
      ui.Size size = ui.Size(
          message['width'].toDouble(),
          message['height'].toDouble()
      );

      debugPrint("Running thread for >> $f");

      List<String> split = getFileNameAndExtension(f);
      String key = generateKeyFromFilename(f);
      bool replacing = split.length == 3;

      if(replacing) {
        prefs.remove(key);
      }

      runOCR(f, size, crop: !replacing).then((result) {
        if (result is String) {
          // Save OCR result
          debugPrint("Save OCR result of key:[$key] >> ${result.replaceAll("\n", " ")}");
          prefs.setString(key, result);

          // Send back result to main thread
          debugPrint("Sending OCR result...");
          messenger.send(result);
        }
        else{
          messenger.send("");
        }
      });
    }
    else{
      debugPrint("did NOT detect string...");
      messenger.send(null);
    }

  });

}