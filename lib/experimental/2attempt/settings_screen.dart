import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  final Future<void> Function() onResetImportDir;
  final Future<void> Function() onChangeImportDir;

  const SettingsScreen({
    Key? key,
    required this.onResetImportDir,
    required this.onChangeImportDir,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('Change Import Directory'),
            subtitle: const Text('Select a new directory for imports'),
            onTap: () async {
              await onChangeImportDir();
            },
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Reset Import Directory'),
            subtitle: const Text('Clear saved import directory'),
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
