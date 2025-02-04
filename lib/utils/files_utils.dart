import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:PhotoWordFind/services/chat_gpt_service.dart';
import 'package:flutter/material.dart';

import 'package:PhotoWordFind/constants/constants.dart';
import 'package:PhotoWordFind/utils/image_utils.dart';
import 'package:PhotoWordFind/utils/sort_utils.dart';
import 'package:PhotoWordFind/utils/storage_utils.dart';
import 'package:flutter_isolate/flutter_isolate.dart';
import 'package:path/path.dart' as path;
import 'package:PhotoWordFind/main.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

Future<Map<String, dynamic>> extractProfileData(String filePath,
    {bool crop = true, ui.Size? size}) async {
  print("Entering runOCR()...");
  debugPrint("Running OCR on $filePath");
  File tempCropped = crop
      ? createCroppedImage(filePath, Directory.systemTemp, size!)
      : new File(filePath);

  debugPrint("Leaving runOCR()");
  final ocr = await OCR(tempCropped.path);

  Map<String, dynamic> result = postProcessOCR(ocr);

  return result;
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
        (element) => element.contains(RegExp(r'^.{3,32}#[0-9]{4}$')),
        orElse: () => "");
    return discord;
  } on Exception catch (_e) {
    Exception e = _e as Exception;
    debugPrint("${e.toString()} failed");
    debugPrint(e.toString());
    throw (e);
  }
}

String? suggestionUserName(String text, List<String> keys) {
  // TODO: Change so tha it finds the next word in the series, not the row
  text = text.toLowerCase();
  // text = text.replaceAll(new RegExp('[-+.^:,|!]'),'');
  // text = text.replaceAll(new RegExp('[^A-Za-z0-9]'),'');
  // Remove all non-alphanumeric characters
  debugPrint("text: " + text.replaceAll(new RegExp('[^A-Za-z0-9]'), ' '));

  // Split up lines
  for (String line in text.split("\n")) {
    // Split up words
    int i = 0;
    List<String> words = line.split(" ");
    for (String word in words) {
      if (keys.contains(word.replaceAll(new RegExp('[^A-Za-z0-9]'), '').trim()))
        return (i + 1 < words.length)
            ? words[++i].trim().replaceAll(new RegExp('^[@]'), "")
            : "";
      i++;
    }
  }
  return null;
}

List<String> getFileNameAndExtension(String f) {
  List<String> split = path.basename(f).split(".");

  return split;
}

String getKeyOfFilename(String f) {
  List<String> split = getFileNameAndExtension(f);
  String key = split.first;

  return key;
}

