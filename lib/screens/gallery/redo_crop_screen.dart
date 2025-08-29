import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';

import 'package:PhotoWordFind/services/chat_gpt_service.dart';
import 'package:PhotoWordFind/models/contactEntry.dart';

class RedoCropScreen extends StatefulWidget {
	const RedoCropScreen({super.key, required this.imageFile, this.initialAllowNameAgeUpdate, this.contact, this.forceShowFullRedo = false});


	final File imageFile;
	final bool? initialAllowNameAgeUpdate;
	final ContactEntry? contact;
	// Testing aid: when true, always expose a top-right Full redo action
	final bool forceShowFullRedo;

	@override
	State<RedoCropScreen> createState() => _RedoCropScreenState();
}

class _RedoCropScreenState extends State<RedoCropScreen> {
	final PhotoViewController _photoController = PhotoViewController();
	bool _processing = false;
	static bool _hintShown = false;
	late bool _showHint;
	// One-time override: allow updating name/age from this redo
	bool _allowNameAgeUpdate = false;
	// Session-only preference to skip the full redo confirmation
	static bool _skipFullRedoConfirm = false;
  
		bool get _shouldShowFullRedo {
			final c = widget.contact;
			if (c == null) return false;
			final hasText = (c.extractedText?.trim().isNotEmpty ?? false);
			final hasName = (c.name?.trim().isNotEmpty ?? false);
			final hasAge = c.age != null;
			final hasSnap = (c.snapUsername?.trim().isNotEmpty ?? false);
			final hasInsta = (c.instaUsername?.trim().isNotEmpty ?? false);
			final hasDiscord = (c.discordUsername?.trim().isNotEmpty ?? false);
			final hasSections = (c.sections?.isNotEmpty ?? false);
			// Show only when we believe prior OCR/import yielded nothing meaningful
			return !(hasText || hasName || hasAge || hasSnap || hasInsta || hasDiscord || hasSections);
		}
  
	// Crop area state
	Rect _cropRect = const Rect.fromLTWH(50, 100, 200, 200);
	bool _isDragging = false;
	bool _isResizing = false;
	Offset? _dragStart;
	String? _resizeHandle; // 'tl', 'tr', 'bl', 'br' for corners

	@override
	void initState() {
		super.initState();
		_showHint = !_hintShown;
		_hintShown = true;
    _allowNameAgeUpdate = widget.initialAllowNameAgeUpdate ?? false;
    
		// Set initial crop area to center of screen
		WidgetsBinding.instance.addPostFrameCallback((_) {
			final size = MediaQuery.of(context).size;
			setState(() {
				_cropRect = Rect.fromCenter(
					center: Offset(size.width / 2, size.height / 2),
					width: size.width * 0.6,
					height: size.height * 0.3,
				);
			});
		});
	}	@override
	void dispose() {
		_photoController.dispose();
		super.dispose();
	}

