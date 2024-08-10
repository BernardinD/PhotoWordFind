import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:chat_gpt_sdk/chat_gpt_sdk.dart';
import 'package:flutter/foundation.dart';
import 'dart:collection';
import 'package:image/image.dart' as imglib;

class Gpt4oModel extends Gpt4OChatModel {
  Gpt4oModel() : super() {
    model = "gpt-4o";
  }
}

class Gpt4oMiniModel extends Gpt4OChatModel {
  Gpt4oMiniModel() : super() {
    model = "gpt-4o-mini";
  }
}

class ChatGPTService {
  static late OpenAI _openAI;
  static late Map<String, dynamic> systemMessage;
  static bool _initialized = false;

  static const int _maxRequestsPerMinute = 60;
  static int _currentRequestCount = 0;
  static final Queue<Map<String, dynamic>> _requestQueue = Queue();

  static void initialize() {
    _openAI = OpenAI.instance.build(
      token: "",
      baseOption: HttpSetup(
        receiveTimeout: const Duration(seconds: 60),
        connectTimeout: const Duration(seconds: 60),
      ),
    );

    systemMessage = {
      "role": 'system',
      "content": '''
Extract the social media handles, name, age, location, and text from the given Bumble profile screenshot using an OCR process optimized for handling emojis. The social media handles may include Instagram, Snapchat, Discord, or others. These handles can be denoted with shorthands like "sc", "amos", or "snap" for Snapchat and "insta" or "ig" for Instagram. The location is usually found at the bottom of the profile. Return the extracted data in JSON array format. For the text, return them broken up by their section titles and the underlying text under the "sections" field.

These handles can possibly also be denoted with emojis:
- Instagram: 📷 
- Snapchat: 👻 

Notice:
  1) The text sections are wrapped around, and that the image is a long screenshot and will need to be cropped and broken up vertically in order to clearly see all the text section, I recommend breaking up into 6 chunks.
  2) Feel free to re-combine any chunks that have the text cut off. 
  3) For debugging purposes, name all the emojis you see in the image if they exist under "emojis".

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

    final completer = Completer<Map<String, dynamic>?>();
    _requestQueue.add({
      'completer': completer,
      'imageFile': imageFile,
      'useMiniModel': useMiniModel,
      'maxRetries': maxRetries
    });

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
    final imageFile = request['imageFile'] as File;
    final useMiniModel = request['useMiniModel'] as bool;
    final maxRetries = request['maxRetries'] as int;

    try {
      final result = await _sendRequest(
        imageFile: imageFile,
        useMiniModel: useMiniModel,
        maxRetries: maxRetries,
      );
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

  static Future<Map<String, dynamic>?> _sendRequest({
    required File imageFile,
    bool useMiniModel = true,
    int maxRetries = 3,
  }) async {
    int attempt = 0;
    // List<File> chunks = _preprocessAndSplitImage(imageFile);
    List<File> chunks = [imageFile];
    List<Map<String, dynamic>> content = chunks.map((imageFileChunk) {
      final encodedImage = base64Encode(imageFileChunk.readAsBytesSync());
      return {
        "type": "image_url",
        "image_url": {"url": "data:image/jpeg;base64,$encodedImage"}
      };
    }).toList();
    while (attempt < maxRetries) {
      try {
        final imageMessage = {
          "role": 'user',
          "content": content,
        };

        final request = ChatCompleteText(
          maxToken: 2000,
          model: useMiniModel ? Gpt4oMiniModel() : Gpt4oModel(),
          messages: [systemMessage, imageMessage],
          responseFormat: ResponseFormat.jsonObject,
        );

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

  static List<File> _preprocessAndSplitImage(File imageFile) {
    // Read the image from the file
    final image = imglib.decodeImage(imageFile.readAsBytesSync());

    if (image == null) {
      throw Exception("Unable to decode image.");
    }

    // Convert the image to grayscale
    final grayscaleImage = imglib.grayscale(image);

    // Enhance contrast
    final enhancedImage = imglib.adjustColor(grayscaleImage, contrast: 1.5);

    // Split the image into smaller chunks
    final chunkHeight =
        (image.height / 4).ceil(); // Split into 4 horizontal chunks
    final chunkWidth = image.width; // Keep the full width

    List<File> chunks = [];
    for (int i = 0; i < 4; i++) {
      final chunk = imglib.copyCrop(enhancedImage,
          x: 0, y: i * chunkHeight, width: chunkWidth, height: chunkHeight);
      final chunkFile = File('${imageFile.path}_chunk_$i.jpg')
        ..writeAsBytesSync(imglib.encodeJpg(chunk));
      chunks.add(chunkFile);
    }

    return chunks;
  }
}
