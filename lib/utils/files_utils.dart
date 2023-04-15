
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:PhotoWordFind/constants/constants.dart';
import 'package:PhotoWordFind/utils/image_utils.dart';
import 'package:PhotoWordFind/utils/sort_utils.dart';
import 'package:PhotoWordFind/utils/storage_utils.dart';
import 'package:flutter_isolate/flutter_isolate.dart';
import 'package:path/path.dart' as path;
import 'package:PhotoWordFind/main.dart';
import 'package:flutter/widgets.dart';
// import 'package:isolate_handler/isolate_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';


Future<String> runOCR(String filePath, {bool crop=true, ui.Size? size}) async {
  print("Entering runOCR()...");
  debugPrint("Running OCR on $filePath");
  File tempCropped = crop ? createCroppedImage(
      filePath, Directory.systemTemp, size!) : new File(filePath);

  debugPrint("Leaving runOCR()");
  return OCR(tempCropped.path);
}

/// Searches for the occurance of a keyword meaning there is a snapchat username and returns a suggestion for the user name
String? suggestionSnapName(String text) {
  return suggestionUserName(text, snapnameKeyWords);
}
String? suggestionInstaName(String text) {
  return suggestionUserName(text, instanameKeyWords);
}

String? suggestionUserName(String text, List<String> keys){
  // TODO: Change so tha it finds the next word in the series, not the row
  text = text.toLowerCase();
  // text = text.replaceAll(new RegExp('[-+.^:,|!]'),'');
  // text = text.replaceAll(new RegExp('[^A-Za-z0-9]'),'');
  // Remove all non-alphanumeric characters
  debugPrint("text: " + text.replaceAll(new RegExp('[^A-Za-z0-9]'),' '));

  // Split up lines
  for(String line in text.split("\n")){
    // Split up words
    int i = 0;
    List<String> words= line.split(" ");
    for(String word in words){
      if (keys.contains(word.replaceAll(new RegExp('[^A-Za-z0-9]'), '').trim()))
        return (i + 1 < words.length) ? words[++i].trim().replaceAll(new RegExp('^[@]'), "") : "";
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

Future ocrParallel(List filesList, Size size, { String? query, bool findFirst = false, Map<int, String?>? replace}) async{

  await MyApp.showProgress(limit: filesList.length);
  // Have a small delay in case there is no large computation to use as time buffer
  await Future.delayed(const Duration(milliseconds: 500), (){});

  // Reset Gallery
  if(replace == null) {
    if(MyApp.gallery.length() > 0)
      MyApp.gallery.galleryController.jumpToPage(0);
    MyApp.gallery.clear();
  }

  // Time search
  Stopwatch timeElasped = new Stopwatch();


  final List<Future> isolates = [];
  int completed = 0;
  int filesIdx = 0;
  timeElasped.start();

  // Make sure latest thread cached updates exist in main thread
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  int startingStorageSize = prefs.getKeys().length;

  await Sortings.updateCache();
  filesList.sort(Sortings.getSorting() as int Function(dynamic, dynamic)?);
  for(filesIdx = 0; filesIdx < filesList.length; filesIdx++){


    // Prepare data to be sent to thread
    var srcFile = filesList[filesIdx];

    Map<String, dynamic> message = {
      "f": srcFile.path,
      "height": size.height,
      "width" : size.width
    };
    String rawJson = jsonEncode(message);
    String isoName = path.basename(srcFile.path);
    debugPrint("srcFilePath [${srcFile.path}] :: isolate name $isoName :: rawJson -> $rawJson");

    Future<String?> job = createOCRJob(srcFile, rawJson, replace != null);
    Future processResult = job.then((result) => onEachOcrResult(result, srcFile, query, replace, timeElasped, filesList.length, ++completed, isolates));
    isolates.add( processResult );

  }

  final joinIsolates = await Future.wait(isolates);
  debugPrint("Joined [ ${joinIsolates.length} ] isolates");
  debugPrint("completed: $completed");



  debugPrint("popping...");

  // Quick fix for this callback being called twice
  // TODO: Find way to stop isolates immediately so they don't get to this point
  if (MyApp.pr.isOpen()) {
    MyApp.pr.close();

    MyApp.updateFrame(() => null);
    debugPrint(">>> getting in.");
  }

  final int finalStorageSize = prefs.getKeys().length;
  // Only backup when getting new data
  if (startingStorageSize < finalStorageSize || replace != null)
    await StorageUtils.syncLocalAndCloud();

}

Future<String?> createOCRJob(dynamic srcFile, String rawJson, bool replacing) async{
  debugPrint("Entering createOCRJob()...");
  final prefs = await SharedPreferences.getInstance();

  String key = getKeyOfFilename(srcFile.path);

  var result;
  if(replacing) {
    debugPrint(">>> Removing cached OCR result");
    prefs.remove(key);

    debugPrint("Running OCR redo in main thread...");
    result = await runOCR(srcFile.path, crop: false);

    await StorageUtils.save(key, ocrResult: result, snap: "", overridingUsername: false, backup: true); //The "await" is needed for synchronization with main thread
  }

  // Check if this file's' OCR has been cached
  else if(await StorageUtils.get(key, reload: true) != null){
    debugPrint("This file[$key]'s result has been cached. Skipping OCR threading and directly processing result.");
    result = await StorageUtils.get(key, reload: false);
  }
  else {
    // Start up the thread and configures the callbacks
    debugPrint("Spawning new iso for [$key]....");
    result = flutterCompute(ocrThread, rawJson);
  }

  debugPrint("Leaving createOCRJob()...");
  return result;
}

void increaseProgressBar(int completed, int pathsLength){
  int update = (completed+1)*100~/pathsLength;
  update = update.clamp(0, 100);
  print("Increasing... " + update.toString());
  MyApp.pr.update(value: completed, msg: "Loading...");
}

@pragma('vm:entry-point')
Future<String?> ocrThread(String receivedData) async {

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

      await StorageUtils.save(key, ocrResult: result, backup: false);

      // Send back result to main thread
      debugPrint("Sending OCR result...");
      return result;
  }
  else{
    return "";
  }

}

Future onEachOcrResult (
    String? result,
    srcFile,
    String? query,
    Map? replace,
    timeElapsed,
    filesListLength,
    int completed,
    isolates,
    ) async {
    debugPrint("Entering onOCRResult...");
    if (result is String) {
      String ocr = result;
      // If query word has been found
      String key = getKeyOfFilename(srcFile.path);
      String savedSnapUser = (await StorageUtils.get(key, reload: true, snap: true)) as String;
      String savedInstaUser = (await StorageUtils.get(key, reload: false, insta: true) as String);
      String? snapUsername, instaUsername = "";
      if (savedSnapUser.isNotEmpty) {
        snapUsername = savedSnapUser.replaceAll(new RegExp('^[@]'), "");
      }
      else {
        String snap = suggestionSnapName(ocr) ?? "";
        if (snap.isNotEmpty)
          StorageUtils.save(key, backup: true, snap: snap, overridingUsername: false);
        snapUsername = snap;
      }

      if (savedInstaUser.isNotEmpty) {
        instaUsername = savedInstaUser.replaceAll(new RegExp('^[@]'), "");
      }
      else {
        String insta = suggestionInstaName(ocr) ?? "";
        if (insta.isNotEmpty)
          StorageUtils.save(key, backup: true, insta: insta, overridingUsername: false);
        instaUsername = insta;
      }

      // Skip this image if query word has not been found
      bool skipImage =
          query != null
          && !snapUsername.toLowerCase().contains(query.toLowerCase())
          && !ocr.toLowerCase().contains(query.toLowerCase());

      if (!skipImage) {
        if (replace == null)
          MyApp.gallery.addNewCell(
              ocr, snapUsername, srcFile, new File(srcFile.path), instaUsername: instaUsername);
        else {
          var pair = replace.entries.first;
          int idx = pair.key;
          MyApp.gallery.redoCell(ocr, snapUsername, "", idx);
          // Note: scrFile will always be a File for redo and ONLY redo
          (srcFile as File).delete();
        }

        debugPrint("Elapsed: ${timeElapsed.elapsedMilliseconds}ms");
      }

    }

    increaseProgressBar(completed, filesListLength);

    debugPrint("Leaving onOCRResult...");
}