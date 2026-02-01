// TODO: remove this file once testing is complete
// NOTE: This file is deprecated and uses the old chat_gpt_sdk 
// The new implementation is in services/chat_gpt_service.dart

import 'dart:io';

/// Deprecated class - use ChatGPTService models instead
@Deprecated('Use ChatGPTService with Gpt5NanoModel, Gpt4oModel, or Gpt4oMiniModel')
class MyModelChoice {
  String model = "gpt-4o";
}

/// Deprecated function - use ChatGPTService.processMultipleImages instead
@Deprecated('Use ChatGPTService.processMultipleImages instead')
Future<dynamic> sendImagesToChatGPT(List<File> images) async {
  throw UnimplementedError(
    'This function is deprecated. Use ChatGPTService.processMultipleImages instead.'
  );
}

/// Deprecated function - use ChatGPTService._makeResponsesRequest instead
@Deprecated('Use ChatGPTService._makeResponsesRequest instead')
Future<dynamic> sendChatGPTImagesRequest(
    List<Map<String, dynamic>> messages,
    {int timeoutOffest = 0}) async {
  throw UnimplementedError(
    'This function is deprecated. Use ChatGPTService._makeResponsesRequest instead.'
  );
}
