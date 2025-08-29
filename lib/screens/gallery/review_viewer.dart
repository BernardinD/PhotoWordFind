// ignore_for_file: unused_field
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:PhotoWordFind/models/contactEntry.dart';
import 'package:PhotoWordFind/screens/gallery/widgets/handles_sheet.dart';
import 'package:PhotoWordFind/screens/gallery/redo_crop_screen.dart';
import 'package:PhotoWordFind/utils/chatgpt_post_utils.dart';
import 'package:PhotoWordFind/utils/storage_utils.dart';

class ReviewViewer extends StatefulWidget {
  final List<ContactEntry> images;
  final int initialIndex;
  final String sortOption;

  const ReviewViewer({super.key, required this.images, required this.initialIndex, required this.sortOption});

  @override
  State<ReviewViewer> createState() => _ReviewViewerState();
}

class _ReviewViewerState extends State<ReviewViewer> {
  late final PageController _pageController;
  late int _index;
  bool _editorOpen = false;
  bool _aimHighlight = false;
  double _aimY = 0.75; // normalized 0..1 from top
  double _dockPerc = 0.45; // 0..1 of screen height
  final double _dockMin = 0.22;
  final double _dockMid = 0.55;
  final double _dockMax = 0.92;
  ScrollController? _panelScroll;

  // Legacy compatibility: keep these fields to placate potential stale analyzer/build
  // references observed intermittently in test runs. They are not used in logic.
  int? _animatingIndex;
  Tween<double>? _scaleTween;
  Tween<Offset>? _posTween;

  // Note: This screen no longer uses legacy zoom animation fields. Keep a benign
  // constant animation to avoid any stale references in tooling caches.
  final Animation<double> _zoomAnim = const AlwaysStoppedAnimation<double>(1.0);

