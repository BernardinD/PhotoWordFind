import 'package:flutter/material.dart';
import 'package:PhotoWordFind/widgets/note_dialog.dart';
import 'package:PhotoWordFind/models/contactEntry.dart';

/// Demo app to showcase the responsive notes dialog fix
class NoteDialogDemo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Note Dialog Demo',
      home: DemoScreen(),
    );
  }
}

class DemoScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final contact = ContactEntry(
      identifier: 'demo',
      imagePath: '/demo/path.jpg',
      dateFound: DateTime.now(),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('Note Dialog Responsiveness Demo'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Test the notes dialog in different screen sizes:',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 40),
            ElevatedButton(
              onPressed: () async {
                await showNoteDialog(
                  context,
                  'demo-key',
                  contact,
                  existingNotes: 'Sample existing note text...',
                );
              },
              child: Text('Show Notes Dialog'),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
            SizedBox(height: 20),
            Text(
              'Screen size: ${MediaQuery.of(context).size.width.round()} x ${MediaQuery.of(context).size.height.round()}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            SizedBox(height: 10),
            Text(
              MediaQuery.of(context).size.height < 400 
                ? 'Constrained height mode (split screen)' 
                : 'Normal height mode',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: MediaQuery.of(context).size.height < 400 
                  ? Colors.orange 
                  : Colors.green,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  runApp(NoteDialogDemo());
}