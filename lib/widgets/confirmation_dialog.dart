import 'package:flutter/material.dart';

class ConfirmationDialog extends StatelessWidget {
  final String message;

  ConfirmationDialog({required this.message});

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Handle the case when the user presses the back button or taps outside the dialog
        Navigator.of(context).pop(false); // Return false when dismissed
        return false;
      },
      child: AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.0),
        ),
        title: Text(
          'Are you sure?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(message),
        contentPadding: EdgeInsets.all(16.0),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.maxFinite,
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context)
                        .pop(false); // Return false when "No" is pressed
                  },
                  child: Text(
                    'No',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 8.0), // Adjust the spacing as needed
              SizedBox(
                width: double.maxFinite,
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context)
                        .pop(true); // Return true when "Yes" is pressed
                  },
                  child: Text(
                    'Yes',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
