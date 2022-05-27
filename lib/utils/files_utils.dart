
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:PhotoWordFind/main.dart';
import 'package:flutter/widgets.dart';
import 'package:isolate_handler/isolate_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';


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
  final prefs = await SharedPreferences.getInstance();

  for(path_idx = 0; path_idx < paths.length; path_idx++){


    // Prepare data to be sent to thread
    var src_filePath = paths[path_idx];

    Map<String, dynamic> message = {
      "f": src_filePath.path,
      "height": size.height,
      "width" : size.width
    };
    String rawJson = jsonEncode(message);
    final Map<String, dynamic> data = json.decode(rawJson);
    String iso_name = src_filePath.path.split("/").last;

    // Define callback
    Function onReceive = (dynamic signal) {
      if(signal is String){
        String text = signal;
        // If query word has been found
        String suggestedUsername = post(text, query);
        if(suggestedUsername != null) {

          if(replace == null)
            MyApp.gallery.addNewCell(text, suggestedUsername, src_filePath, new File(src_filePath.path));
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

      }
      else{
        // Dispose of finished isolate
        isolates.kill(iso_name, priority: Isolate.immediate);
      }

      debugPrint("before `completed`... $completed <= ${paths.length}");
      debugPrint("before `path_idx`... $path_idx <= ${paths.length}");


      // Increase progress bar
      int update = (completed+1)*100~/paths.length;
      update = update.clamp(0, 100);
      print("Increasing... " + update.toString());
      MyApp.pr.update(maxProgress: 100.0, progress: update/1.0);

      // Close dialogs once finished with all images
      if(++completed >= paths.length){
        // Terminate running isolates
        List names = isolates.isolates.keys.toList();
        for(String name in names){
          // Don't kill current thread
          if(name == iso_name) continue;

          debugPrint("iso-name: ${name}");
          if(isolates.isolates[name].messenger.connectionEstablished ) {
            try {
              isolates.kill(name, priority: Isolate.immediate);
            }
            catch(e){
              debugPrint("pass kill error");
            }
          }
        }
        debugPrint("popping...");

        // Quick fix for this callback being called twice
        // TODO: Find way to stop isolates immediately so they don't get to this point
        if(MyApp.pr.isShowing()) {
          MyApp.pr.hide().then((value) {
            // setState(() => {});
            MyApp.updateFrame(() => {});
            debugPrint(">>> getting in.");
          });
        }
      }
    };

    List<String> split = getFileNameAndExtension(src_filePath.path);
    String key = generateKeyFromFilename(src_filePath.path);
    bool replacing = split.length == 3;

    if(replacing) {
      prefs.remove(key);
    }

    if(prefs.getString(key) != null){
      String result = prefs.getString(key);
      onReceive(result);
    }
    else {
      // Start up the thread and configures the callbacks
      debugPrint("spawning new iso....");
      isolates.spawn<String>(
          threadFunction,
          name: iso_name,
          onInitialized: () => isolates.send(rawJson, to: iso_name),
          onReceive: (dynamic signal) => onReceive(signal));
    }

  }
}


// Runs the `find` operation in a Isolate thread
void threadFunction(Map<String, dynamic> context) {

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

      List<String> split = getFileNameAndExtension(f);
      String key = generateKeyFromFilename(f);
      bool replacing = split.length == 3;

      if(replacing) {
        prefs.remove(key);
      }

      runOCR(f, size, crop: !replacing ).then((result) {
        if (result is String) {
          // Save OCR result
          prefs.setString(key, result);
          // Send back result to main thread
          messenger.send(result);
        }
      });
    }
    else{
      debugPrint("did NOT detect string...");
      messenger.send(null);
    }

  });

}