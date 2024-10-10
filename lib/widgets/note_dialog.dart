import 'package:PhotoWordFind/utils/storage_utils.dart';
import 'package:PhotoWordFind/widgets/confirmation_dialog.dart';
import 'package:flutter/material.dart';

Future<String?> showNoteDialog(BuildContext context, String key, {String? existingNotes}) {
  final _formKey = GlobalKey<FormState>(); // Key for the form
  TextEditingController noteController =
      TextEditingController(text: existingNotes);

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
          ),
        ),
        content: Form(
          key: _formKey, // Attach the form key
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: noteController,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: 'Enter your note',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Note cannot be empty'; // Validation message
                  }
                  return null; // Input is valid
                },
              ),
            ],
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
          StatefulBuilder(
            builder: (context, innerSetState) {
              return ElevatedButton(
                onPressed: () async {
                  if (_formKey.currentState!.validate()) {
                    String note = noteController.text;
              
                    bool confirmed = await showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return ConfirmationDialog(
                          message: "Are you sure you want to sign out?",
                        );
                      },
                    );
              
                    if (!confirmed) return;
              
                    innerSetState(() {
                      _onSave(key, note); // Call the onSave function to save the note
                      Navigator.of(context).pop(note); // Dismiss the dialog
                    });
                  }
                },
                child: Text('Save'),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.deepPurple,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            }
          ),
        ],
      );
    },
  );
}

void _onSave(String key, notes) {
  StorageUtils.save(key, backup: true, notes: notes);
}
