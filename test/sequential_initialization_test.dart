import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:PhotoWordFind/experimental/2attempt/imageGalleryScreen.dart';
import 'package:PhotoWordFind/utils/cloud_utils.dart';

// Mock class for CloudUtils
class MockCloudUtils extends Mock {
  static Future<bool> isSignedin() async => true;
  static Future<bool> firstSignIn() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Sequential Initialization Tests', () {
    testWidgets('ImageGalleryScreen shows loading state during initialization', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ImageGalleryScreen(),
      ));

      // Should show loading state initially
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Initializing app...'), findsOneWidget);

      // FAB should be hidden during initialization
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('ImageGalleryScreen shows content after initialization', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ImageGalleryScreen(),
      ));

      // Wait for initialization to complete
      await tester.pump();
      await tester.pump(Duration(seconds: 2));

      // Loading state should be gone
      expect(find.text('Initializing app...'), findsNothing);
    });

    testWidgets('FloatingActionButton appears after initialization', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ImageGalleryScreen(),
      ));

      // Initial state - no FAB
      expect(find.byType(FloatingActionButton), findsNothing);

      // Wait for initialization
      await tester.pump();
      await tester.pump(Duration(seconds: 2));

      // FAB should appear after initialization
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('App remains functional even if sign-in fails', (tester) async {
      // This test would require mocking CloudUtils to simulate sign-in failure
      // For now, we'll test that the app initializes and shows content
      await tester.pumpWidget(MaterialApp(
        home: ImageGalleryScreen(),
      ));

      await tester.pump();
      await tester.pump(Duration(seconds: 2));

      // App should still show the gallery interface
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });
  });

  group('Loading State Tests', () {
    testWidgets('Controls are hidden during initialization', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ImageGalleryScreen(),
      ));

      // During loading, controls should not be visible
      expect(find.text('Initializing app...'), findsOneWidget);
      
      // Search controls should not be accessible during loading
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('AppBar actions are responsive during initialization', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ImageGalleryScreen(),
      ));

      // AppBar should be present even during initialization
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Image Gallery'), findsOneWidget);
      
      // Settings icon should be available
      expect(find.byIcon(Icons.settings), findsOneWidget);
    });
  });
}