  ContactEntry get _current => widget.images[_index];

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.images.length - 1);
    _pageController = PageController(initialPage: _index);
    // Touch legacy fields in debug to keep analyzer/state consistent during hot test runs.
    // no-op: keep a reference alive for debug-only consistency
    assert(() {
      return _zoomAnim.value == 1.0;
    }());
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _showDetailsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final c = _current;
        return SafeArea(
          child: DraggableScrollableSheet(
            initialChildSize: 0.4,
            minChildSize: 0.25,
            maxChildSize: 0.9,
            expand: false,
            builder: (context, scroll) {
              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: ListView(
                  controller: scroll,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.description_outlined),
                        SizedBox(width: 8),
                        Text('Image Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        Spacer(),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('Full OCR/Text'),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(c.extractedText?.trim().isNotEmpty == true ? c.extractedText!.trim() : 'No text found'),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  // (legacy helper removed)

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Image viewer
            PageView.builder(
              controller: _pageController,
              itemCount: widget.images.length,
              onPageChanged: (i) => setState(() {
                _index = i;
                _aimHighlight = false; // reset aim when switching entries
                if (_editorOpen) {
                  _panelScroll?.dispose();
                  _panelScroll = ScrollController();
                }
              }),
              itemBuilder: (context, index) {
                final entry = widget.images[index];
                return PhotoView(
                  imageProvider: FileImage(File(entry.imagePath)),
                  backgroundDecoration: const BoxDecoration(color: Colors.black),
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: PhotoViewComputedScale.covered * 3.0,
                );
              },
            ),
            if (_editorOpen && _aimHighlight)
              Positioned.fill(
                child: _AimBandOverlay(centerY: _aimY, bandHeightFraction: 0.18),
              ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      color: Colors.white,
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    Text('${_index + 1} / ${widget.images.length}', style: const TextStyle(color: Colors.white)),
                    const Spacer(),
                    // Redo text extraction for the current item
                    IconButton(
                      tooltip: 'Redo text extraction',
                      color: Colors.white,
                      icon: const Icon(Icons.refresh),
                      onPressed: () async {
                        final entry = _current;
                        final result = await Navigator.of(context).push<Map<String, dynamic>>(
                          MaterialPageRoute(
                            builder: (_) => RedoCropScreen(
                              imageFile: File(entry.imagePath),
                              contact: entry,
                              initialAllowNameAgeUpdate: (entry.name == null || entry.name!.isEmpty || entry.age == null),
                            ),
                          ),
                        );
                        if (result != null) {
                          final response = result['response'] as Map<String, dynamic>?;
                          final allowNameAgeUpdate = result['allowNameAgeUpdate'] == true;
                          final didFullRedo = result['full'] == true;
                          if (response != null) {
                            setState(() {
                              postProcessChatGptResult(
                                entry,
                                response,
                                save: false,
                                allowNameAgeUpdate: allowNameAgeUpdate,
                              );
                            });
                            await StorageUtils.save(entry);
                            if (didFullRedo && mounted) {
                              ScaffoldMessenger.of(context).hideCurrentSnackBar();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Full file redo applied.')), 
                              );
                            }
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black54],
                    ),
                  ),
                  child: SizedBox(
                    height: 52,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Button row with reserved edge space for arrows
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 56.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: _showDetailsSheet,
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      minimumSize: const Size(0, 44),
                                    ),
                                    icon: const Icon(Icons.description_outlined),
                                    label: const FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text('Details'),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => setState(() => _editorOpen = !_editorOpen),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      side: const BorderSide(color: Colors.white70),
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      minimumSize: const Size(0, 44),
                                    ),
                                    icon: const Icon(Icons.manage_accounts),
                                    label: const FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text('Handles'),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            color: Colors.white,
                            icon: const Icon(Icons.chevron_left, size: 30),
                            onPressed: _index > 0
                                ? () => _pageController.animateToPage(_index - 1, duration: const Duration(milliseconds: 200), curve: Curves.easeOut)
                                : null,
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            color: Colors.white,
                            icon: const Icon(Icons.chevron_right, size: 30),
                            onPressed: _index < widget.images.length - 1
                                ? () => _pageController.animateToPage(_index + 1, duration: const Duration(milliseconds: 200), curve: Curves.easeOut)
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_editorOpen)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: MediaQuery.of(context).size.height * _dockPerc,
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).canvasColor,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 12, offset: const Offset(0, -2))],
                  ),
                  child: Column(
                    children: [
                      // Drag handle area: only this area resizes the panel
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragUpdate: (d) {
                          final h = MediaQuery.of(context).size.height;
                          setState(() {
                            _dockPerc = (_dockPerc - d.primaryDelta! / h).clamp(_dockMin, _dockMax);
                          });
                        },
                        onVerticalDragEnd: (_) {
                          // snap to nearest
                          final targets = [_dockMin, _dockMid, _dockMax];
                          double closest = targets.first;
                          for (final t in targets) {
                            if ((t - _dockPerc).abs() < (closest - _dockPerc).abs()) closest = t;
                          }
                          setState(() => _dockPerc = closest);
                          // light haptic
                          // ignore: deprecated_member_use
                          Feedback.forTap(context);
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(top: 6, bottom: 8),
                          child: Column(
                            children: [
                              Container(
                                width: 36,
                                height: 4,
                                decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
                              ),
                              const SizedBox(height: 6),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                                child: Row(
                                  children: [
                                    const Icon(Icons.manage_accounts),
                                    const SizedBox(width: 8),
                                    const Text('Handles & Verification', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                                    const Spacer(),
                                    TextButton(
                                      onPressed: () => setState(() => _editorOpen = false),
                                      child: const Text('Hide'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: HandlesEditorPanel(
                          key: ValueKey(widget.images[_index].imagePath),
                          contact: _current,
                          scrollController: _panelScroll ??= ScrollController(),
                          showHeader: false,
                          onAim: (y) => setState(() => _aimY = y),
                          onAimHighlight: (v) => setState(() => _aimHighlight = v),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AimBandOverlay extends StatelessWidget {
  final double centerY; // 0..1
  final double bandHeightFraction; // 0..1
  const _AimBandOverlay({required this.centerY, this.bandHeightFraction = 0.2});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _AimBandPainter(centerY: centerY, bandHeightFraction: bandHeightFraction),
    );
  }
}

class _AimBandPainter extends CustomPainter {
  final double centerY;
  final double bandHeightFraction;
  _AimBandPainter({required this.centerY, required this.bandHeightFraction});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black54;
    final rect = Offset.zero & size;
    final bandHeight = size.height * bandHeightFraction;
    final center = size.height * centerY;
    final bandRect = Rect.fromLTWH(0, (center - bandHeight / 2).clamp(0.0, size.height - bandHeight), size.width, bandHeight);

    // Darken whole screen
    canvas.drawRect(rect, paint);
    // Clear a horizontal band
    final clearPaint = Paint()..blendMode = BlendMode.clear;
    canvas.saveLayer(rect, Paint());
    canvas.drawRect(rect, paint);
    canvas.drawRect(bandRect, clearPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AimBandPainter old) {
    return old.centerY != centerY || old.bandHeightFraction != bandHeightFraction;
  }
}
