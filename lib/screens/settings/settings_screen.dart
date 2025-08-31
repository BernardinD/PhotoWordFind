import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:PhotoWordFind/utils/cloud_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ImportLimitTile extends StatefulWidget {
	const _ImportLimitTile();

	@override
	State<_ImportLimitTile> createState() => _ImportLimitTileState();
}

class _ImportLimitTileState extends State<_ImportLimitTile> {
	static const String _key = 'import_max_selection_v1';
	final List<int> _options = const [20, 50, 100, 200, 500, -1];
	int? _current; // null while loading

	@override
	void initState() {
		super.initState();
		_load();
	}

	Future<void> _load() async {
		final prefs = await SharedPreferences.getInstance();
		setState(() => _current = prefs.getInt(_key) ?? 200);
	}

	Future<void> _set(int value) async {
		final prefs = await SharedPreferences.getInstance();
		await prefs.setInt(_key, value);
		if (!mounted) return;
		setState(() => _current = value);
		ScaffoldMessenger.of(context).showSnackBar(
			SnackBar(content: Text(value < 0 ? 'Import selection set to Unlimited' : 'Import selection limit set to $value')),
		);
	}

	String _labelFor(int v) => v < 0 ? 'Unlimited' : v.toString();

	@override
	Widget build(BuildContext context) {
		final current = _current;
		return ListTile(
			title: const Text('Import selection limit'),
			subtitle: Text(current == null ? 'Loading...' : 'Current: ${_labelFor(current)}'),
			onTap: () async {
				final result = await showModalBottomSheet<int>(
					context: context,
					builder: (ctx) => SafeArea(
						child: ListView(
							shrinkWrap: true,
							children: [
								const ListTile(title: Text('Select max images per import', style: TextStyle(fontWeight: FontWeight.bold))),
								..._options.map((v) => RadioListTile<int>(
											value: v,
											groupValue: current ?? 200,
											title: Text(_labelFor(v)),
											onChanged: (val) => Navigator.pop(ctx, val),
										)),
							],
						),
					),
				);
				if (result != null) {
					await _set(result);
				}
			},
		);
	}
}

class SettingsScreen extends StatelessWidget {
	final Future<void> Function()? onResetImportDir;
	final Future<void> Function()? onChangeImportDir;
	final Future<bool> Function()? onRequestSignIn;
	final Future<void> Function()? onRequestSignOut;
	final DateTime? lastSyncTime;
	final bool syncing;
	final bool signInFailed;

	const SettingsScreen({
		super.key,
		this.onResetImportDir,
		this.onChangeImportDir,
		this.onRequestSignIn,
		this.onRequestSignOut,
		this.lastSyncTime,
		this.syncing = false,
		this.signInFailed = false,
	});

	@override
	Widget build(BuildContext context) {
		return Scaffold(
			appBar: AppBar(title: const Text('Settings')),
			body: ListView(
				children: [
					ListTile(
						title: const Text('Import directory'),
						subtitle: const Text('Choose or reset the import location'),
						trailing: Wrap(
							spacing: 8,
							children: [
								IconButton(
									tooltip: 'Change directory',
									onPressed: onChangeImportDir,
									icon: const Icon(Icons.drive_folder_upload),
								),
								IconButton(
									tooltip: 'Reset',
									onPressed: onResetImportDir,
									icon: const Icon(Icons.restore),
								),
							],
						),
					),
					const Divider(),
					const _ImportLimitTile(),
					const Divider(),
					FutureBuilder<bool>(
						future: CloudUtils.isSignedin(),
						builder: (ctx, snap) {
							final signed = snap.data == true;
							return ListTile(
								title: const Text('Cloud account'),
								subtitle: Text(
									signed
											? 'Signed in'
											: signInFailed
													? 'Sign-in failed'
													: 'Signed out',
								),
								trailing: ElevatedButton.icon(
									icon: Icon(signed ? Icons.logout : Icons.login),
									label: Text(signed ? 'Sign out' : 'Sign in'),
									onPressed: () async {
										if (signed) {
											await onRequestSignOut?.call();
										} else {
											await onRequestSignIn?.call();
										}
										if (context.mounted) {
											ScaffoldMessenger.of(context).showSnackBar(
												SnackBar(
													content: Text(
															signed ? 'Signed out' : 'Signed in (requested)'),
												),
											);
										}
									},
								),
							);
						},
					),
					const Divider(),
					ListTile(
						title: const Text('Last sync time'),
						subtitle: Text(
							syncing
									? 'Syncing...'
									: lastSyncTime != null
											? DateFormat.yMd().add_Hm().format(lastSyncTime!)
											: 'Never',
						),
					),
				],
			),
		);
	}
}

