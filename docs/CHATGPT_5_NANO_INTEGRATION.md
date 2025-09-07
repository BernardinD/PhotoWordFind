# ChatGPT 5 Nano Integration

This document describes the changes made to integrate ChatGPT 5 Nano model with the new responses API.

## Changes Made

### 1. Dependency Updates
- **Removed**: `chat_gpt_sdk: ^3.0.3` 
- **Added**: `http: ^1.1.0` for direct REST API calls

### 2. New Model Classes
- `Gpt5NanoModel`: Uses the new responses API endpoint
- `Gpt4oModel` and `Gpt4oMiniModel`: Updated to work with new architecture
- All models implement the `ChatGPTModel` abstract class

### 3. API Endpoint Changes
- **Primary**: Uses `/responses` endpoint for GPT-5 Nano model
- **Fallback**: Automatically falls back to `/chat/completions` for other models or if responses endpoint fails
- **Error Handling**: Robust error handling with retry logic for rate limits and timeouts

### 4. Interface Compatibility
- `processImage()` method signature maintained, but now uses `useNanoModel` parameter instead of `useMiniModel`
- `processMultipleImages()` updated accordingly
- `fetchUpdatedLocationFromChatGPT()` now uses GPT-5 Nano by default

### 5. Deprecated Files
- `lib/utils/chat_gpt_utils.dart` marked as deprecated with proper deprecation annotations
- Functions throw `UnimplementedError` to guide developers to new implementation

## Usage

### Basic Image Processing
```dart
// Use GPT-5 Nano (default)
final result = await ChatGPTService.processImage(
  imageFile: imageFile,
  useNanoModel: true, // Uses GPT-5 Nano with responses API
);

// Use GPT-4o Mini as fallback
final result = await ChatGPTService.processImage(
  imageFile: imageFile,
  useNanoModel: false, // Uses GPT-4o Mini with chat/completions API
);
```

### Multiple Images
```dart
final results = await ChatGPTService.processMultipleImages(
  imageFiles: imageFiles,
  useNanoModel: true, // Uses GPT-5 Nano
);
```

### Location Processing
```dart
final location = await ChatGPTService.fetchUpdatedLocationFromChatGPT(
  "Los Angeles"
);
```

## API Key Configuration
Add your OpenAI API key to `lib/apiSecretKeys.dart`:
```dart
const String chatGPTApiKey = 'your_actual_openai_api_key_here';
```

## Error Handling
The new implementation includes:
- Automatic fallback from responses to chat/completions endpoint
- Retry logic for rate limits and temporary errors
- Better debugging output with request/response logging
- Graceful handling of model-specific endpoint requirements

## Testing
Run the new test suite:
```bash
flutter test test/chat_gpt_service_test.dart
```

This verifies:
- Model class functionality
- Interface compatibility
- Deprecation warnings for old functions
- API endpoint logic