import 'dart:io';
import 'dart:convert';

import 'package:chat_gpt_sdk/chat_gpt_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image/image.dart' as imglib;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class MyModelChoice extends GptTurbo0631Model {
  MyModelChoice() : super() {
    model = "gpt-4o-mini";
  }
}

Future<ChatCTResponse?> sendImagesToChatGPT(List<File> images) async {
  List<Map<String, dynamic>> messages = [];

  messages.add(Map.of({
      "role": "system",
      "content":
          "You are a useful assistant, capable of pulling social media handles and locations from screenshots of Bumble profiles."}));

  List<Map<String, dynamic>> content = [
    {
      "type": "text",
      "text": '''
Extract the social media handles and location from the given Bumble profile screenshot. The social media handles may include Instagram, Snapchat, Discord, or others, and can be denoted with emojis (e.g., 📷 for Instagram, 👻 for Snapchat, 🕹️ for Discord). 
The location is usually found at the bottom of the profile. If you're not able to see any of those things tell me what you think the image is instead as well as what you do see and the name towards the top, under "other". Return the extracted data in JSON array format.

[
  {
    "social_media_handle": {
      "Instagram": "",
      "Snapchat": "",
      "Discord": ""
    },
    "location": ""
    "other": ""
  }
]
'''
    }
  ];
  
  List<Future<File?>> preprocessedImages = images.map(scaleDownImage).toList();
  Future.wait(preprocessedImages);
  for (var imageFuture in preprocessedImages) {
    File? image = await imageFuture;
    if (image == null) continue;

    var imageBytes = image.readAsBytesSync(); //encodeImageJpg(image);
    String base64String = base64Encode(imageBytes);
    content.add({
      "type": "image_url",
      "image_url": {"url": "data:image/jpeg;base64," + base64String}
    });

    // Save the base64 string to a file
    File base64File = File('/storage/emulated/0/Documents/base64_image.txt');
    await base64File.writeAsString(base64String);
    debugPrint("base64 path: ${base64File.parent}");
  }

  String jsonContent = json.encode(content);
  // Save the base64 string to a file
  File base64File = File('/storage/emulated/0/Documents/content.json');
  await base64File.writeAsString(jsonContent);
  debugPrint("base64 path: ${base64File.parent}");
  messages.add(Map.of({"role": "user", "content": content}));

  ChatCTResponse? response;
  RequestError? error;
  int countOut = 3;
  bool retry = false;
  do {
    try {
      retry = false;
      response =
          await sendChatGPTImagesRequest(messages, timeoutOffest: 3 - countOut);
    } on RequestError catch (e) {
      error = e;
      if (error.code != null) {
        debugPrint(error.data?.message);
      }
      countOut--;
    } on OpenAIServerError catch (e) {
      retry = true;
      countOut--;
      debugPrint("caught new error: $e");
    }
  } while (retry ||
      (error != null &&
          error.code == null &&
          error.code != 400 &&
          countOut > 0));

  if (response == null) {
    debugPrint(
        "Couldn't send request. Will save receipts done up to this point. Ending now.");
    return null;
  }

  /*
  Concat. chatGPT response message and convert to single json list
    */
  String message = "";
  // Note: Assuming this loop runs messages.length times
  for (var element in response.choices) {
    message += " ${element.message?.content}";
  }

  String chatGPTResponseStr =
      message.substring(message.indexOf('['), message.lastIndexOf(']') + 1);
  List? chatGPTResponseList;
  try {
    chatGPTResponseList = json.decode(chatGPTResponseStr) as List;
  } on FormatException catch (e) {
    throw ("Couldn't decode message: \n\n-----------\n$chatGPTResponseStr\n${e.message}");
  }

  debugPrint("Response: $chatGPTResponseList");

  return response;
}

Future<ChatCTResponse?> sendChatGPTImagesRequest(List<Map<String, dynamic>> messages,
    {int timeoutOffest = 0}) async {
  final openAI = OpenAI.instance.build(
      // token: dotenv.env['CHAT_GPT_KEY'],
      token: "",
      baseOption: HttpSetup(
          receiveTimeout: Duration(seconds: 120 + timeoutOffest * 20)),
      enableLog: true);
  final request = ChatCompleteText(
      messages: messages, maxToken: 2000, model: MyModelChoice());

  ChatCTResponse? response;
  RequestError? error;
  int countOut = 3;
  do {
    try {
      response = await openAI.onChatCompletion(request: request);
    } on RequestError catch (e) {
      error = e;
      if (error.code != 503 && error.code != 429 && error.code != 400) {
        rethrow;
      }
      countOut--;
    }
  } while (error != null &&
      error.code == 503 &&
      error.code != 429 &&
      error.code != 400 &&
      countOut > 0);

  return response!;
}

Uint8List encodeImageJpg(imglib.Image image) {
  return imglib.encodeJpg(image, quality: 60);
}

Future<File?> scaleDownImage(File originalImage) async {
  imglib.Image? inputImage = await imglib.decodeImageFile(originalImage.path);

  if (inputImage == null) {
    print('Failed to decode image');
    return null;
  }

  double scale = 0.45;
  imglib.Command? cmd = imglib.Command()
        ..image(inputImage)
        ..copyResize(
            width: (inputImage.width * scale).round(),
            height: (inputImage.height * scale).round())
      ..grayscale()
      ;

  imglib.Image? image = await cmd.getImage();
  final tempDir = await getExternalStorageDirectory();
  DateTime now = DateTime.now();
  String tempPath = path.join(
      tempDir!.path, 'temp_receipts', '${now.microsecondsSinceEpoch}.jpg');
  await imglib.writeFile(tempPath, encodeImageJpg(image!));
  File file = File(tempPath);
  debugPrint("exists: ${file.existsSync()} | $tempPath");

  String base64String = base64Encode(encodeImageJpg(image));

  // Save the base64 string to a file
  File base64File = File(
      '/storage/emulated/0/Documents/base64_image_${path.basenameWithoutExtension(originalImage.path)}.txt');
  await base64File.writeAsString(base64String);
  debugPrint("base64 path: ${base64File.parent}");

  return file;
}
