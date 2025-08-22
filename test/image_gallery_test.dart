import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:PhotoWordFind/screens/gallery/image_gallery_screen.dart';
import 'package:PhotoWordFind/screens/gallery/widgets/image_gallery.dart';

Future<String> _createTestImage() async {
  final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQImWNgYGD4DwABAgEAO+2VfQAAAABJRU5ErkJggg==');
  final file =
      await File('${Directory.systemTemp.path}/test_image.png').create();
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

  testWidgets('ImageGalleryScreen shows loading state during initialization',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: ImageGalleryScreen()));

    // Should show loading state initially
    expect(find.text('Signing in and loading images...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });

  testWidgets('ImageGalleryScreen handles initialization error gracefully',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: ImageGalleryScreen()));

    // Let initialization attempt to complete
    await tester.pump();
    await tester.pump(Duration(seconds: 1));

    // Should either show the app content or an error message, but not crash
    expect(tester.takeException(), isNull);
  });

  testWidgets('Search field shows clear button when text is entered',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: ImageGalleryScreen()));

    // Wait for initialization
    await tester.pump();
    await tester.pump(Duration(seconds: 2));

    // Find the search field
    final searchField = find.byType(TextField).first;
    expect(searchField, findsOneWidget);

    // Initially, there should be no clear button (suffixIcon should be null)
    expect(find.byIcon(Icons.clear), findsNothing);

    // Enter text in search field
    await tester.enterText(searchField, 'test search');
    await tester.pump();

    // Now the clear button should appear
    expect(find.byIcon(Icons.clear), findsOneWidget);

    // Tap the clear button
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();

    // Clear button should disappear and text should be cleared
    expect(find.byIcon(Icons.clear), findsNothing);
    expect(find.text('test search'), findsNothing);
  });
}