Future ocrParallel(List filesList, Size size,
    {String? query, bool findFirst = false, Map<int, String?>? replace}) async {
  await MyApp.showProgress(autoComplete: false, limit: filesList.length);
  // Have a small delay in case there is no large computation to use as time buffer
  await Future.delayed(const Duration(milliseconds: 300), () {});

  // Reset Gallery
  if (replace == null) {
    if (MyApp.gallery.length() > 0) {
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
  for (filesIdx = 0; filesIdx < filesList.length; filesIdx++) {
    // Prepare data to be sent to thread
    var srcFile = filesList[filesIdx];

    Map<String, dynamic> message = {
      "f": srcFile.path,
      "height": size.height,
      "width": size.width
    };
    String rawJson = jsonEncode(message);
    String isoName = path.basename(srcFile.path);
    debugPrint(
        "srcFilePath [${srcFile.path}] :: isolate name $isoName :: rawJson -> $rawJson");

    Future<Map<String, dynamic>?> job =
        createOCRJob(srcFile, message, replace != null);
    // Subtracting the completed number by 1 in order to control the auto complete of the progress dialog
    Future processResult = job.then((result) => onEachOcrResult(result, srcFile,
        query, replace, timeElasped, filesList.length, ++completed - 1));
    isolates.add(processResult);
  }

  try {
    final joinIsolates = await Future.wait(isolates);
    await prefs.reload();
    debugPrint("Joined [ ${joinIsolates.length} ] isolates");
  } on Exception catch (e) {
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
    MyApp.pr.close(delay: 500);
    debugPrint(">>> getting in.");
  }
}

Future<Map<String, dynamic>?> createThread(Map<String, dynamic> rawJson) {
  return flutterCompute(ocrThread, rawJson);
}

typedef FunctionType<T> = Future<Map<String, dynamic>?> Function(T);
Function(Future<Map<String, dynamic>>) createThread_<T>(
    FunctionType<Map<String, dynamic>> function) {
  return (Future<Map<String, dynamic>> rawJson) {
    // return flutterCompute(function, rawJson);
  };
}

Future<Map<String, dynamic>?> createOCRJob(
    dynamic srcFile, Map<String, dynamic> rawJson, bool replacing) async {
  debugPrint("Entering createOCRJob()...");

  String key = getKeyOfFilename(srcFile.path);
  bool useChatGPT = true;

  var result;
  rawJson["replacing"] = replacing;
  Map<String, dynamic>? originalValues =
      await StorageUtils.get(key, asMap: true, reload: true);

  // Check if this file's' OCR has been cached
  if (originalValues is Map && !replacing) {
    debugPrint(
        "This file[$key]'s result has been cached. Skipping OCR threading and directly processing result.");
    result = originalValues;
  } else {
    if (useChatGPT) {
      result = ChatGPTService.processImage(imageFile: File(srcFile.path))
          .then((onValue) async {
        debugPrint(json.encode(onValue));
        originalValues = originalValues ?? {};

        // Avoid overriding sensitive info
        if (originalValues?[SubKeys.Location] != null &&
            onValue?[SubKeys.Location] != null) {
          onValue?.remove(SubKeys.Location);
        }

        // Validate timezone identifier
        if (onValue?[SubKeys.Location] is Map) {
          try {
            tz.getLocation(onValue?[SubKeys.Location]["timezone"]); // Replace with real mapping logic
          } catch (e) {
            print("❌ Failed to validate time zone: ${onValue?[SubKeys.Location]["timezone"]}");
            throw("❌ Message: $e");
          }
        }

        if (originalValues?[SubKeys.Sections] != null &&
            onValue?[SubKeys.Sections] != null) {
          List<Map<String, String>> originalSections =
              (originalValues?[SubKeys.Sections] as List)
                  .map((item) => Map<String, String>.from(item as Map))
                  .toList();
          List<Map<String, String>> newSections = (onValue?[SubKeys.Sections] as List)
              .map((item) => Map<String, String>.from(item as Map))
              .toList();

          for (var newSection in newSections) {
            originalSections.removeWhere((originalSection) =>
                originalSection["title"] == newSection["title"]);
          }

          newSections.addAll(originalSections);
          onValue?[SubKeys.Sections].addAll(originalSections);
        }

        originalValues!.addAll(onValue ?? {});
        await StorageUtils.save(key, asMap: originalValues, backup: replacing);

        // Reload storage for this thread
        await StorageUtils.get("", reload: true);
        return originalValues;
      });
    } else {
      Future<Map<String, dynamic>?> Function(Map<String, dynamic>) funct =
          replacing ? ocrThread : createThread;
      result = funct(rawJson);
    }
  }

  debugPrint("Leaving createOCRJob()...");
  return result;
}

void increaseProgressBar(int completed, int pathsLength) {
  int update = (completed + 1) * 100 ~/ pathsLength;
  update = update.clamp(0, 100);
  print("Increasing... " + update.toString());
  MyApp.pr.update(value: completed, msg: "Loading...");
}

Map<String, dynamic> postProcessOCR(String ocr) {
  Map<String, dynamic> map = StorageUtils.convertValueToMap(ocr, enforceMapOutput: true)!;
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
Future<Map<String, dynamic>?> ocrThread(Map<String, dynamic> receivedData) async {
  String filePath = receivedData["f"];
  ui.Size size = ui.Size(
      receivedData['width'].toDouble(), receivedData['height'].toDouble());
  bool replacing = receivedData["replacing"];
  String key = getKeyOfFilename(filePath);
  debugPrint("Spawning new iso for [$key]....");

  debugPrint("Running thread for >> $filePath");

  Map<String, dynamic> result = {};
  try {
    result = await extractProfileData(filePath, size: size, crop: !replacing);
    // Save OCR result
    debugPrint(
        "Save OCR result of key:[$key] >> ${result[SubKeys.OCR].replaceAll("\n", " ")}");

    await StorageUtils.save(key, asMap: result, backup: replacing);

    // Reload storage for this thread
    await StorageUtils.get("", reload: true);

    // Send back result to main thread
    debugPrint("Sending OCR result...");
    return result;
  } catch (error, stackTrace) {
    debugPrint("File ($filePath) failed");
    debugPrint("$error \n $stackTrace");
    debugPrint("Leaving try-catch");
  }
  return result;
}

Future onEachOcrResult(
  Map<String, dynamic>? result,
  srcFile,
  String? query,
  Map? replace,
  timeElapsed,
  filesListLength,
  int completed,
) async {
  debugPrint("Entering onOCRResult...");
  List<Map<String, String>>? sections;

  if (result?[SubKeys.Sections] is List) {
    sections = (result?[SubKeys.Sections] as List)
        .map((item) => Map<String, String>.from(item as Map))
        .toList();
  } else {
    sections = null;
  }
  String? ocr = result?[SubKeys.OCR];
  Map<String, dynamic>? usernames = result?[SubKeys.SocialMediaHandles] ?? result;
  String snapUsername = usernames?[SubKeys.SnapUsername] as String? ?? "";
  String instaUsername = usernames?[SubKeys.InstaUsername] as String? ?? "";
  String discordUsername = usernames?[SubKeys.DiscordUsername] as String? ?? "";

  if (ocr == null && sections == null) {
    ocr = "";
  }

  final cellBody = sections ??
      [
        {"ocr": ocr!}
      ];

  // Skip this image if query word has not been found
  bool skipImage = query != null &&
      !snapUsername.toLowerCase().contains(query.toLowerCase()) &&
      !ocr!.toLowerCase().contains(query.toLowerCase());

  if (!skipImage) {
    // If query word has been found
    if (replace == null)
      MyApp.gallery.addNewCell(
          cellBody, snapUsername, srcFile, new File(srcFile.path),
          instaUsername: instaUsername, discordUsername: discordUsername);
    else {
      var pair = replace.entries.first;
      int idx = pair.key;
      MyApp.gallery.redoCell(
          cellBody, snapUsername, instaUsername, discordUsername, idx);
      // Note: scrFile will always be a File for redo and ONLY redo
      (srcFile as File).delete();
    }

    debugPrint("Elapsed: ${timeElapsed.elapsedMilliseconds}ms");
  }

  increaseProgressBar(completed, filesListLength);

  debugPrint("Leaving onOCRResult...");
}
