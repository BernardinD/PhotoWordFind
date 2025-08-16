import 'package:PhotoWordFind/models/contactEntry.dart';
import 'package:PhotoWordFind/widgets/confirmation_dialog.dart';
import 'package:flutter/material.dart';
// Remove custom formatter so focus handling can be simplified. The built-in
// `TextCapitalization.sentences` option already covers sentence casing for
// speech input.

Future<String?> showNoteDialog(
    BuildContext context, String key, ContactEntry? contact,
    {String? existingNotes}) {
  final _formKey = GlobalKey<FormState>(); // Key for the form
  final _noteFocus = FocusNode();
  final originalNote = existingNotes ?? '';
  TextEditingController noteController =
      TextEditingController(text: originalNote);

  bool changed = false;
  noteController.addListener(() {
    changed = noteController.text != originalNote;
  });

  Future<bool> _confirm(BuildContext context,
      {String message = 'Are you sure?'}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialog(message: message),
    );
    return result ?? false;
  }

  // Get screen width and height to adjust the dialog size in split-screen mode
  var screenSize = MediaQuery.of(context).size;

  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (context, setState) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_noteFocus.hasFocus) {
              _noteFocus.requestFocus();
            }
          });
          return WillPopScope(
            onWillPop: () async {
              if (changed) {
                return await _confirm(context, message: 'Discard changes?');
              }
              return true;
            },
            child: AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15.0),
              ),
          icon: Icon(Icons.note_alt, color: Colors.deepPurple, size: 40),
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
              maxHeight: screenSize.height *
                  0.6, // Dialog height will be 60% of screen height
              maxWidth: screenSize.width *
                  0.9, // Dialog width will be 90% of screen width
            ),
            child: SingleChildScrollView(
              child: Form(
                key: _formKey, // Attach the form key
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      autofocus: true,
                      focusNode: _noteFocus,
                      controller: noteController,
                      maxLines: 5,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      textCapitalization: TextCapitalization.sentences,
                      onFieldSubmitted: (_) => _noteFocus.requestFocus(),
                      style: TextStyle(
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Enter your note',
                        hintText: 'Type something...',
                        labelStyle: TextStyle(fontSize: 14),
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10.0),
                        ),
                        contentPadding: EdgeInsets.all(12.0),
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
            ),
          ),
          actions: [
              TextButton(
                onPressed: () async {
                  if (changed) {
                    final discard =
                        await _confirm(context, message: 'Discard changes?');
                    if (!discard) return;
                  }
                  Navigator.of(context).pop(); // Dismiss the dialog
                },
              child: Text('Cancel'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.redAccent,
              ),
            ),
              ElevatedButton(
                child: Text('Save'),
                onPressed: () async {
                  if (_formKey.currentState!.validate()) {
                    String note = noteController.text;

                    if (changed) {
                      final confirmSave =
                          await _confirm(context, message: 'Save changes?');
                      if (!confirmSave) return;
                    }

                    // Call the onSave function and pass back the note
                    _onSave(key, note, contact);
                    Navigator.of(context).pop(note);
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
            ),
          );
        },
      );
    },
  ).then((value) {
    noteController.dispose();
    _noteFocus.dispose();
    return value;
  });
}

void _onSave(String key, notes, ContactEntry? contact) {
  // StorageUtils.save(key, backup: true, notes: notes);
  // TODO: Review this call stack. With the new ContactEntry model,
  // saving will happen automatically when the contact is updated
  // with the return value
  contact?.notes = notes;
}
