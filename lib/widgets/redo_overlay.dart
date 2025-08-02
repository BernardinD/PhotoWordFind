import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;

/// Full screen overlay for redoing text extraction on a selected region.
///
/// Displays the [image] with zoom and pan controls and allows the user to
/// resize a crop box. When the user taps **Redo** the cropped bytes are
/// returned via [onCropped].
class RedoOverlay extends StatefulWidget {
  const RedoOverlay({
    super.key,
    required this.image,
    required this.onCropped,
  });

  final ImageProvider image;
  final void Function(Uint8List) onCropped;

  @override
  State<RedoOverlay> createState() => _RedoOverlayState();
}

class _RedoOverlayState extends State<RedoOverlay> {
  final TransformationController _controller = TransformationController();
  final GlobalKey _repaintKey = GlobalKey();

  // Crop rectangle state
  late Rect _cropRect;
  // Used to hide the overlay chrome when capturing the screenshot
  bool _hideUi = false;

  // Drag handling
  Offset? _dragStart;
  Rect? _startingRect;
  late Size _screenSize;

  static const double _minSize = 50.0;
  static const double _handleSize = 20.0;

  @override
  void initState() {
    super.initState();
    // Default crop rect is a centered square taking up 60% of width
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _screenSize = MediaQuery.of(context).size;
      final double side = _screenSize.width * 0.6;
      setState(() {
        _cropRect = Rect.fromCenter(
          center: _screenSize.center(Offset.zero),
          width: side,
          height: side,
        );
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _pointInRect(Offset p, Rect rect) =>
      p.dx >= rect.left &&
      p.dx <= rect.right &&
      p.dy >= rect.top &&
      p.dy <= rect.bottom;

  void _startDrag(DragStartDetails d) {
    _dragStart = d.localPosition;
    _startingRect = _cropRect;
  }

  void _updateDrag(DragUpdateDetails d) {
    if (_dragStart == null || _startingRect == null) return;
    final Offset delta = d.localPosition - _dragStart!;
    Rect newRect = _startingRect!.shift(delta);
    // Keep the rect within screen bounds
    newRect = Rect.fromLTWH(
      newRect.left.clamp(0.0, _screenSize.width - newRect.width),
      newRect.top.clamp(0.0, _screenSize.height - newRect.height),
      newRect.width,
      newRect.height,
    );
    setState(() => _cropRect = newRect);
  }

  void _endDrag(_) {
    _dragStart = null;
    _startingRect = null;
  }

  void _resizeRect(DragUpdateDetails d, Alignment handle) {
    double left = _cropRect.left;
    double top = _cropRect.top;
    double right = _cropRect.right;
    double bottom = _cropRect.bottom;

    if (handle.x < 0) {
      left += d.delta.dx;
    } else if (handle.x > 0) {
      right += d.delta.dx;
    }
    if (handle.y < 0) {
      top += d.delta.dy;
    } else if (handle.y > 0) {
      bottom += d.delta.dy;
    }

    double width = (right - left).clamp(_minSize, _screenSize.width);
    double height = (bottom - top).clamp(_minSize, _screenSize.height);

    // Ensure handles stay within bounds
    left = left.clamp(0.0, _screenSize.width - width);
    top = top.clamp(0.0, _screenSize.height - height);

    setState(() {
      _cropRect = Rect.fromLTWH(left, top, width, height);
    });
  }

  Future<void> _redo() async {
    setState(() => _hideUi = true);
    await Future.delayed(const Duration(milliseconds: 20));

    final boundary =
        _repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final pixelRatio = MediaQuery.of(context).devicePixelRatio;
    final ui.Image fullImage = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData =
        await fullImage.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;
    Uint8List bytes = byteData.buffer.asUint8List();

    // Crop the captured image using the crop rect
    final img.Image decoded = img.decodeImage(bytes)!;
    final int left = (_cropRect.left * pixelRatio).round();
    final int top = (_cropRect.top * pixelRatio).round();
    final int width = (_cropRect.width * pixelRatio).round();
    final int height = (_cropRect.height * pixelRatio).round();
    final img.Image cropped = img.copyCrop(
      decoded,
      x: left.clamp(0, decoded.width - 1),
      y: top.clamp(0, decoded.height - 1),
      width: width.clamp(1, decoded.width - left),
      height: height.clamp(1, decoded.height - top),
    );

    final Uint8List croppedBytes = Uint8List.fromList(img.encodePng(cropped));
    widget.onCropped(croppedBytes);
    if (mounted) Navigator.of(context).pop();
    setState(() => _hideUi = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: RepaintBoundary(
        key: _repaintKey,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: _controller,
                minScale: 1,
                maxScale: 5,
                child: Image(
                  image: widget.image,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            if (!_hideUi) ...[
              // dim outside area
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _OverlayPainter(_cropRect),
                  ),
                ),
              ),
              // move area
              Positioned.fromRect(
                rect: _cropRect,
                child: GestureDetector(
                  onPanStart: _startDrag,
                  onPanUpdate: _updateDrag,
                  onPanEnd: _endDrag,
                ),
              ),
              // handles
              for (final alignment in [
                Alignment.topLeft,
                Alignment.topRight,
                Alignment.bottomLeft,
                Alignment.bottomRight
              ])
                _buildHandle(alignment),
            ],
            // Action bar
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Theme.of(context).colorScheme.surface,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: _redo,
                      child: const Text('Redo'),
                    ),
                  ],
                ),
              ),
            ),
            // Cancel by tapping outside image
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapUp: (d) {
                  if (!_pointInRect(d.localPosition, _cropRect)) {
                    Navigator.of(context).pop();
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHandle(Alignment alignment) {
    final double left = alignment.x < 0
        ? _cropRect.left - _handleSize / 2
        : _cropRect.right - _handleSize / 2;
    final double top = alignment.y < 0
        ? _cropRect.top - _handleSize / 2
        : _cropRect.bottom - _handleSize / 2;
    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onPanUpdate: (d) => _resizeRect(d, alignment),
        child: Container(
          width: _handleSize,
          height: _handleSize,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.rectangle,
          ),
        ),
      ),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  final Rect rect;

  _OverlayPainter(this.rect);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.fill;
    final path = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRect(rect),
    );
    canvas.drawPath(path, paint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawRect(rect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter oldDelegate) =>
      oldDelegate.rect != rect;
}