	Future<void> _captureCroppedArea() async {
		setState(() => _processing = true);
    
		try {
			// Load the original image
			final imageBytes = await widget.imageFile.readAsBytes();
			final codec = await ui.instantiateImageCodec(imageBytes);
			final frame = await codec.getNextFrame();
			final originalImage = frame.image;
      
			// Get screen dimensions
			final screenSize = MediaQuery.of(context).size;
      
			// Calculate the actual image dimensions and position on screen
			// PhotoView uses "contained" scale by default, so image fits within screen
			final imageAspectRatio = originalImage.width / originalImage.height;
			final screenAspectRatio = screenSize.width / screenSize.height;
      
			late double imageWidthOnScreen;
			late double imageHeightOnScreen;
			late double imageLeftOnScreen;
			late double imageTopOnScreen;
      
			if (imageAspectRatio > screenAspectRatio) {
				// Image is wider than screen ratio - fits by width
				imageWidthOnScreen = screenSize.width;
				imageHeightOnScreen = screenSize.width / imageAspectRatio;
				imageLeftOnScreen = 0;
				imageTopOnScreen = (screenSize.height - imageHeightOnScreen) / 2;
			} else {
				// Image is taller than screen ratio - fits by height
				imageWidthOnScreen = screenSize.height * imageAspectRatio;
				imageHeightOnScreen = screenSize.height;
				imageLeftOnScreen = (screenSize.width - imageWidthOnScreen) / 2;
				imageTopOnScreen = 0;
			}
      
			// Convert crop rect from screen coordinates to image coordinates
			final cropLeft = (_cropRect.left - imageLeftOnScreen) / imageWidthOnScreen;
			final cropTop = (_cropRect.top - imageTopOnScreen) / imageHeightOnScreen;
			final cropWidth = _cropRect.width / imageWidthOnScreen;
			final cropHeight = _cropRect.height / imageHeightOnScreen;
      
			// Clamp values to valid range
			final clampedLeft = math.max(0.0, math.min(1.0, cropLeft));
			final clampedTop = math.max(0.0, math.min(1.0, cropTop));
			final clampedRight = math.max(0.0, math.min(1.0, cropLeft + cropWidth));
			final clampedBottom = math.max(0.0, math.min(1.0, cropTop + cropHeight));
      
			// Convert to pixel coordinates
			final pixelLeft = (clampedLeft * originalImage.width).round();
			final pixelTop = (clampedTop * originalImage.height).round();
			final pixelRight = (clampedRight * originalImage.width).round();
			final pixelBottom = (clampedBottom * originalImage.height).round();
      
			final cropRect = Rect.fromLTRB(
				pixelLeft.toDouble(),
				pixelTop.toDouble(), 
				pixelRight.toDouble(),
				pixelBottom.toDouble(),
			);
      
			// Crop the image
			final croppedImage = await _cropImage(imageBytes, cropRect);
      
			// Save cropped image
			final dir = await getTemporaryDirectory();
			final file = await File('${dir.path}/redo.png').create();
			await file.writeAsBytes(croppedImage);

			final response = await ChatGPTService.processImage(imageFile: file);
			if (!mounted) return;
			Navigator.pop(context, {
          'response': response,
          'allowNameAgeUpdate': _allowNameAgeUpdate,
        });
		} catch (e) {
			if (mounted) {
				ScaffoldMessenger.of(context).showSnackBar(
					SnackBar(content: Text('Failed to process crop: $e')),
				);
			}
		} finally {
			if (mounted) {
				setState(() => _processing = false);
			}
		}
	}

	Future<void> _redoFullImage() async {
		setState(() => _processing = true);
		try {
			final response = await ChatGPTService.processImage(imageFile: widget.imageFile);
			if (!mounted) return;
			Navigator.pop(context, {
				'response': response,
				'allowNameAgeUpdate': _allowNameAgeUpdate,
				'full': true,
			});
		} catch (e) {
			if (mounted) {
				ScaffoldMessenger.of(context).showSnackBar(
					SnackBar(content: Text('Failed to reprocess image: $e')),
				);
			}
		} finally {
			if (mounted) setState(() => _processing = false);
		}
	}

	Future<void> _confirmAndRedoFullImage() async {
		if (_skipFullRedoConfirm) {
			return _redoFullImage();
		}
		bool dontAskAgain = false;
		final confirmed = await showDialog<bool>(
			context: context,
			builder: (ctx) {
				return AlertDialog(
					title: const Text('Run full file redo?'),
					content: Column(
						mainAxisSize: MainAxisSize.min,
						crossAxisAlignment: CrossAxisAlignment.start,
						children: [
							const Text(
								'This reprocesses the entire image from the top of the OCR workflow. Use when the initial import missed content. It can be slower and uses more quota.'),
							const SizedBox(height: 12),
							StatefulBuilder(
								builder: (context, setSB) => CheckboxListTile(
									value: dontAskAgain,
									onChanged: (v) => setSB(() => dontAskAgain = v ?? false),
									contentPadding: EdgeInsets.zero,
									title: const Text("Don't ask again for this session"),
									controlAffinity: ListTileControlAffinity.leading,
								),
							),
						],
					),
					actions: [
						TextButton(
							onPressed: () => Navigator.pop(ctx, false),
							child: const Text('Cancel'),
						),
						FilledButton(
							onPressed: () => Navigator.pop(ctx, true),
							child: const Text('Run full redo'),
						),
					],
				);
			},
		);
		if (confirmed == true) {
			if (dontAskAgain) _skipFullRedoConfirm = true;
			await _redoFullImage();
		}
	}

