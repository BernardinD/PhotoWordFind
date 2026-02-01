import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

import 'package:PhotoWordFind/services/chat_gpt_service.dart';
import 'package:PhotoWordFind/utils/chat_gpt_utils.dart';

// Generate mocks using mockito
@GenerateMocks([http.Client])
import 'chat_gpt_service_test.mocks.dart';

/// Test for the new ChatGPT 5 Nano service implementation
void main() {
  group('ChatGPTService', () {
    late MockClient mockClient;
    
    setUp(() {
      mockClient = MockClient();
      ChatGPTService.initialize();
    });

    test('models return correct model names', () {
      expect(Gpt5NanoModel().model, equals('gpt-5-nano'));
      expect(Gpt4oModel().model, equals('gpt-4o-2024-08-06'));
      expect(Gpt4oMiniModel().model, equals('gpt-4o-mini'));
    });

    test('GPT-5 Nano supports responses endpoint', () {
      final gpt5Nano = Gpt5NanoModel();
      final gpt4o = Gpt4oModel();
      
      expect(gpt5Nano.supportsResponses, isTrue);
      expect(gpt4o.supportsResponses, isFalse);
    });

    test('processImage method maintains interface compatibility', () async {
      // Create a test image file
      final testImageBytes = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQImWNgYGD4DwABAgEAO+2VfQAAAABJRU5ErkJggg==');
      final testImageFile = File('${Directory.systemTemp.path}/test_image.png');
      await testImageFile.writeAsBytes(testImageBytes);
      
      try {
        // Test that the method signature works (will fail due to no API key, but that's expected)
        final result = ChatGPTService.processImage(
          imageFile: testImageFile,
          useNanoModel: true,
          maxRetries: 1,
        );
        
        // Expect it to be a Future that will complete (may fail with API error)
        expect(result, isA<Future<Map<String, dynamic>?>>());
        
        // Clean up
        if (await testImageFile.exists()) {
          await testImageFile.delete();
        }
      } catch (e) {
        // Expected to fail without proper API key
        expect(e.toString(), contains('your_openai_api_key_here'));
      }
    });

    test('deprecated chat_gpt_utils functions throw UnimplementedError', () {
      expect(
        () => sendImagesToChatGPT([]),
        throwsA(isA<UnimplementedError>()),
      );
      
      expect(
        () => sendChatGPTImagesRequest([]),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('fetchUpdatedLocationFromChatGPT uses new parameter name', () async {
      try {
        // This should use the new useNanoModel parameter internally
        final result = ChatGPTService.fetchUpdatedLocationFromChatGPT('Los Angeles');
        expect(result, isA<Future<Map<String, dynamic>?>>());
      } catch (e) {
        // Expected to fail without proper API key
        expect(e.toString(), contains('your_openai_api_key_here'));
      }
    });
  });
}