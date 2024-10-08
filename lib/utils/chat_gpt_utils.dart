// TODO: remove this file once testing is complete

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
    // model = "gpt-4o-mini";
    model = "gpt-4o";
  }
}

Future<ChatCTResponse?> sendImagesToChatGPT(List<File> images) async {
  List<Map<String, dynamic>> messages = [];

  messages.add(Map.of({
    "role": "system",
    "content":
        "You are a useful assistant, capable of pulling social media handles, names, age, and locations from screenshots of Bumble profiles. Especially handle denoted by emojis."
  }));

  var discordEmoji = "- Discord: 🕹️";
  List<Map<String, dynamic>> content = [
    {
      "type": "text",
      "text": '''
Extract the social media handles, name, age, and location from the given Bumble profile screenshot. The social media handles may include Instagram, Snapchat, Discord, or others. These handles can be denoted with shorthands like "sc" or "snap" for Snapchat and "insta" or "ig" for Instagram. The location is usually found at the bottom of the profile. Return the extracted data in JSON array format.

These handles can possibly also be denoted with emojis:
- Instagram: 📷 
- Snapchat: 👻 

Notice that the text sections are wrapped around. And for debugging purposes, name all the emojis you see in the image if that exist under "emojis".

[
  {
    "name": "<their name>",
    "age": <age>,
    "social_media_handles": {
      "Instagram": "<instagram handle>",
      "Snapchat": "<snapchat handle>",
      "Discord": "<discord handle>"
    },
    "location": "<location>",
    "emojis": []
  }
]
'''
    }
  ];

  for (var image in images) {
    var imageBytes = image.readAsBytesSync();
    String base64String = base64Encode(imageBytes);
    content.add({
      "type": "image_url",
      "image_url": {"url": "data:image/jpeg;base64," + base64String}
    });
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

Future<ChatCTResponse?> sendChatGPTImagesRequest(
    List<Map<String, dynamic>> messages,
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
