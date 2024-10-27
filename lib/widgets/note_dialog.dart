import 'package:PhotoWordFind/utils/storage_utils.dart';
import 'package:PhotoWordFind/widgets/confirmation_dialog.dart';
import 'package:flutter/material.dart';

Future<String?> showNoteDialog(BuildContext context, String key, {String? existingNotes}) {
  final _formKey = GlobalKey<FormState>(); // Key for the form
  TextEditingController noteController = TextEditingController(text: existingNotes);

  // Get screen width and height to adjust the dialog size in split-screen mode
  var screenSize = MediaQuery.of(context).size;

  return showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15.0),
        ),
        title: Text(
          'Add Note...',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
            fontSize: 20, // Title font size
          ),
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: screenSize.height * 0.6, // Dialog height will be 60% of screen height
            maxWidth: screenSize.width * 0.9,   // Dialog width will be 90% of screen width
          ),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey, // Attach the form key
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: noteController,
                    maxLines: 5,
                    style: TextStyle(
                      fontSize: 14,  // Smaller input text size
                    ),
                    decoration: InputDecoration(
                      labelText: 'Enter your note',
                      labelStyle: TextStyle(
                        fontSize: 14,  // Smaller label text size
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Note cannot be empty';  // Validation message
                      }
                      return null;  // Input is valid
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Dismiss the dialog
            },
            child: Text('Cancel'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.redAccent,
            ),
          ),
          ElevatedButton(
            child: Text('Save'),
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                String note = noteController.text;

                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return ConfirmationDialog(
                      message: "Are you sure you want to save this?",
                    );
                  },
                ).then((confirmed) {
                  if (!confirmed) return;

                  // Call the onSave function and pass back the note
                  _onSave(key, note);
                  Navigator.of(context)
                      .pop(note); // Pass note back and dismiss dialog
                });
              }
            },
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.deepPurple,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      );
    },
  );
}


void _onSave(String key, notes) {
  StorageUtils.save(key, backup: true, notes: notes);
}
