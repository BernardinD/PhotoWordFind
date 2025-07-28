import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:PhotoWordFind/main.dart';

class SettingsScreen extends StatefulWidget {
  final String? currentDirectory;
  final Function(String?) onDirectoryChanged;

  const SettingsScreen({
    Key? key,
    required this.currentDirectory,
    required this.onDirectoryChanged,
  }) : super(key: key);

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _directoryPath;

  @override
  void initState() {
    super.initState();
    _directoryPath = widget.currentDirectory;
  }

  Future<void> _selectDirectory() async {
    try {
      // Reset callback function to handle file picker issues
      await FilePicker.platform.pickFiles(
          type: FileType.image,
          onFileLoading: (_) => debugPrint(""),
          allowedExtensions: ["fail"]);
    } catch (e) {
      debugPrint("Directory picker setup error: $e");
    }

    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    
    if (selectedDirectory != null) {
      setState(() {
        _directoryPath = selectedDirectory;
      });
      widget.onDirectoryChanged(selectedDirectory);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Import Directory',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current Directory:',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SizedBox(height: 8),
                    Text(
                      _directoryPath ?? 'No directory selected',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _directoryPath != null ? Colors.blue : Colors.grey,
                      ),
                    ),
                    SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _selectDirectory,
                      icon: Icon(Icons.folder_open),
                      label: Text('Change Directory'),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 24),
            Text(
              'About Import Directory',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SizedBox(height: 8),
            Text(
              'Select the directory where your images are stored. This is where the app will look for images to process and analyze.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}