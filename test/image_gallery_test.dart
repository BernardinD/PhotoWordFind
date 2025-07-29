import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:PhotoWordFind/experimental/2attempt/imageGalleryScreen.dart';
import 'package:PhotoWordFind/models/contactEntry.dart';

Future<String> _createTestImage() async {
  final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQImWNgYGD4DwABAgEAO+2VfQAAAABJRU5ErkJggg==');
  final file = await File('${Directory.systemTemp.path}/test_image.png').create();
  await file.writeAsBytes(bytes);
  return file.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ImageGallery shows page info for empty list', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: TickerMode(
        enabled: false,
        child: ImageGallery(
          images: const [],
          selectedImages: const [],
          onImageSelected: (_) {},
          onMenuOptionSelected: (_, __) {},
          galleryHeight: 200,
          onPageChanged: (_) {},
          currentIndex: 0,
          sortOption: 'Name',
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('1 / 0'), findsOneWidget);
  });

  testWidgets('ImageGalleryScreen shows loading state during initialization', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ImageGalleryScreen()));
    
    // Should show loading state initially
    expect(find.text('Signing in and loading images...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    
    // Should not show floating action button during loading
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('ImageGalleryScreen handles initialization error gracefully', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ImageGalleryScreen()));
    
    // Let initialization attempt to complete
    await tester.pump();
    await tester.pump(Duration(seconds: 1));
    
    // Should either show the app content or an error message, but not crash
    expect(tester.takeException(), isNull);
  });

}