	Future<Uint8List> _cropImage(Uint8List imageBytes, Rect cropRect) async {
		final codec = await ui.instantiateImageCodec(imageBytes);
		final frame = await codec.getNextFrame();
		final image = frame.image;
    
		final recorder = ui.PictureRecorder();
		final canvas = Canvas(recorder);
    
		// Draw the cropped portion
		canvas.drawImageRect(
			image,
			cropRect,
			Rect.fromLTWH(0, 0, cropRect.width, cropRect.height),
			Paint(),
		);
    
		final picture = recorder.endRecording();
		final croppedImage = await picture.toImage(cropRect.width.round(), cropRect.height.round());
		final byteData = await croppedImage.toByteData(format: ui.ImageByteFormat.png);
    
		image.dispose();
		croppedImage.dispose();
    
		return byteData!.buffer.asUint8List();
	}

	@override
	Widget build(BuildContext context) {
		return Scaffold(
			backgroundColor: Colors.black,
			body: Stack(
				children: [
					// Interactive PhotoView background
					PhotoView(
						imageProvider: FileImage(widget.imageFile),
						backgroundDecoration: const BoxDecoration(color: Colors.black),
						minScale: PhotoViewComputedScale.contained * 0.8,
						maxScale: PhotoViewComputedScale.covered * 3.0,
						controller: _photoController,
						enableRotation: false,
							filterQuality: FilterQuality.high,
						),

						Positioned.fill(
							child: GestureDetector(
								onPanStart: (details) {
									final localPosition = details.localPosition;
									final handle = _getResizeHandle(localPosition);
									if (handle != null) {
										setState(() {
											_isResizing = true;
											_resizeHandle = handle;
											_dragStart = localPosition;
										});
									} else if (_cropRect.contains(localPosition)) {
										setState(() {
											_isDragging = true;
											_dragStart = localPosition;
										});
									}
								},
								onPanUpdate: (details) {
									if (_isDragging && _dragStart != null) {
										final delta = details.localPosition - _dragStart!;
										setState(() {
											_cropRect = _cropRect.translate(delta.dx, delta.dy);
											_dragStart = details.localPosition;
										});
									} else if (_isResizing && _dragStart != null && _resizeHandle != null) {
										_handleResize(details.localPosition);
									}
								},
								onPanEnd: (details) {
									setState(() {
										_isDragging = false;
										_isResizing = false;
										_dragStart = null;
										_resizeHandle = null;
									});
								},
								child: CustomPaint(
									painter: CropOverlayPainter(_cropRect, _isResizing, _resizeHandle),
									child: Container(),
								),
							),
						),
          
					if (_showHint)
						Positioned(
							top: 60,
							left: 16,
							right: 16,
							child: Container(
								padding: const EdgeInsets.all(12),
								decoration: BoxDecoration(
									color: Colors.black87,
									borderRadius: BorderRadius.circular(8),
								),
								child: Column(
									mainAxisSize: MainAxisSize.min,
									children: [
										const Text(
											'📱 Pinch to zoom, drag to move image',
											style: TextStyle(color: Colors.white, fontSize: 14),
											textAlign: TextAlign.center,
										),
										const SizedBox(height: 4),
										const Text(
											'✂️ Drag crop area to move, drag corners to resize',
											style: TextStyle(color: Colors.white, fontSize: 14),
											textAlign: TextAlign.center,
										),
										const SizedBox(height: 8),
										GestureDetector(
											onTap: () => setState(() => _showHint = false),
											child: const Text(
												'Got it!',
												style: TextStyle(color: Colors.blue, fontSize: 14, fontWeight: FontWeight.bold),
											),
										),
									],
								),
							),
						),

					// Top-right test access to Full redo so it's always reachable during testing
					if (widget.forceShowFullRedo || kDebugMode)
						Positioned(
							top: MediaQuery.of(context).padding.top + 8,
							right: 8,
							child: SafeArea(
								child: Tooltip(
									message: 'Full file redo (test access)',
									child: Material(
										color: Colors.transparent,
										child: IconButton(
											icon: const Icon(Icons.autorenew, color: Colors.white),
											onPressed: _processing ? null : _confirmAndRedoFullImage,
											tooltip: 'Full file redo',
										),
									),
								),
							),
						),
          
					// Control buttons
					Align(
						alignment: Alignment.bottomCenter,
						child: Container(
							margin: const EdgeInsets.all(16),
							padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
							decoration: BoxDecoration(
								color: Colors.black87,
								borderRadius: BorderRadius.circular(25),
							),
							child: _processing
									? const SizedBox(
											height: 40,
											child: Row(
												mainAxisSize: MainAxisSize.min,
												children: [
													CircularProgressIndicator(strokeWidth: 2),
													SizedBox(width: 12),
													Text('Processing...', style: TextStyle(color: Colors.white)),
												],
											),
										)
									: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Only show toggle if name or age are missing
                      if (widget.contact != null && 
                          (widget.contact!.name == null || widget.contact!.name!.isEmpty || widget.contact!.age == null))
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Switch(
                                  value: _allowNameAgeUpdate,
                                  onChanged: (v) => setState(() => _allowNameAgeUpdate = v),
                                ),
                                const SizedBox(width: 8),
                                const Flexible(
                                  child: Text(
                                    'Allow updating name/age from this redo',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton.icon(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close, color: Colors.white),
                            label: const Text('Cancel', style: TextStyle(color: Colors.white)),
                          ),
                          const SizedBox(width: 16),
								ElevatedButton.icon(
									onPressed: _processing ? null : _captureCroppedArea,
									icon: const Icon(Icons.crop),
									label: const Text('Redo (Crop)'),
									style: ElevatedButton.styleFrom(
										backgroundColor: Colors.blue,
										foregroundColor: Colors.white,
									),
								),
								const SizedBox(width: 12),
													if (_shouldShowFullRedo)
														Tooltip(
															message: 'Rarely needed. Use if auto import missed content. Slower and uses more quota.',
															child: OutlinedButton.icon(
																onPressed: _processing ? null : _confirmAndRedoFullImage,
																icon: const Icon(Icons.autorenew, color: Colors.white),
																label: const Text('Full file redo', style: TextStyle(color: Colors.white)),
																style: OutlinedButton.styleFrom(
																	side: const BorderSide(color: Colors.white70),
																),
															),
														),
                        ],
                      ),
                    ],
                  ),
						),
					),
				],
			),
		);
	}

	String? _getResizeHandle(Offset position) {
		const handleSize = 20.0;
    
		// Check corners for resize handles
		if ((position - _cropRect.topLeft).distance <= handleSize) {
			return 'tl'; // top-left
		}
		if ((position - _cropRect.topRight).distance <= handleSize) {
			return 'tr'; // top-right
		}
		if ((position - _cropRect.bottomLeft).distance <= handleSize) {
			return 'bl'; // bottom-left
		}
		if ((position - _cropRect.bottomRight).distance <= handleSize) {
			return 'br'; // bottom-right
		}
    
		return null;
	}

	void _handleResize(Offset currentPosition) {
		final delta = currentPosition - _dragStart!;
    
		setState(() {
			switch (_resizeHandle) {
				case 'tl':
					_cropRect = Rect.fromLTRB(
						_cropRect.left + delta.dx,
						_cropRect.top + delta.dy,
						_cropRect.right,
						_cropRect.bottom,
					);
					break;
				case 'tr':
					_cropRect = Rect.fromLTRB(
						_cropRect.left,
						_cropRect.top + delta.dy,
						_cropRect.right + delta.dx,
						_cropRect.bottom,
					);
					break;
				case 'bl':
					_cropRect = Rect.fromLTRB(
						_cropRect.left + delta.dx,
						_cropRect.top,
						_cropRect.right,
						_cropRect.bottom + delta.dy,
					);
					break;
				case 'br':
					_cropRect = Rect.fromLTRB(
						_cropRect.left,
						_cropRect.top,
						_cropRect.right + delta.dx,
						_cropRect.bottom + delta.dy,
					);
					break;
			}
      
			// Ensure minimum size
			const minSize = 50.0;
			if (_cropRect.width < minSize || _cropRect.height < minSize) {
				final center = _cropRect.center;
				_cropRect = Rect.fromCenter(
					center: center,
					width: math.max(_cropRect.width, minSize),
					height: math.max(_cropRect.height, minSize),
				);
			}
      
			_dragStart = currentPosition;
		});
	}
}

