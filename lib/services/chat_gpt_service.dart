import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:PhotoWordFind/apiSecretKeys.dart';
import 'package:chat_gpt_sdk/chat_gpt_sdk.dart';
import 'package:flutter/foundation.dart';
import 'dart:collection';
import 'package:image/image.dart' as imglib;

class Gpt4oModel extends Gpt4OChatModel {
  Gpt4oModel() : super() {
    model = "gpt-4o-2024-08-06";
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

  // Removed unused test system message block

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
  final chatRequest = ChatCompleteText(
            maxToken: 2000,
            model: useMiniModel ? Gpt4oMiniModel() : Gpt4oModel(),
            messages: messages,
            responseFormat: ResponseFormat.jsonObject,
            temperature: 1);

  final response = await _openAI.onChatCompletion(request: chatRequest);

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
      } on OpenAIRateLimitError catch (e) {
        // Too many requests to OpenAI – exponential backoff with jitter
        attempt++;
        final delaySeconds = min(32, pow(2, attempt).toInt());
        debugPrint(
            "Rate limit hit (attempt $attempt/$maxRetries). Backing off ${delaySeconds}s. Details: ${e.data}");
        await Future.delayed(Duration(seconds: delaySeconds + Random().nextInt(1)));
        continue;
      } on OpenAIAuthError catch (e) {
        // Invalid API key or org – don't retry
        debugPrint("Auth error: ${e.data ?? 'Invalid authentication'}");
        return null;
      } on OpenAIServerError catch (e) {
        // Transient server error – retry with backoff
        attempt++;
        final delaySeconds = min(16, pow(2, attempt).toInt());
        debugPrint(
            "Server error (attempt $attempt/$maxRetries). Retrying in ${delaySeconds}s. Details: ${e.data}");
        await Future.delayed(Duration(seconds: delaySeconds));
        continue;
      } on RequestError catch (e) {
        // Fallback when SDK throws generic wrapper with an HTTP status code
        final int code = (e.code is int) ? (e.code as int) : -1;
        debugPrint("OpenAI RequestError: code=$code, data=${e.data}");
        if (code == 429) {
          // Rate limit
          attempt++;
          final delaySeconds = min(32, pow(2, attempt).toInt());
          debugPrint(
              "Retrying after 429 rate limit (attempt $attempt/$maxRetries) in ${delaySeconds}s");
          await Future.delayed(Duration(seconds: delaySeconds));
          continue;
        } else if (code == 401 || code == 403) {
          // Auth error
          debugPrint("Auth error ($code): ${e.data ?? 'Invalid API key/organization'}");
          return null;
        } else if (code == 413) {
          // Payload too large / token limit like constraint
          attempt++;
          final delaySeconds = min(16, pow(2, attempt).toInt());
          debugPrint("Payload too large (413). Retrying in ${delaySeconds}s");
          await Future.delayed(Duration(seconds: delaySeconds));
          continue;
        } else if (<int>[500, 502, 503, 504].contains(code)) {
          // Server/transient
          attempt++;
          final delaySeconds = min(16, pow(2, attempt).toInt());
          debugPrint("Server/transient error $code. Retrying in ${delaySeconds}s");
          await Future.delayed(Duration(seconds: delaySeconds));
          continue;
        } else {
          // Unknown; don't loop forever
          return null;
        }
      } on TimeoutException catch (e) {
        attempt++;
        final delaySeconds = min(8, pow(2, attempt).toInt());
        debugPrint(
            "Timeout (attempt $attempt/$maxRetries). Retrying in ${delaySeconds}s. ${e.message ?? ''}");
        await Future.delayed(Duration(seconds: delaySeconds));
        continue;
      } on SocketException catch (e) {
        attempt++;
        final delaySeconds = min(8, pow(2, attempt).toInt());
        debugPrint(
            "Network error (attempt $attempt/$maxRetries). Retrying in ${delaySeconds}s. ${e.message}");
        await Future.delayed(Duration(seconds: delaySeconds));
        continue;
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
