import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:PhotoWordFind/apiSecretKeys.dart';
import 'package:PhotoWordFind/utils/image_slicer.dart';
import 'package:chat_gpt_sdk/chat_gpt_sdk.dart';
import 'package:flutter/foundation.dart';
import 'dart:collection';

class Gpt41Model extends Gpt4OChatModel {
  Gpt41Model() : super() {
    model = "gpt-4.1";
  }
}

class Gpt41MiniModel extends Gpt4OChatModel {
  Gpt41MiniModel() : super() {
    model = "gpt-4.1-mini";
  }
}

class ChatGPTService {
  static late OpenAI _openAI;
  static late Map<String, dynamic> systemMessage;
  static late Map<String, dynamic> userMessage;
  static bool _initialized = false;

  static const int _maxRequestsPerMinute = 3;
  static int _currentRequestCount = 0;
  static final Queue<Map<String, dynamic>> _requestQueue = Queue();

  static void initialize() {
    _openAI = OpenAI.instance.build(
      token: chatGPTApiKey,
      baseOption: HttpSetup(
        receiveTimeout: const Duration(seconds: 60),
        connectTimeout: const Duration(seconds: 60),
      ),
    );

    systemMessage = {
      "role": 'system',
      "content": '''
You are an experienced Bumble  user who is viewing Bumble profiles, reading important information from the profile, including symbols, like emojis
You know not to ignore the images  and focus on the written content in the profile.
You will be finding the name, age, social media handles, location, time zone (IANA zone ID) of the location, UTF offset of the location, text from each cropped out section of the image. And you will be sharing this infomation in JSON format.

Return format:
[
  {
    "name": "<their name>",
    "age": <age>,
    "social_media_handles": {
      "insta": "<instagram handle>",
      "snap": "<snapchat handle>",
      "discord": "<discord handle>"
    },
    "location": {"name": "<location>", "timezone": "<IANA tz zone ID>", "utc-offset": +/- <offset>},
    "sections": [
      {
        "title": "<section title>",
        "text": "<text in section>"
      }
    ],
    "emojis": [],
    "summary" <list of steps you took while processing the image>
  }
]
'''
    };

    // TODO: Remove this after testing
    Map<String, dynamic> userMessage_ = {
      "role": 'system',
      "content": '''
Extract the social media handles, name, age, location, and text from the given Bumble profile screenshot using an text retrieval process optimized for handling emojis.
The social media handles may include Instagram, Snapchat, Discord, or others. These handles can be denoted with shorthands like "sc", "amos", or "snap" for Snapchat and "insta" or "ig" for Instagram. The location is usually found at the bottom of the profile. Return the extracted data in JSON array format. For the text, return them broken up by their section titles and the underlying text under the "sections" field.

These handles can possibly also be denoted with emojis:
- Instagram: 📷 
- Snapchat: 👻 

Notice:
  1) The text sections are wrapped around, and can have emojis, and that the image is a long screenshot and will need to be cropped and broken up vertically in order to clearly see all the text section
  2) I recommend cropping into squares with the dimensions of the width of the image.
  3) Feel free to re-combine any chunks that have the text cut off. 
  4) For debugging purposes, name all the emojis you see in the image if they exist under "emojis".

[
  {
    "name": "<their name>",
    "age": <age>,
    "social_media_handles": {
      "insta": "<instagram handle>",
      "snap": "<snapchat handle>",
      "discord": "<discord handle>"
    },
    "location": "<location>",
    "sections": [
      {
        "title": "<section title>",
        "text": "<text in section>"
      }
    ],
    "emojis": []
  }
]
'''
    };

    _initialized = true;
    _startResetCounterTimer();
  }

  static Future<Map<String, dynamic>?> processImage({
    required File imageFile,
    bool useMiniModel = true,
    int maxRetries = 3,
  }) async {
    if (!_initialized) {
      throw Exception(
          "ChatGPTService not initialized. Call initialize() first.");
    }

    userMessage = {
      "role": 'system',
      "content": '''
Keep the information below in mind:
- The words/sentences are text wrapped.
- The social media handles you will be focusing on are Snapchat, Instagram, and Discord.
- Handles can be denoted by abbreviates like "sc", "amos", "snap", "insta", "ig", etc. so pay attention for creative denotions
- Handles can also be denoted by the 👻 emoji for Snapchat and 📷 emoji for Instagram.
- Make sure handles are labled under "social_media_handles"
- Make sure the bio section has the key "My bio" (the bio will be specfically labled)
- For debugging purposes, name all the emojis you see in the image if they exist under "emojis"
- For any values that aren't present, like location, don't include in the output, DO NOT make them empty strings
- Location will only be a the bottom of the image
- If at the end of the process there is an obvious handle and it wasn't associated with any social media platform, assume that it applies to both Snapchat and Instagram (e.g. if it's only denoted by a "@").
'''
    };

    Map<String, dynamic> request = {
      'imageFile': imageFile,
      'useMiniModel': useMiniModel,
      'maxRetries': maxRetries
    };

    return addToQueue(request);
  }

  static Future<Map<String, dynamic>?> addToQueue(
      Map<String, dynamic> request) {
    final completer = Completer<Map<String, dynamic>?>();

    request['completer'] = completer;
    _requestQueue.add(request);

    if (_currentRequestCount < _maxRequestsPerMinute) {
      _currentRequestCount++;
      _handleRequestQueue();
    }

    return completer.future;
  }

