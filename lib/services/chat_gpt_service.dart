import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:PhotoWordFind/apiSecretKeys.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'dart:collection';
import 'package:image/image.dart' as imglib;

/// Model classes for different ChatGPT variants
abstract class ChatGPTModel {
  String get model;
}

class Gpt4oModel extends ChatGPTModel {
  @override
  String get model => "gpt-4o-2024-08-06";
}

class Gpt4oMiniModel extends ChatGPTModel {
  @override
  String get model => "gpt-4o-mini";
}

class Gpt5NanoModel extends ChatGPTModel {
  @override
  String get model => "gpt-5-nano";
}

class ChatGPTService {
  static late String _apiKey;
  static late Map<String, dynamic> systemMessage;
  static late Map<String, dynamic> userMessage;
  static bool _initialized = false;

  static const int _maxRequestsPerMinute = 3;
  static int _currentRequestCount = 0;
  static final Queue<Map<String, dynamic>> _requestQueue = Queue();
  
  static const String _baseUrl = 'https://api.openai.com/v1';

  static void initialize() {
    _apiKey = chatGPTApiKey;

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
    bool useNanoModel = true,
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
      'useNanoModel': useNanoModel,
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
    final useNanoModel = request['useNanoModel'] as bool? ?? true;
    final maxRetries = request['maxRetries'] as int;
    int attempt = 0;
    List<Map<String, dynamic>> content;
    List<Map<String, dynamic>> messages = [];

    // Determine which model to use
    ChatGPTModel model;
    if (useNanoModel) {
      model = Gpt5NanoModel();
    } else {
      // Fall back to Mini model if Nano is not selected
      model = Gpt4oMiniModel();
    }

    // If processing image
    if (request['imageFile'] != null) {
      final imageFile = request['imageFile'] as File;

      List<File> chunks = [imageFile];
      content = chunks.map((imageFileChunk) {
        final encodedImage = base64Encode(imageFileChunk.readAsBytesSync());
        return {
          "type": "image_url",
          "image_url": {"url": "data:image/jpeg;base64,$encodedImage"}
        };
      }).toList();

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
        // Use responses endpoint instead of chat completions
        final response = await _makeResponsesRequest(
          model: model.model,
          messages: messages,
          maxTokens: 2000,
          temperature: 1.0,
          responseFormat: 'json_object',
        );

        if (response != null) {
          return response;
        }
        return null;
      } catch (e) {
        debugPrint("OpenAI API Error: ${e.toString()}");
        
        // Handle specific error types
        if (e.toString().contains('rate_limit') || 
            e.toString().contains('token_limit')) {
          debugPrint("Retrying... (Attempt ${attempt + 1} of $maxRetries)");
          attempt++;
          await Future.delayed(Duration(seconds: 2));
        } else {
          debugPrint("An unknown error occurred: ${e.toString()}");
          return null;
        }
      }
    }

    debugPrint("Max retry attempts reached. Request failed.");
    return null;
  }

  /// Makes a request to the OpenAI responses endpoint
  static Future<Map<String, dynamic>?> _makeResponsesRequest({
    required String model,
    required List<Map<String, dynamic>> messages,
    required int maxTokens,
    required double temperature,
    required String responseFormat,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/responses');
      
      final requestBody = {
        'model': model,
        'messages': messages,
        'max_tokens': maxTokens,
        'temperature': temperature,
        'response_format': {'type': responseFormat},
      };

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: json.encode(requestBody),
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body) as Map<String, dynamic>;
        
        // Extract content from responses API format
        if (responseData['choices'] != null && 
            responseData['choices'].isNotEmpty) {
          final content = responseData['choices'][0]['message']['content'];
          if (content != null) {
            return json.decode(content);
          }
        }
        
        debugPrint("Error: No content found in response");
        return null;
      } else {
        final errorData = json.decode(response.body);
        debugPrint("API Error ${response.statusCode}: ${errorData['error']['message']}");
        throw Exception("API Error: ${errorData['error']['message']}");
      }
    } catch (e) {
      debugPrint("HTTP request failed: ${e.toString()}");
      rethrow;
    }
  }

  /// This function has mostly just been used for testing.
  static Future<List<Map<String, dynamic>?>> processMultipleImages({
    required List<File> imageFiles,
    bool useNanoModel = true,
  }) async {
    if (!_initialized) {
      throw Exception(
          "ChatGPTService not initialized. Call initialize() first.");
    }

    List<Future<Map<String, dynamic>?>> tasks = imageFiles
        .map((imageFile) =>
            processImage(imageFile: imageFile, useNanoModel: useNanoModel))
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
        'useNanoModel': true,
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
