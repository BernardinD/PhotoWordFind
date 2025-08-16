import 'package:flutter/material.dart';
import 'package:PhotoWordFind/utils/cloud_utils.dart';
import 'package:PhotoWordFind/main.dart' show UiMode; // for UI mode toggle

class SettingsScreen extends StatefulWidget {
  final Future<void> Function() onResetImportDir;
  final Future<void> Function() onChangeImportDir;
  final Future<bool> Function() onRequestSignIn; // returns success
  final Future<void> Function() onRequestSignOut;
  final DateTime? lastSyncTime;
  final bool syncing;
  final bool signInFailed; // signal last sign-in attempt failed

  const SettingsScreen({
    super.key,
    required this.onResetImportDir,
    required this.onChangeImportDir,
    required this.onRequestSignIn,
    required this.onRequestSignOut,
    this.lastSyncTime,
    this.syncing = false,
    this.signInFailed = false,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _working = false; // local flag to disable taps while signing in/out
  String? _opMessage; // transient message while operating

  Future<void> _handleSignInOut() async {
    if (_working) return;
    setState(() {
      _working = true;
      _opMessage = null;
    });
    final bool currentlySignedIn = await CloudUtils.isSignedin();
    try {
      if (!currentlySignedIn) {
        _opMessage = 'Signing in...';
        setState(() {});
        final ok = await widget.onRequestSignIn();
        if (!ok) {
          _opMessage = 'Sign in failed';
        } else {
          _opMessage = 'Signed in';
        }
      } else {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Sign out'),
            content: const Text('Do you want to sign out and sync first?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Sign out'),
              ),
            ],
          ),
        );
        if (confirm == true) {
          _opMessage = 'Signing out...';
          setState(() {});
          await widget.onRequestSignOut();
          _opMessage = 'Signed out';
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
        });
      }
      if (mounted && _opMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_opMessage!)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = CloudUtils.currentUserEmail;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Interface', style: Theme.of(context).textTheme.titleMedium),
          ),
            FutureBuilder<bool>(
              future: UiMode.isNewUi(),
              builder: (ctx, snap) {
                final isNew = snap.data ?? true;
                return SwitchListTile(
                  title: Text('Use new gallery UI'),
                  subtitle: Text(isNew ? 'Currently using new UI' : 'Currently using legacy UI'),
                  value: isNew,
                  onChanged: (val) async {
                    if (val == isNew) return; // no change
                    final proceed = await showDialog<bool>(
                      context: context,
                      builder: (dialogCtx) => AlertDialog(
                        title: const Text('Confirm UI Switch'),
                        content: Text('Switch to ' + (val ? 'new' : 'legacy') + ' interface?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(dialogCtx, true), child: const Text('Switch')),
                        ],
                      ),
                    );
                    if (proceed == true) {
                      // Perform the UI mode switch; this will rebuild the root and likely dispose this screen.
                      await UiMode.switchTo(val);
                      // Only attempt to refresh if still mounted (e.g., if user stayed in same UI somehow).
                      if (mounted) setState(() {});
                    }
                  },
                );
              },
            ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Account', style: Theme.of(context).textTheme.titleMedium),
          ),
          ListTile(
            leading: Stack(
              children: [
                Icon(
                  email != null ? Icons.cloud_done : Icons.cloud_off,
                  color: email != null ? Colors.green : Colors.redAccent,
                ),
                if (widget.signInFailed && email == null)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Icon(Icons.error, size: 14, color: Colors.orange),
                  ),
              ],
            ),
            title: Text(email ?? 'Not signed in'),
            subtitle: Text(widget.lastSyncTime != null
                ? 'Last sync: ${TimeOfDay.fromDateTime(widget.lastSyncTime!).format(context)}'
                : 'No sync yet'),
            trailing: _working || widget.syncing
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton(
                    onPressed: _handleSignInOut,
                    child: Text(email != null ? 'Sign out' : 'Sign in'),
                  ),
            onTap: _handleSignInOut,
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Import Directory', style: Theme.of(context).textTheme.titleMedium),
          ),
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('Change Import Directory'),
            subtitle: const Text('Select a new directory for imports'),
            onTap: _working ? null : () async { await widget.onChangeImportDir(); },
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Reset Import Directory'),
            subtitle: const Text('Clear saved import directory'),
            onTap: _working
                ? null
                : () async {
                    await widget.onResetImportDir();
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
