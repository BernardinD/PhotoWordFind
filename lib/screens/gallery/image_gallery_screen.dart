import 'dart:io';
import 'dart:async';

import 'package:PhotoWordFind/models/contactEntry.dart';
import 'package:PhotoWordFind/social_icons.dart';
import 'package:PhotoWordFind/utils/storage_utils.dart';
import 'package:PhotoWordFind/services/search_service.dart';
import 'package:PhotoWordFind/services/chat_gpt_service.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:PhotoWordFind/utils/chatgpt_post_utils.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:PhotoWordFind/widgets/confirmation_dialog.dart';
import 'package:PhotoWordFind/screens/settings/settings_screen.dart';
import 'package:PhotoWordFind/utils/cloud_utils.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:PhotoWordFind/main.dart' show UiMode; // for UI mode switching
import 'package:PhotoWordFind/screens/gallery/widgets/image_gallery.dart';

// PageController moved to widgets as kGalleryPageController

class ImageGalleryScreen extends StatefulWidget {
	@override
	_ImageGalleryScreenState createState() => _ImageGalleryScreenState();
}

class _ImageGalleryScreenState extends State<ImageGalleryScreen>
		with TickerProviderStateMixin {
	String searchQuery = '';
	String selectedSortOption = 'Name'; // Default value from the list
	List<String> sortOptions = [
		'Name',
		'Date found',
		'Size',
		'Snap Added Date',
		'Instagram Added Date',
		'Added on Snapchat',
		'Added on Instagram'
	]; // Add your sort options here
	String selectedState = 'All';
	List<String> states = ['All'];
	List<ContactEntry> images = [];
	List<ContactEntry> allImages = [];
	List<String> selectedImages = [];

	int currentIndex = 0;
	static const String _lastStateKey = 'last_selected_state';
	static const String _importDirKey = 'import_directory';
	String? _importDirPath;

	// State variable to track the selected sort order
	bool isAscending = true; // Default sorting order

	// Add a setting to control which loading method to use
	bool useJsonFileForLoading = false; // Set to true to load from JSON file

	bool _controlsExpanded = true; // Tracks whether the controls are minimized

	bool _isInitializing = true; // Tracks if app is still initializing
	String? _initializationError; // Stores any initialization error
	
	// New granular loading states
	bool _isLoadingImages = false; // Tracks if images are being loaded
	int _totalImagesToLoad = 0; // Total number of images to load
	int _imagesLoaded = 0; // Number of images loaded so far

	/// Key for the root [Navigator] so dialogs can use a context that
	/// has navigation and localization available.
	final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

	// Track sign-out operation (removed icon usage, state no longer needed)
	// bool _signingOut = false;
	// String? _signOutMessage;
	// New sync state
	bool _syncing = false;
	DateTime? _lastSyncTime;
	// String? _lastSyncError; // no longer surfaced

	// Debounce for search input to reduce rebuild churn
	Timer? _searchDebounce;

	@override
	void initState() {
		super.initState();
		// Attach progress callback for CloudUtils (scoped to this screen)
		CloudUtils.progressCallback = ({double? value, String? message, bool done = false, bool error = false}) {
			if (!mounted) return;
			// Previously updated sign-out UI; now no-op.
		};
		_initializeApp();
	}

	@override
	void dispose() {
		_searchDebounce?.cancel();
		super.dispose();
	}

	Future requestPermissions() async {
		var status = await Permission.manageExternalStorage.status;
		if (!status.isGranted) {
			await Permission.manageExternalStorage.request();
		}
	}

	/// Initializes the app in sequential order:
	/// 1. Sign-in first
	/// 2. Load images after sign-in is complete
	/// 3. Load import directory
	Future<void> _initializeApp() async {
		try {
			await requestPermissions();
			setState(() {
				_isInitializing = true;
				_initializationError = null;
			});

			// Step 1: Ensure user is signed in first
			final signedIn = await _ensureSignedIn();

			if (!signedIn) {
				setState(() {
					_initializationError =
							'Sign-in failed. Some features may not be available.';
				});
			}

			// Complete basic initialization - allow UI to be partially functional
			setState(() {
				_isInitializing = false;
				_isLoadingImages = true;
			});

			// Step 2: Load images only after sign-in is complete
			if (useJsonFileForLoading) {
				await _loadImagesFromJsonFile();
			} else {
				await _loadImagesFromPreferences();
			}

			// Step 3: Load import directory
			await _loadImportDirectory();

			setState(() {
				_isLoadingImages = false;
			});
		} catch (e) {
			setState(() {
				_isInitializing = false;
				_isLoadingImages = false;
				_initializationError = 'Initialization failed: $e';
			});
		}
	}

	Future<bool> _ensureSignedIn() async {
		// First check if we're already signed in (from main app initialization)
		bool signed = await CloudUtils.isSignedin();
		if (!signed) {
			// Only attempt sign-in if not already signed in
			signed = await CloudUtils.firstSignIn();
		}
		return signed;
	}

	Future<void> _forceSync({bool fromPull = false}) async {
		if (_syncing) return; // Prevent concurrent syncs
		final ctx = _navigatorKey.currentContext ?? context;
		final messenger = ScaffoldMessenger.of(ctx);

		setState(() {
			_syncing = true;
		});

		void show(String msg, {Duration duration = const Duration(seconds: 2)}) {
			if (fromPull) return;
			messenger.showSnackBar(SnackBar(content: Text(msg), duration: duration));
		}

		try {
			if (!await CloudUtils.isSignedin()) {
				show('Not signed in');
				return;
			}
			if (!await CloudUtils.isConnected()) {
				show('No internet connection');
				return;
			}
			if (!fromPull) {
				messenger.hideCurrentSnackBar();
				messenger.showSnackBar(const SnackBar(
					content: Row(
						children: [
							SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
							SizedBox(width: 12),
							Text('Syncing…'),
						],
					),
					duration: Duration(minutes: 1),
				));
			}
			await CloudUtils.updateCloudJson().timeout(const Duration(seconds: 45));
			_lastSyncTime = DateTime.now();
			if (!fromPull) {
				messenger.hideCurrentSnackBar();
				show('Sync complete (${DateFormat.Hm().format(_lastSyncTime!)})');
			}
		} catch (e) {
			if (!fromPull) {
				messenger.hideCurrentSnackBar();
				show('Sync failed: $e');
			}
		} finally {
			if (mounted) setState(() => _syncing = false);
		}
	}

	Future<void> _toggleSignInOut() async {
		final ctx = _navigatorKey.currentContext ?? context;
		bool signed = await CloudUtils.isSignedin();
		if (!signed) {
			setState(() {
				_isInitializing = true;
			});
			try {
				await CloudUtils.firstSignIn();
			} finally {
				if (!mounted) return;
				setState(() {
					_isInitializing = false;
				});
			}
		} else {
			final confirm = await showDialog<bool>(
				context: ctx,
				builder: (_) => ConfirmationDialog(message: 'Sign out?'),
			);
			if (confirm == true) {
				setState(() {
					// _signingOut = true; // removed
					// _signOutMessage = 'Signing out...'; // removed
				});
				try {
					await CloudUtils.signOut();
				} catch (_) {
					// error message already captured via callback
				}
			}
		}
		if (!mounted) return;
		setState(() {
			// Trigger UI update to reflect new sign-in state
		});
	}

	Future<void> _loadImagesFromPreferences() async {
		// Read the image path map from the JSON file (simulating a separate storage location)
		List<ContactEntry> loadedImages = [];
		
		final keys = StorageUtils.getKeys();
		setState(() {
			_totalImagesToLoad = keys.length;
			_imagesLoaded = 0;
		});

		// Fetch each contact directly from Hive using the keys list to avoid
		// reading the entire box twice.
		// TODO: Make sure that an error from parsing one contact doesn't prevent others from loading
		for (final identifier in keys) {
			final contactEntry = await StorageUtils.get(identifier);
			if (contactEntry != null) {
				loadedImages.add(contactEntry);
			}
			
			setState(() {
				_imagesLoaded++;
			});
			
			// Allow UI to update progressively every 10 images or at the end
			if (_imagesLoaded % 10 == 0 || _imagesLoaded == _totalImagesToLoad) {
				// Small delay to allow UI updates
				await Future.delayed(Duration(milliseconds: 1));
			}
		}
		allImages = loadedImages;
		_updateStates(allImages);
		await _restoreLastSelectedState();
		await _applyFiltersAndSort();
	}

	Future<void> _loadImagesFromJsonFile() async {
		// Read the image path map from the JSON file
		final Map<String, dynamic> fileMap = await StorageUtils.readJson();
		List<ContactEntry> loadedImages = [];
		
		setState(() {
			_totalImagesToLoad = fileMap.length;
			_imagesLoaded = 0;
		});
		
		for (final entry in fileMap.entries) {
			final identifier = entry.key;
			final value = entry.value;
			// If the value is just a path string, create a minimal ContactEntry
			if (value is String) {
				loadedImages.add(ContactEntry(
					identifier: identifier,
					imagePath: value,
					dateFound: File(value).existsSync()
							? File(value).lastModifiedSync()
							: DateTime.now(),
					json: {'imagePath': value},
				));
			} else if (value is Map<String, dynamic>) {
				// If the value is a full contact JSON, use fromJson
				final imagePath = value['imagePath'] ?? '';
				loadedImages.add(ContactEntry.fromJson(
					identifier,
					imagePath,
					value,
				));
			}
			
			setState(() {
				_imagesLoaded++;
			});
			
			// Allow UI to update progressively every 10 images or at the end
			if (_imagesLoaded % 10 == 0 || _imagesLoaded == _totalImagesToLoad) {
				// Small delay to allow UI updates
				await Future.delayed(Duration(milliseconds: 1));
			}
		}
		allImages = loadedImages;
		_updateStates(allImages);
		await _restoreLastSelectedState();
		await _applyFiltersAndSort();
	}

		@override
		Widget build(BuildContext context) {
			// No nested MaterialApp. Use the app's root MaterialApp.
			final navContext = context;
			return Scaffold(
						appBar: AppBar(
							title: const Text('Image Gallery'),
							actions: [
								IconButton(
									tooltip: 'Switch to Legacy UI',
									icon: const Icon(Icons.swap_horiz),
									onPressed: () async {
										final proceed = await showDialog<bool>(
											context: navContext,
											builder: (dialogCtx) => AlertDialog(
												title: const Text('Confirm UI Switch'),
												content: const Text('Switch to legacy interface?'),
												actions: [
													TextButton(
														onPressed: () => Navigator.pop(dialogCtx, false),
														child: const Text('Cancel'),
													),
													TextButton(
														onPressed: () => Navigator.pop(dialogCtx, true),
														child: const Text('Switch'),
													),
												],
											),
										);
										if (proceed == true) {
											await UiMode.switchTo(false);
										}
									},
								),
								if (_isInitializing || _isLoadingImages)
									const Padding(
										padding: EdgeInsets.symmetric(horizontal: 16.0),
										child: SizedBox(
											width: 24,
											height: 24,
											child: CircularProgressIndicator(strokeWidth: 2),
										),
									)
								else
									// Persistent auth status icon (green if signed in, red if failed last attempt)
									FutureBuilder<bool>(
										future: CloudUtils.isSignedin(),
										builder: (ctx, snap) {
											final signed = snap.data == true;
											return Padding(
												padding: const EdgeInsets.symmetric(horizontal: 4.0),
												child: Icon(
													signed ? Icons.cloud_done : Icons.cloud_off,
													color: signed ? Colors.green : Colors.redAccent,
												),
											);
										},
									),
								if (!_isInitializing)
									IconButton(
										icon: const Icon(Icons.settings),
										tooltip: 'Settings',
										onPressed: () {
											Navigator.of(navContext).push(
												MaterialPageRoute(
													builder: (_) => SettingsScreen(
														onResetImportDir: _resetImportDir,
														onChangeImportDir: _changeImportDir,
														onRequestSignIn: () async {
															final ok = await _ensureSignedIn();
															if (!ok) {
																setState(() {
																	_initializationError = 'Sign-in failed';
																});
															}
															return ok;
														},
														onRequestSignOut: () async {
															try {
																await CloudUtils.signOut();
															} catch (_) {}
															setState(() {});
														},
														lastSyncTime: _lastSyncTime,
														syncing: _syncing,
														signInFailed: _initializationError != null,
													),
												),
											);
										},
									),
							],
						),
						body: _isInitializing
								? Center(
										child: Column(
											mainAxisAlignment: MainAxisAlignment.center,
											children: [
												const CircularProgressIndicator(),
												const SizedBox(height: 16),
												const Text('Signing in and setting up...'),
												if (_initializationError != null) ...[
													const SizedBox(height: 16),
													Padding(
														padding:
																const EdgeInsets.symmetric(horizontal: 16.0),
														child: Text(
															_initializationError!,
															style: const TextStyle(color: Colors.orange),
															textAlign: TextAlign.center,
														),
													),
												],
											],
										),
									)
								: LayoutBuilder(
										builder: (context, constraints) {
											final screenHeight = constraints.maxHeight;
											return Column(
												children: [
												if (_initializationError != null)
													_buildInitializationErrorBanner(context),
												if (_isLoadingImages)
													_buildImageLoadingBanner(),
													_buildControls(),
													Expanded(
														child: ImageGallery(
															images: images,
															selectedImages: selectedImages,
															sortOption: selectedSortOption,
															onImageSelected: (String id) {
																setState(() {
																	if (selectedImages.contains(id)) {
																		selectedImages.remove(id);
																	} else {
																		selectedImages.add(id);
																	}
																});
															},
															onMenuOptionSelected: _onMenuOptionSelected,
															galleryHeight: screenHeight,
															onPageChanged: (idx) =>
																	setState(() => currentIndex = idx),
															currentIndex: currentIndex,
														),
													),
												],
											);
										},
									),
						floatingActionButton: _isInitializing
								? null // Hide FAB during initialization
								: selectedImages.isNotEmpty
										? FloatingActionButton(
												onPressed: () => _onMenuOptionSelected('', 'move'),
												child: Icon(Icons.move_to_inbox),
											)
										: FloatingActionButton(
												onPressed: () => _importImages(navContext),
												tooltip: 'Import Images',
												child: Icon(Icons.add),
											),
						persistentFooterButtons: [
							SingleChildScrollView(
								scrollDirection: Axis.horizontal,
								child: Container(
									width: MediaQuery.of(navContext).size.width * 1.20,
									child: Row(
										mainAxisAlignment: MainAxisAlignment.spaceBetween,
										children: [
											SocialIcon.snapchatIconButton!,
											Spacer(),
											SocialIcon.galleryIconButton!,
											Spacer(),
											SocialIcon.bumbleIconButton!,
											Spacer(),
											FloatingActionButton(
												heroTag: null,
												tooltip: 'Change current directory',
												onPressed: _changeImportDir,
												child: Icon(Icons.drive_folder_upload),
											),
											Spacer(),
											SocialIcon.instagramIconButton!,
											Spacer(),
											SocialIcon.discordIconButton!,
											Spacer(),
											SocialIcon.kikIconButton!,
										],
									),
								),
							),
									],
							);
				}

	Widget _buildControls() {
		// Pull-to-refresh limited to this controls area only
		return RefreshIndicator(
			onRefresh: () => _forceSync(fromPull: true),
			displacement: 56,
			child: SingleChildScrollView(
				physics: const AlwaysScrollableScrollPhysics(),
				padding: EdgeInsets.zero,
				child: AnimatedSize(
					duration: const Duration(milliseconds: 300),
					child: _controlsExpanded
							? _buildExpandedControls()
							: _buildMinimizedControls(),
				),
			),
		);
	}

	Widget _buildExpandedControls() {
		return LayoutBuilder(builder: (context, constraints) {
			final isWide = constraints.maxWidth > 500;
			final children = <Widget>[
				Expanded(
					child: DropdownButtonFormField<String>(
						value: states.contains(selectedState) ? selectedState : null,
						isExpanded: true,
						decoration: InputDecoration(
							labelText: 'State',
							border: const OutlineInputBorder(),
							isDense: true,
						),
						items: states
								.map((dir) => DropdownMenuItem<String>(
											value: dir,
											child: Text(dir),
										))
								.toList(),
						onChanged: (value) async {
							selectedState = value!;
							await _saveLastSelectedState(selectedState);
							await _filterImages();
						},
					),
				),
				const SizedBox(width: 8),
				Expanded(
					flex: 2,
					child: TextField(
						decoration: InputDecoration(
							hintText: 'Search',
							prefixIcon: const Icon(Icons.search),
							border: const OutlineInputBorder(),
							isDense: true,
						),
						onChanged: (value) async {
							searchQuery = value;
							_searchDebounce?.cancel();
							_searchDebounce = Timer(const Duration(milliseconds: 220), () {
								if (!mounted) return;
								_filterImages();
							});
						},
					),
				),
				const SizedBox(width: 8),
				Expanded(
					child: DropdownButtonFormField<String>(
						value: selectedSortOption,
						isExpanded: true,
						decoration: InputDecoration(
							labelText: 'Sort by',
							border: const OutlineInputBorder(),
							isDense: true,
						),
						items: sortOptions
								.map((option) => DropdownMenuItem<String>(
											value: option,
											child: Text(option),
										))
								.toList(),
						onChanged: (value) async {
							selectedSortOption = value!;
							await _applyFiltersAndSort();
						},
					),
				),
				const SizedBox(width: 12),
				_buildOrderToggle(),
			];

			Widget content = isWide
					? Row(children: children)
					: Column(
							crossAxisAlignment: CrossAxisAlignment.stretch,
							children: [
								Row(children: children.sublist(0, 3)),
								const SizedBox(height: 12),
								Row(children: children.sublist(3)),
							],
						);

			return Card(
				margin: const EdgeInsets.all(12),
				elevation: 4,
				shape: RoundedRectangleBorder(
					borderRadius: BorderRadius.circular(16),
				),
				child: Padding(
					padding: const EdgeInsets.all(12.0),
					child: Stack(
						clipBehavior: Clip.none,
						children: [
							Padding(
								padding: const EdgeInsets.only(top: 8.0, right: 8.0),
								child: content,
							),
							Positioned(
								top: 0,
								right: 0,
								child: IconButton(
									icon: const Icon(Icons.expand_less),
									onPressed: () {
										setState(() => _controlsExpanded = false);
									},
								),
							),
						],
					),
				),
			);
		});
	}

	Widget _buildMinimizedControls() {
		return Card(
			margin: const EdgeInsets.all(12),
			elevation: 4,
			shape: RoundedRectangleBorder(
				borderRadius: BorderRadius.circular(16),
			),
			child: Padding(
				padding: const EdgeInsets.all(12.0),
				child: Row(
					children: [
						Expanded(
							child: DropdownButtonFormField<String>(
								value: sortOptions.contains(selectedSortOption)
										? selectedSortOption
										: null,
								isExpanded: true,
								decoration: const InputDecoration(
									labelText: 'Sort by',
									border: OutlineInputBorder(),
									isDense: true,
								),
								items: sortOptions
										.map((option) => DropdownMenuItem<String>(
													value: option,
													child: Text(option),
												))
										.toList(),
								onChanged: (value) async {
									selectedSortOption = value!;
									await _applyFiltersAndSort();
								},
							),
						),
						const SizedBox(width: 8),
						IconButton(
							icon: const Icon(Icons.expand_more),
							onPressed: () {
								setState(() => _controlsExpanded = true);
							},
						),
					],
				),
			),
		);
	}

	Widget _buildOrderToggle() {
		return Padding(
			padding: const EdgeInsets.symmetric(horizontal: 4.0),
			child: Ink(
				decoration: BoxDecoration(
					color: Colors.blue.withOpacity(0.1),
					shape: BoxShape.circle,
				),
				child: IconButton(
					icon: AnimatedRotation(
						turns: isAscending ? 0 : 0.5,
						duration: const Duration(milliseconds: 200),
						child: const Icon(Icons.arrow_upward, color: Colors.blue),
					),
					onPressed: () async {
						isAscending = !isAscending;
						await _applyFiltersAndSort();
					},
				),
			),
		);
	}

	Future<void> _filterImages() async {
		await _applyFiltersAndSort();
	}

	void _updateStates(List<ContactEntry> imgs) {
		final tags = <String>{};
		for (final img in imgs) {
			if (img.state != null) tags.add(img.state!);
		}
		final sorted = tags.toList()..sort();
		setState(() {
			states = ['All', ...sorted];
			if (!states.contains(selectedState)) {
				selectedState = 'All';
			}
		});
	}

	Future<void> _restoreLastSelectedState() async {
		final prefs = await SharedPreferences.getInstance();
		final last = prefs.getString(_lastStateKey);
		if (last != null && states.contains(last)) {
			selectedState = last;
		}
	}

	Future<void> _saveLastSelectedState(String value) async {
		final prefs = await SharedPreferences.getInstance();
		await prefs.setString(_lastStateKey, value);
	}

	Future<void> _loadImportDirectory() async {
		final prefs = await SharedPreferences.getInstance();
		_importDirPath = prefs.getString(_importDirKey);
	}

	Future<void> _saveImportDirectory(String path) async {
		final prefs = await SharedPreferences.getInstance();
		await prefs.setString(_importDirKey, path);
	}

	Future<void> _changeImportDir() async {
		final dir = await FilePicker.platform.getDirectoryPath();
		if (dir != null) {
			setState(() {
				_importDirPath = dir;
			});
			await _saveImportDirectory(dir);
		}
	}

	Future<void> _resetImportDir() async {
		final prefs = await SharedPreferences.getInstance();
		await prefs.remove(_importDirKey);
		setState(() {
			_importDirPath = null;
		});
	}

	Future<AssetPathEntity?> _getImportAlbum() async {
		if (_importDirPath == null) return null;
		final paths = await PhotoManager.getAssetPathList(
			type: RequestType.image,
			hasAll: true,
		);
		final dirName = path.basename(_importDirPath!);
		for (final p in paths) {
			if (p.name == dirName) {
				return p;
			}
		}
		return null;
	}

	/// Build a filter that restricts the picker to [_importDirPath].
	Future<PMFilter?> _buildImportFilter() async {
		if (_importDirPath == null) return null;
		final album = await _getImportAlbum();
		if (album == null) return null;
		if (Platform.isAndroid) {
			final id = album.id.replaceAll("'", "''");
			return CustomFilter.sql(
				where: "${CustomColumns.android.bucketId} = '$id'",
			);
		}
		return null;
	}

	Future<void> _applyFiltersAndSort() async {
		List<ContactEntry> filtered =
				SearchService.searchEntries(allImages, searchQuery)
						.where((img) {
			final tag = img.state ?? path.basename(path.dirname(img.imagePath));
			final matchesState = selectedState == 'All' || tag == selectedState;
			return matchesState;
		}).toList();

		int compare(ContactEntry a, ContactEntry b) {
			int result;
			switch (selectedSortOption) {
				case 'Date found':
					result = a.dateFound.compareTo(b.dateFound);
					break;
				case 'Size':
					result = File(a.imagePath)
							.lengthSync()
							.compareTo(File(b.imagePath).lengthSync());
					break;
				case 'Snap Added Date':
					DateTime aDate =
							a.dateAddedOnSnap ?? DateTime.fromMillisecondsSinceEpoch(0);
					DateTime bDate =
							b.dateAddedOnSnap ?? DateTime.fromMillisecondsSinceEpoch(0);
					result = aDate.compareTo(bDate);
					break;
				case 'Instagram Added Date':
					DateTime aDate =
							a.dateAddedOnInsta ?? DateTime.fromMillisecondsSinceEpoch(0);
					DateTime bDate =
							b.dateAddedOnInsta ?? DateTime.fromMillisecondsSinceEpoch(0);
					result = aDate.compareTo(bDate);
					break;
				case 'Added on Snapchat':
					result = (a.addedOnSnap ? 1 : 0).compareTo(b.addedOnSnap ? 1 : 0);
					break;
				case 'Added on Instagram':
					result = (a.addedOnInsta ? 1 : 0).compareTo(b.addedOnInsta ? 1 : 0);
					break;
				case 'Name':
				default:
					result =
							path.basename(a.imagePath).compareTo(path.basename(b.imagePath));
			}
			return isAscending ? result : -result;
		}

		filtered.sort(compare);

		setState(() {
			images = filtered;
			currentIndex = 0;
		});
		if (images.isNotEmpty) {
			if (kGalleryPageController.hasClients) {
				kGalleryPageController.jumpToPage(0);
			} else {
				WidgetsBinding.instance.addPostFrameCallback((_) {
					if (!mounted) return;
					if (kGalleryPageController.hasClients) {
						try {
							kGalleryPageController.jumpToPage(0);
						} catch (_) {}
					}
				});
			}
		}
	}

	Widget _buildInitializationErrorBanner(BuildContext context) {
		return Padding(
			padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
			child: Container(
				padding: const EdgeInsets.all(12),
				decoration: BoxDecoration(
					color: Colors.orange.shade50,
					borderRadius: BorderRadius.circular(8),
					border: Border.all(color: Colors.orange.shade300),
				),
				child: Row(
					crossAxisAlignment: CrossAxisAlignment.start,
					children: [
						const Icon(Icons.warning_amber_rounded, color: Colors.orange),
						const SizedBox(width: 8),
						Expanded(
							child: Text(
								_initializationError ?? 'Initialization error',
								style: TextStyle(color: Colors.orange.shade900),
							),
						),
						IconButton(
							tooltip: 'Dismiss',
							icon: const Icon(Icons.close, size: 18),
							onPressed: () => setState(() => _initializationError = null),
						),
					],
				),
			),
		);
	}

	/// Builds a banner showing image loading progress
	Widget _buildImageLoadingBanner() {
		final progress = _totalImagesToLoad > 0 
			? _imagesLoaded / _totalImagesToLoad 
			: 0.0;
		
		return Padding(
			padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
			child: Container(
				padding: const EdgeInsets.all(12),
				decoration: BoxDecoration(
					color: Colors.blue.shade50,
					borderRadius: BorderRadius.circular(8),
					border: Border.all(color: Colors.blue.shade300),
				),
				child: Row(
					children: [
						const SizedBox(
							width: 16,
							height: 16,
							child: CircularProgressIndicator(strokeWidth: 2),
						),
						const SizedBox(width: 12),
						Expanded(
							child: Column(
								crossAxisAlignment: CrossAxisAlignment.start,
								mainAxisSize: MainAxisSize.min,
								children: [
									Text(
										'Loading images... $_imagesLoaded/$_totalImagesToLoad',
										style: TextStyle(
											color: Colors.blue.shade900,
											fontWeight: FontWeight.w500,
										),
									),
									const SizedBox(height: 4),
									LinearProgressIndicator(
										value: progress,
										backgroundColor: Colors.blue.shade100,
										valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
									),
								],
							),
						),
					],
				),
			),
		);
	}

	Future<String?> _selectState(String currentState) async {
		String? selected = currentState.isNotEmpty
				? currentState
				: states.firstWhere(
						(s) => s != 'All',
						orElse: () => '',
					);
		final controller = TextEditingController(text: selected);

		final dialogCtx = _navigatorKey.currentContext ?? context;
		return showDialog<String>(
			context: dialogCtx,
			builder: (context) {
				return StatefulBuilder(
					builder: (context, setState) {
						return AlertDialog(
							title: const Text('Move to state'),
							content: SingleChildScrollView(
								child: Column(
									mainAxisSize: MainAxisSize.min,
									children: [
										if (currentState.isNotEmpty)
											Padding(
												padding: const EdgeInsets.only(bottom: 8.0),
												child: Row(
													children: [
														const Text('Current:'),
														const SizedBox(width: 4),
														Chip(
															label: Text(currentState),
															backgroundColor: Colors.grey.shade300,
														),
													],
												),
											),
										if (states.where((s) => s != 'All').isNotEmpty)
											Wrap(
												spacing: 6,
												children: [
													...states.where((s) => s != 'All').map(
																(s) => ChoiceChip(
																	label: Text(s),
																	selected: selected == s,
																	onSelected: (_) {
																		setState(() {
																			selected = s;
																			controller.text = s;
																		});
																	},
																),
															),
													const SizedBox(height: 8),
												],
											),
										TextField(
											controller: controller,
											decoration: const InputDecoration(labelText: 'State'),
										),
									],
								),
							),
							actions: [
								TextButton(
									onPressed: () => Navigator.pop(context),
									child: const Text('Cancel'),
								),
								TextButton(
									onPressed: () =>
											Navigator.pop(context, controller.text.trim()),
									child: const Text('OK'),
								),
							],
						);
					},
				);
			},
		);
	}

	Future<void> _onMenuOptionSelected(String imagePath, String option) async {
		if (option != 'move') return;
		final targets = <ContactEntry>[];

		if (selectedImages.isNotEmpty) {
			for (final id in selectedImages) {
				final match = allImages.where((e) => e.identifier == id);
				if (match.isNotEmpty) targets.add(match.first);
			}
		} else {
			final match = allImages.where((e) => e.imagePath == imagePath);
			if (match.isNotEmpty) targets.add(match.first);
		}

		if (targets.isEmpty) return;

		String currentState = '';
		if (targets.isNotEmpty) {
			final firstState = targets.first.state ?? '';
			if (targets.every((e) => e.state == firstState)) {
				currentState = firstState;
			}
		}

		final newState = await _selectState(currentState);
		if (newState == null || newState.isEmpty) return;

		setState(() {
			for (final entry in targets) {
				entry.state = newState;
			}
			selectedImages.clear();
		});

		_updateStates(allImages);
		await _applyFiltersAndSort();
	}

	Future<void> _importImages(BuildContext pickerContext) async {
		if (_importDirPath == null) {
			await _changeImportDir();
			if (_importDirPath == null) {
				ScaffoldMessenger.of(pickerContext).showSnackBar(
					const SnackBar(content: Text('No directory selected')),
				);
				return;
			}
		}
		final filter = await _buildImportFilter();
		final ps = await PhotoManager.requestPermissionExtend();
		if (ps != PermissionState.authorized && ps != PermissionState.limited) {
			ScaffoldMessenger.of(pickerContext).showSnackBar(
				const SnackBar(content: Text('Permission not granted')),
			);
			return;
		}

		final config = AssetPickerConfig(
			requestType: RequestType.image,
			filterOptions: filter,
			textDelegate: const EnglishAssetPickerTextDelegate(),
		);

		final List<AssetEntity>? assets = await AssetPicker.pickAssets(
			pickerContext,
			pickerConfig: config,
		);
		if (assets == null || assets.isEmpty) {
			ScaffoldMessenger.of(pickerContext).showSnackBar(
				const SnackBar(content: Text('No images selected')),
			);
			return;
		}

		final destDir = Directory('/storage/emulated/0/DCIM/Comb');
		await destDir.create(recursive: true);
		final messenger = ScaffoldMessenger.of(pickerContext);
		final total = assets.length;
		messenger.showSnackBar(
			SnackBar(
				duration: const Duration(hours: 1),
				content: Row(
					children: [
						const SizedBox(
							width: 20,
							height: 20,
							child: CircularProgressIndicator(),
						),
						const SizedBox(width: 16),
						Text('Importing images... 0/$total'),
					],
				),
			),
		);

		List<ContactEntry> newEntries = [];
		var processed = 0;

		for (final asset in assets) {
			try {
				final origin = await asset.originFile;
				if (origin == null) continue;

				final filename = path.basename(origin.path);
				final destPath = path.join(destDir.path, filename);

				if (File(destPath).existsSync()) {
					debugPrint('File already exists at $destPath, skipping');
					continue;
				}

				try {
					await origin.rename(destPath);
				} catch (_) {
					// Fall back to copy/delete if rename fails due to SAF restrictions
					await origin.copy(destPath);
					try {
						await origin.delete();
					} catch (_) {}
				}

				final id = path.basenameWithoutExtension(filename);
				final entry = ContactEntry(
					identifier: id,
					imagePath: destPath,
					dateFound: File(destPath).lastModifiedSync(),
					json: {SubKeys.State: 'Comb'},
				);

				final result =
						await ChatGPTService.processImage(imageFile: File(destPath));
				if (result != null) {
					postProcessChatGptResult(entry, result, save: false);
				}

				await StorageUtils.save(entry, backup: false);
				StorageUtils.filePaths[id] = destPath;
				newEntries.add(entry);
			} catch (e) {
				debugPrint('Failed to import ${asset.id}: $e');
			}

			processed++;
			messenger
				..hideCurrentSnackBar()
				..showSnackBar(
					SnackBar(
						duration: const Duration(hours: 1),
						content: Row(
							children: [
								const SizedBox(
									width: 20,
									height: 20,
									child: CircularProgressIndicator(),
								),
								const SizedBox(width: 16),
								Text('Importing images... $processed/$total'),
							],
						),
					),
				);
		}

		await StorageUtils.writeJson(StorageUtils.filePaths);

		if (newEntries.isNotEmpty) {
			setState(() {
				allImages.addAll(newEntries);
			});
			_updateStates(allImages);
			await _applyFiltersAndSort();
			await StorageUtils.syncLocalAndCloud();
		}

		messenger.hideCurrentSnackBar();
		final imported = newEntries.length;
		messenger.showSnackBar(
			SnackBar(
				content: Text(
					imported > 0
							? 'Imported $imported image${imported == 1 ? '' : 's'}'
							: 'No new images imported',
				),
			),
		);
	}
}

// Updated ImageGallery Widget
// ImageGallery and ImageTile widgets moved to lib/screens/gallery/widgets/

