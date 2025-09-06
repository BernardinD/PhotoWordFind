import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:PhotoWordFind/widgets/note_dialog.dart';
import 'package:PhotoWordFind/models/contactEntry.dart';

void main() {
  group('Note Dialog Responsiveness Tests', () {
    late ContactEntry testContact;

    setUp(() {
      testContact = ContactEntry(
        identifier: 'test',
        imagePath: '/test/path.jpg',
        dateFound: DateTime.now(),
      );
    });

    testWidgets('showNoteDialog adapts to constrained height (split screen)', (tester) async {
      // Create a widget with constrained height (simulating split screen)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return MediaQuery(
                  data: const MediaQueryData(size: Size(400, 350)), // Constrained height < 400
                  child: ElevatedButton(
                    onPressed: () {
                      showNoteDialog(context, 'test-key', testContact);
                    },
                    child: const Text('Show Dialog'),
                  ),
                );
              },
            ),
          ),
        ),
      );

      // Tap the button to show the dialog
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Verify the dialog appears
      expect(find.byType(AlertDialog), findsOneWidget);
      
      // Verify the dialog has responsive elements
      expect(find.text('Add Note...'), findsOneWidget);
      expect(find.byIcon(Icons.note_alt), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Verify text field is present and accessible
      expect(find.byType(TextFormField), findsOneWidget);
      
      // The dialog should not overflow - if it did, we'd get render errors
      expect(tester.takeException(), isNull);
    });

    testWidgets('showNoteDialog uses normal sizing for regular screen height', (tester) async {
      // Create a widget with normal height
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return MediaQuery(
                  data: const MediaQueryData(size: Size(400, 800)), // Normal height >= 400
                  child: ElevatedButton(
                    onPressed: () {
                      showNoteDialog(context, 'test-key', testContact);
                    },
                    child: const Text('Show Dialog'),
                  ),
                );
              },
            ),
          ),
        ),
      );

      // Tap the button to show the dialog
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Verify the dialog appears with normal elements
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Add Note...'), findsOneWidget);
      expect(find.byIcon(Icons.note_alt), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
      
      // No render overflow errors
      expect(tester.takeException(), isNull);
    });

    testWidgets('dialog can be dismissed with Cancel button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showNoteDialog(context, 'test-key', testContact);
                  },
                  child: const Text('Show Dialog'),
                );
              },
            ),
          ),
        ),
      );

      // Show dialog
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Tap Cancel button
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Verify dialog is dismissed
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('dialog validates empty input', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showNoteDialog(context, 'test-key', testContact);
                  },
                  child: const Text('Show Dialog'),
                );
              },
            ),
          ),
        ),
      );

      // Show dialog
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Try to save with empty input
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Should show validation error
      expect(find.text('Note cannot be empty'), findsOneWidget);
      
      // Dialog should still be open
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('dialog works with existing notes', (tester) async {
      const existingNote = 'This is an existing note';
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showNoteDialog(
                      context, 
                      'test-key', 
                      testContact,
                      existingNotes: existingNote,
                    );
                  },
                  child: const Text('Show Dialog'),
                );
              },
            ),
          ),
        ),
      );

      // Show dialog
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Verify existing note is displayed
      expect(find.text(existingNote), findsOneWidget);
    });
  });
}