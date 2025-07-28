// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility that Flutter provides. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:PhotoWordFind/main.dart';

void main() {
  group('PhotoWordFind App Tests', () {
    testWidgets('App builds and shows title', (WidgetTester tester) async {
      // Build our app and trigger a frame.
      await tester.pumpWidget(MyApp(title: "Testing"));

      // Wait for the app to load
      await tester.pumpAndSettle();

      // Verify that the app builds successfully
      expect(find.byType(MaterialApp), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('AppBar contains expected controls', (WidgetTester tester) async {
      // Build our app and trigger a frame.
      await tester.pumpWidget(MyApp(title: "Testing"));

      // Wait for the app to load
      await tester.pumpAndSettle();

      // Verify AppBar exists
      expect(find.byType(AppBar), findsOneWidget);
      
      // Verify settings button exists
      expect(find.byIcon(Icons.settings), findsOneWidget);
      
      // Verify sync button exists
      expect(find.byIcon(Icons.sync), findsOneWidget);
      
      // Verify sign in/out button exists (should be either login or logout icon)
      expect(find.byType(IconButton), findsAtLeastNWidgets(3)); // settings, sync, sign in/out
    });

    testWidgets('Find, Display, and Move buttons exist', (WidgetTester tester) async {
      // Build our app and trigger a frame.
      await tester.pumpWidget(MyApp(title: "Testing"));

      // Wait for the app to load
      await tester.pumpAndSettle();

      // Verify main action buttons exist
      expect(find.text('Find'), findsOneWidget);
      expect(find.text('Display'), findsOneWidget);
      expect(find.text('Move'), findsOneWidget);
    });

    testWidgets('FloatingActionButton exists', (WidgetTester tester) async {
      // Build our app and trigger a frame.
      await tester.pumpWidget(MyApp(title: "Testing"));

      // Wait for the app to load
      await tester.pumpAndSettle();

      // Verify floating action button exists
      expect(find.byType(FloatingActionButton), findsAtLeastNWidgets(1));
    });

    testWidgets('Settings button navigates to settings screen', (WidgetTester tester) async {
      // Build our app and trigger a frame.
      await tester.pumpWidget(MyApp(title: "Testing"));

      // Wait for the app to load
      await tester.pumpAndSettle();

      // Tap the settings button
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();

      // Verify we navigated to settings screen
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Import Directory'), findsOneWidget);
    });
  });
}
