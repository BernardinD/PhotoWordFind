import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:PhotoWordFind/utils/cloud_utils.dart';

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