  static void _handleRequestQueue() async {
    if (_requestQueue.isEmpty) return;

    final request = _requestQueue.removeFirst();
    final completer = request['completer'] as Completer<Map<String, dynamic>?>;

    try {
      final result = await _sendRequest(request);
      completer.complete(result);
    } catch (error) {
      completer.completeError(error);
    } finally {
      _currentRequestCount--;
      if (_currentRequestCount < _maxRequestsPerMinute) {
        _handleRequestQueue();
      }
    }
  }

  static Future<Map<String, dynamic>?> _sendRequest(
      Map<String, dynamic> request) async {
    final useMiniModel = request['useMiniModel'] as bool;
    final maxRetries = request['maxRetries'] as int;
    int attempt = 0;
    List<Map<String, dynamic>> content;
    List<Map<String, dynamic>> messages = [];

    // If processing image
    if (request['imageFile'] != null) {
      final imageFile = request['imageFile'] as File;
      List<File> chunks;
      try {
        chunks = await _sliceImageOffMainThread(imageFile);
      } catch (e) {
        debugPrint(
            "Falling back to original image after preprocessing failed: $e");
        chunks = [imageFile];
      }

      content = chunks.map((imageFileChunk) {
        final encodedImage = base64Encode(imageFileChunk.readAsBytesSync());
        return {
          "type": "image_url",
          "image_url": {"url": "data:image/jpeg;base64,$encodedImage"}
        };
      }).toList();

      for (final chunk in chunks) {
        if (chunk.path != imageFile.path && chunk.existsSync()) {
          try {
            chunk.deleteSync();
          } catch (_) {}
        }
      }

      final imageMessage = {
        "role": 'user',
        "content": content,
      };

      messages = [systemMessage, userMessage, imageMessage];
    }
    // Processing text
    else {
      String prompt = request['prompt'];
      messages = [
        {"role": "user", "content": prompt}
      ];
    }

    while (attempt < maxRetries) {
      try {
        final request = ChatCompleteText(
            maxToken: 2000,
            model: useMiniModel ? Gpt41MiniModel() : Gpt41Model(),
            messages: messages,
            responseFormat: ResponseFormat.jsonObject,
            temperature: 1);

        final response = await _openAI.onChatCompletion(request: request);

        if (response != null && response.choices.isNotEmpty) {
          final result = response.choices.first.message?.content;
          if (result != null) {
            return json.decode(result);
          } else {
            debugPrint("Error: The content of the response is null.");
            return null;
          }
        }
        return null;
      } on RequestError catch (e) {
        debugPrint("OpenAIError: ${e.data}");
        // Handle specific OpenAI errors
        switch (e.code) {
          case 'token_limit_exceeded':
          case 'rate_limit_exceeded':
            debugPrint("Retrying... (Attempt ${attempt + 1} of $maxRetries)");
            attempt++;
            await Future.delayed(
                Duration(seconds: 2)); // Optional: delay between retries
            break;
          default:
            debugPrint("An unknown error occurred");
            return null;
        }
      } catch (e) {
        debugPrint("General error: ${e.toString()}");
        return null;
      }
    }

    debugPrint("Max retry attempts reached. Request failed.");
    return null;
  }

  /// This function has mostly just been used for testing.
  static Future<List<Map<String, dynamic>?>> processMultipleImages({
    required List<File> imageFiles,
    bool useMiniModel = true,
  }) async {
    if (!_initialized) {
      throw Exception(
          "ChatGPTService not initialized. Call initialize() first.");
    }

    List<Future<Map<String, dynamic>?>> tasks = imageFiles
        .map((imageFile) =>
            processImage(imageFile: imageFile, useMiniModel: useMiniModel))
        .toList();
    return await Future.wait(tasks);
  }

  static void _startResetCounterTimer() {
    Timer.periodic(Duration(minutes: 1), (timer) {
      _currentRequestCount = 0;
      _handleRequestQueue();
    });
  }

  /// 🌍 Fetches new location details using ChatGPT
  static Future<Map<String, dynamic>?> fetchUpdatedLocationFromChatGPT(
      String locationName) async {
    try {
      // 🔹 Send a request to ChatGPT with the updated prompt
      String prompt = '''
      Given the location "$locationName", return a JSON object containing:
      - "name": Full name of the location
      - "timezone": IANA time zone ID
      - "utc-offset": The UTC offset (hours)

      Example response:
      {
        "name": "Los Angeles, USA",
        "timezone": "America/Los_Angeles",
        "utc-offset": -8
      }
    ''';

      Map<String, dynamic> request = {
        'prompt': prompt,
        'useMiniModel': true,
        'maxRetries': 3
      };

      // 🔹 Send the request to ChatGPT
      Map<String, dynamic>? response = await ChatGPTService.addToQueue(request);

      return response;
    } catch (e) {
      print("❌ Error fetching location data from ChatGPT: $e");
    }

    return null; // 🔹 Return null if ChatGPT request fails
  }
}

class _SliceRequest {
  final String path;
  final double overlapRatio;
  const _SliceRequest(this.path, this.overlapRatio);
}

Future<List<File>> _sliceImageOffMainThread(File imageFile,
    {double overlapRatio = 0.25}) async {
  final chunkPaths = await compute<_SliceRequest, List<String>>(
    _sliceImageWorker,
    _SliceRequest(imageFile.path, overlapRatio),
  );
  return chunkPaths.map((p) => File(p)).toList();
}

List<String> _sliceImageWorker(_SliceRequest request) {
  final file = File(request.path);
  final chunks = sliceImageIntoOverlappingSquares(
    file,
    overlapRatio: request.overlapRatio,
  );
  return [
    for (final chunk in chunks) chunk.path,
  ];
}