// Custom painter for the crop overlay
class CropOverlayPainter extends CustomPainter {
	final Rect cropRect;
	final bool isResizing;
	final String? resizeHandle;
  
	CropOverlayPainter(this.cropRect, this.isResizing, this.resizeHandle);
  
	@override
	void paint(Canvas canvas, Size size) {
		// Draw overlay outside crop area
		final overlayPaint = Paint()
			..color = Colors.black54
			..style = PaintingStyle.fill;
    
		final path = Path()
			..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
			..addRect(cropRect)
			..fillType = PathFillType.evenOdd;
    
		canvas.drawPath(path, overlayPaint);
    
		// Draw crop border
		final borderPaint = Paint()
			..color = Colors.white
			..style = PaintingStyle.stroke
			..strokeWidth = 2.0;
    
		canvas.drawRect(cropRect, borderPaint);
    
		// Draw corner handles
		final handlePaint = Paint()
			..color = isResizing ? Colors.blue : Colors.white
			..style = PaintingStyle.fill;
    
		final handleBorderPaint = Paint()
			..color = Colors.black
			..style = PaintingStyle.stroke
			..strokeWidth = 1.0;
    
		const handleSize = 12.0;
		final corners = [
			(cropRect.topLeft, 'tl'),
			(cropRect.topRight, 'tr'),
			(cropRect.bottomLeft, 'bl'),
			(cropRect.bottomRight, 'br'),
		];
    
		for (final (corner, handle) in corners) {
			final isActiveHandle = handle == resizeHandle;
			final paint = isActiveHandle ? 
				(Paint()..color = Colors.blue..style = PaintingStyle.fill) : 
				handlePaint;
      
			canvas.drawCircle(corner, handleSize, paint);
			canvas.drawCircle(corner, handleSize, handleBorderPaint);
      
			// Draw inner dot for better visibility
			final innerPaint = Paint()
				..color = isActiveHandle ? Colors.white : Colors.black
				..style = PaintingStyle.fill;
			canvas.drawCircle(corner, handleSize * 0.3, innerPaint);
		}
    
		// Draw grid lines for better cropping guidance
		final gridPaint = Paint()
			..color = Colors.white.withOpacity(0.3)
			..style = PaintingStyle.stroke
			..strokeWidth = 1.0;
    
		// Rule of thirds lines
		final thirdWidth = cropRect.width / 3;
		final thirdHeight = cropRect.height / 3;
    
		// Vertical lines
		canvas.drawLine(
			Offset(cropRect.left + thirdWidth, cropRect.top),
			Offset(cropRect.left + thirdWidth, cropRect.bottom),
			gridPaint,
		);
		canvas.drawLine(
			Offset(cropRect.left + 2 * thirdWidth, cropRect.top),
			Offset(cropRect.left + 2 * thirdWidth, cropRect.bottom),
			gridPaint,
		);
    
		// Horizontal lines
		canvas.drawLine(
			Offset(cropRect.left, cropRect.top + thirdHeight),
			Offset(cropRect.right, cropRect.top + thirdHeight),
			gridPaint,
		);
		canvas.drawLine(
			Offset(cropRect.left, cropRect.top + 2 * thirdHeight),
			Offset(cropRect.right, cropRect.top + 2 * thirdHeight),
			gridPaint,
		);
	}
  
	@override
	bool shouldRepaint(CropOverlayPainter oldDelegate) {
		return oldDelegate.cropRect != cropRect || 
					 oldDelegate.isResizing != isResizing ||
					 oldDelegate.resizeHandle != resizeHandle;
	}
}

