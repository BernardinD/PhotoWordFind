import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  final Future<void> Function() onResetImportDir;

  const SettingsScreen({Key? key, required this.onResetImportDir})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Reset Import Directory'),
            subtitle: const Text('Set import directory back to default'),
            onTap: () async {
              await onResetImportDir();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Import directory reset')),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
