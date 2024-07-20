
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
String? suggestionDiscordName(String text) {
  text = text.replaceAll("\n", " ");
  List<String> words = text.split(" ");
  try {
    String discord = words.firstWhere(
        (element) => element.contains(RegExp(r'^.{3,32}#[0-9]{4}$')), orElse: () => "");
    return discord;
  }
  on Exception catch(_e){
    Exception e = _e as Exception;
    debugPrint("${e.toString()} failed");
    debugPrint(e.toString());
    throw(e);
  }
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

  await MyApp.showProgress(autoComplete: false, limit: filesList.length);
  // Have a small delay in case there is no large computation to use as time buffer
  await Future.delayed(const Duration(milliseconds: 300), (){});

  // Reset Gallery
  if(replace == null) {
    if(MyApp.gallery.length() > 0){
      MyApp.gallery.galleryController.jumpToPage(0);
      }
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

    Future<Map<String, dynamic>?> job = createOCRJob(srcFile, rawJson, replace != null);
    // Subtracting the completed number by 1 in order to control the auto complete of the progress dialog
    Future processResult = job.then((result) => onEachOcrResult(result, srcFile, query, replace, timeElasped, filesList.length, ++completed-1));
    isolates.add( processResult );

  }

  try {
    final joinIsolates = await Future.wait(isolates);
    await prefs.reload();
    debugPrint("Joined [ ${joinIsolates.length} ] isolates");
  }
  on Exception catch(e){
    debugPrint("At least one of the operations failed. \n$e");
  }
  debugPrint("completed: $completed");

  MyApp.updateFrame(() => null);

  final int finalStorageSize = prefs.getKeys().length;
  // Only backup when getting new data
  if (startingStorageSize < finalStorageSize || replace != null)
    await StorageUtils.syncLocalAndCloud();

  // Display completed status
  increaseProgressBar(completed, filesList.length);
  // Close dialog and control delay
  if (MyApp.pr.isOpen()) {
    MyApp.pr.close(delay:500);
    debugPrint(">>> getting in.");
  }

}

Future<Map<String, dynamic>?> createOCRJob(dynamic srcFile, String rawJson, bool replacing) async{
  debugPrint("Entering createOCRJob()...");
  final prefs = await SharedPreferences.getInstance();

  String key = getKeyOfFilename(srcFile.path);

  var result;
  if(replacing) {
    debugPrint(">>> Removing cached OCR result");
    prefs.remove(key);

    debugPrint("Running OCR redo in main thread...");
    String ocr = await runOCR(srcFile.path, crop: false);

    result = postProcessOCR(ocr);

    await StorageUtils.save(key, asMap: result, backup: true); //The "await" is needed for synchronization with main thread
  }

  // Check if this file's' OCR has been cached
  else if(await StorageUtils.get(key, reload: true) != null){
    debugPrint("This file[$key]'s result has been cached. Skipping OCR threading and directly processing result.");
    result = await StorageUtils.get(key, asMap:true, reload: false);
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

Map<String, dynamic> postProcessOCR(String ocr) {
  Map<String, dynamic> map = StorageUtils.convertValueToMap(ocr);
  String snap = suggestionSnapName(ocr) ?? "";
  String insta = suggestionInstaName(ocr) ?? "";
  String discord = suggestionDiscordName(ocr) ?? "";

  if (snap.isNotEmpty) {
    map[SubKeys.SnapUsername] = snap;
  }

  if (insta.isNotEmpty) {
    map[SubKeys.InstaUsername] = insta;
  }

  if (discord.isNotEmpty) {
    map[SubKeys.DiscordUsername] = discord;
  }

  return map;
}

@pragma('vm:entry-point')
Future<Map<String, dynamic>?> ocrThread(String receivedData) async {

  Map<String, dynamic> message = json.decode(receivedData);
  String filePath = message["f"];
  ui.Size size = ui.Size(
      message['width'].toDouble(),
      message['height'].toDouble()
  );

  debugPrint("Running thread for >> $filePath");

  String? ocr;
  try {
    ocr = await runOCR(filePath, size: size);
  }
  catch(error, stackTrace){
    ocr = null;
    debugPrint("File ($filePath) failed");
    debugPrint("$error \n $stackTrace");
    debugPrint("Leaving try-catch");
  }
  if (ocr is String) {
      String key = getKeyOfFilename(filePath);
      // Save OCR result
      debugPrint("Save OCR result of key:[$key] >> ${ocr.replaceAll("\n", " ")}");

      Map<String, dynamic> result = postProcessOCR(ocr);

      await StorageUtils.save(key, asMap: result, backup: false);

      // Reload storage for this thread
      await StorageUtils.get("", reload: true);

      // Send back result to main thread
      debugPrint("Sending OCR result...");
      return result;
  }
  else{
    return {};
  }

}

Future onEachOcrResult (
    Map<String, dynamic>? result,
    srcFile,
    String? query,
    Map? replace,
    timeElapsed,
    filesListLength,
    int completed,
    ) async {
    debugPrint("Entering onOCRResult...");

  // If query word has been found
  String ocr = result?[SubKeys.OCR] ?? "";
  String snapUsername = result?[SubKeys.SnapUsername] as String;
  String instaUsername = result?[SubKeys.InstaUsername] as String;
  String discordUsername = result?[SubKeys.DiscordUsername] as String;


  // Skip this image if query word has not been found
  bool skipImage = query != null &&
      !snapUsername.toLowerCase().contains(query.toLowerCase()) &&
      !ocr.toLowerCase().contains(query.toLowerCase());

  if (!skipImage) {
    if (replace == null)
      MyApp.gallery.addNewCell(
          ocr, snapUsername, srcFile, new File(srcFile.path),
          instaUsername: instaUsername, discordUsername: discordUsername);
    else {
      var pair = replace.entries.first;
      int idx = pair.key;
      MyApp.gallery.redoCell(ocr, snapUsername, "", "", idx);
      // Note: scrFile will always be a File for redo and ONLY redo
      (srcFile as File).delete();
    }

    debugPrint("Elapsed: ${timeElapsed.elapsedMilliseconds}ms");
  }

  increaseProgressBar(completed, filesListLength);

    debugPrint("Leaving onOCRResult...");
}