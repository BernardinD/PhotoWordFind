// ignore_for_file: unused_field
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:PhotoWordFind/models/contactEntry.dart';
import 'package:PhotoWordFind/screens/gallery/widgets/handles_sheet.dart';
import 'package:PhotoWordFind/screens/gallery/redo_crop_screen.dart';
import 'package:PhotoWordFind/utils/chatgpt_post_utils.dart';
import 'package:PhotoWordFind/services/redo_job_manager.dart';
import 'package:PhotoWordFind/utils/storage_utils.dart';
import 'package:intl/intl.dart';

// Lightweight tuple for platform label and associated date
class _SocialPlatform {
  final String label;
  final DateTime? when;
  const _SocialPlatform(this.label, this.when);
}

class ReviewViewer extends StatefulWidget {
  final List<ContactEntry> images;
  final int initialIndex;
  final String sortOption;

  const ReviewViewer(
      {super.key,
      required this.images,
      required this.initialIndex,
      required this.sortOption});

  @override
  State<ReviewViewer> createState() => _ReviewViewerState();
}

class _ReviewViewerState extends State<ReviewViewer> {
  late final PageController _pageController;
  late int _index;
  bool _editorOpen = false;
  bool _aimHighlight = false;
  bool _metaExpanded = false;
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
                        Text('Image Details',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                        Spacer(),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildMetaRows(c),
                    const SizedBox(height: 12),
                    const Text('Full OCR/Text'),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                          c.extractedText?.trim().isNotEmpty == true
                              ? c.extractedText!.trim()
                              : 'No text found'),
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

  // --- Metadata helpers shared by overlay and details sheet ---
  Widget _buildMetaRows(ContactEntry c) {
    final rows = <Widget>[];
    rows.add(_metaRow('Name', _bestName(c)));
    final offsetLabel = _bestOffsetLabel(c);
    if (offsetLabel != null) rows.add(_metaRow('Time offset', offsetLabel));
    final platformAtDate = _platformAtDate(c);
    if (platformAtDate != null) rows.add(_metaRow('Platform @ date', platformAtDate));
    rows.add(_metaRow('Date found', DateFormat.yMd().format(c.dateFound)));
    return Column(children: rows);
  }

  Widget _metaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _bestName(ContactEntry c) {
    final n = c.name?.trim();
    if (n != null && n.isNotEmpty) return n;
    return File(c.imagePath).uri.pathSegments.isNotEmpty
        ? File(c.imagePath).uri.pathSegments.last
        : c.identifier;
  }

  String? _bestOffsetLabel(ContactEntry c) {
    final loc = c.location;
    if (loc == null) return null;
    final rel = _formatRelativeOffset(loc.utcOffset);
    if (rel != null) return rel;
    return _formatUtcOffset(loc.utcOffset);
  }

  String? _platformAtDate(ContactEntry c) {
    // Priority: verified first, then added, then any handle present
    _SocialPlatform? p = _primaryVerified(c);
    p ??= _primaryAdded(c);
    p ??= _anyHandle(c);
    if (p == null) return null;
    final label = p.label;
    final when = p.when;
    final date = when != null ? DateFormat.yMd().format(when) : '—';
    return '$label @ $date';
  }

  _SocialPlatform? _primaryVerified(ContactEntry c) {
    if (c.verifiedOnSnapAt != null && (c.snapUsername?.isNotEmpty ?? false)) {
      return _SocialPlatform('Snapchat', c.verifiedOnSnapAt);
    }
    if (c.verifiedOnInstaAt != null && (c.instaUsername?.isNotEmpty ?? false)) {
      return _SocialPlatform('Instagram', c.verifiedOnInstaAt);
    }
    if (c.verifiedOnDiscordAt != null && (c.discordUsername?.isNotEmpty ?? false)) {
      return _SocialPlatform('Discord', c.verifiedOnDiscordAt);
    }
    return null;
  }

  _SocialPlatform? _primaryAdded(ContactEntry c) {
    if (c.addedOnSnap) return _SocialPlatform('Snapchat', c.dateAddedOnSnap);
    if (c.addedOnInsta) return _SocialPlatform('Instagram', c.dateAddedOnInsta);
    if (c.addedOnDiscord) return _SocialPlatform('Discord', c.dateAddedOnDiscord);
    return null;
  }

  _SocialPlatform? _anyHandle(ContactEntry c) {
    if (c.snapUsername?.isNotEmpty == true) return _SocialPlatform('Snapchat', c.dateAddedOnSnap ?? c.verifiedOnSnapAt);
    if (c.instaUsername?.isNotEmpty == true) return _SocialPlatform('Instagram', c.dateAddedOnInsta ?? c.verifiedOnInstaAt);
    if (c.discordUsername?.isNotEmpty == true) return _SocialPlatform('Discord', c.dateAddedOnDiscord ?? c.verifiedOnDiscordAt);
    return null;
  }

  // Offset formatting borrowed to keep consistent with tiles
  String? _formatUtcOffset(int? rawOffset) {
    if (rawOffset == null) return null;
    final seconds = _normalizeOffsetToSeconds(rawOffset);
    final sign = seconds >= 0 ? '+' : '-';
    final absSec = seconds.abs();
    final hours = absSec ~/ 3600;
    final minutes = (absSec % 3600) ~/ 60;
    final hh = hours.toString().padLeft(2, '0');
    final mm = minutes.toString().padLeft(2, '0');
    return 'UTC$sign$hh:$mm';
  }

  String? _formatRelativeOffset(int? contactRawOffset) {
    if (contactRawOffset == null) return null;
    final contactSec = _normalizeOffsetToSeconds(contactRawOffset);
    final localSec = DateTime.now().timeZoneOffset.inSeconds;
    final deltaMin = ((contactSec - localSec) / 60).round();
    if (deltaMin == 0) return 'Same time';
    final ahead = deltaMin > 0;
    final absMin = deltaMin.abs();
    final h = absMin ~/ 60;
    final m = absMin % 60;
    final parts = <String>[];
    if (h > 0) parts.add('${h}h');
    if (m > 0) parts.add('${m}m');
    final span = parts.join(' ');
    return ahead ? '$span ahead' : '$span behind';
  }

  int _normalizeOffsetToSeconds(int raw) {
    final abs = raw.abs();
    const maxHours = 18;
    const maxMinutes = maxHours * 60;
    const maxSeconds = maxHours * 3600;
    const maxMillis = maxSeconds * 1000;
    const maxMicros = maxMillis * 1000;
    if (abs <= maxMinutes) return raw * 60; // minutes
    if (abs <= maxSeconds) return raw; // seconds
    if (abs <= maxMillis) return (raw / 1000).round(); // millis
    if (abs <= maxMicros) return (raw / 1000000).round(); // micros
    return 0;
  }

  String _overlaySummary(ContactEntry c) {
    final parts = <String>[];
    parts.add(_bestName(c));
    final off = _bestOffsetLabel(c);
    if (off != null) parts.add(off);
    final pad = _platformAtDate(c);
    if (pad != null) parts.add(pad);
    parts.add('Found ${DateFormat.yMd().format(c.dateFound)}');
    return parts.join(' • ');
  }

  // Build icon-labeled rows for the expanded side card
  List<Widget> _metaRowsWithIcons(ContactEntry c) {
    final items = <_MetaItem>[];
    items.add(_MetaItem(
      icon: Icons.person_outline,
      label: 'Name',
      value: _bestName(c),
    ));
    final off = _bestOffsetLabel(c);
    if (off != null) {
      items.add(_MetaItem(icon: Icons.schedule, label: 'Time offset', value: off));
    }
    final pad = _platformAtDate(c);
    if (pad != null) {
      items.add(_MetaItem(icon: Icons.alternate_email, label: 'Platform @ date', value: pad));
    }
    items.add(_MetaItem(
      icon: Icons.calendar_today_outlined,
      label: 'Date found',
      value: DateFormat.yMd().format(c.dateFound),
    ));

    return [
      for (final it in items)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(it.icon, size: 16, color: Colors.white70),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(it.label,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11)),
                    const SizedBox(height: 2),
                    Text(it.value,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
    ];
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
                  backgroundDecoration:
                      const BoxDecoration(color: Colors.black),
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: PhotoViewComputedScale.covered * 3.0,
                );
              },
            ),
            if (_editorOpen && _aimHighlight)
              Positioned.fill(
                child:
                    _AimBandOverlay(centerY: _aimY, bandHeightFraction: 0.18),
              ),
            // Side info toggle (right-center): tap to expand/collapse metadata
            Positioned(
              top: 0,
              bottom: 0,
              right: 10,
              child: Center(
                child: _metaExpanded
                    ? _MetaCard(
                        summaryBuilder: () => _overlaySummary(_current),
                        rowsBuilder: () => _metaRowsWithIcons(_current),
                        onClose: () => setState(() => _metaExpanded = false),
                      )
                    : _InfoButton(onTap: () => setState(() => _metaExpanded = true)),
              ),
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
                    Text('${_index + 1} / ${widget.images.length}',
                        style: const TextStyle(color: Colors.white)),
                    const Spacer(),
                    // Redo text extraction for the current item
                    ValueListenableBuilder<Map<String, RedoJobStatus>>(
                      valueListenable: RedoJobManager.instance.statuses,
                      builder: (context, map, _) {
                        final st = map[_current.identifier];
                        final busy = st != null &&
                            (st.processing || st.message == 'Queued');
                        return IconButton(
                          tooltip: busy
                              ? 'Redo in progress'
                              : 'Redo text extraction',
                          color: Colors.white,
                          icon: const Icon(Icons.refresh),
                          onPressed: busy
                              ? null
                              : () async {
                                  final entry = _current;
                                  final result = await Navigator.of(context)
                                      .push<Map<String, dynamic>>(
                                    MaterialPageRoute(
                                      builder: (_) => RedoCropScreen(
                                        imageFile: File(entry.imagePath),
                                        contact: entry,
                                        initialAllowNameAgeUpdate:
                                            (entry.name == null ||
                                                entry.name!.isEmpty ||
                                                entry.age == null),
                                      ),
                                    ),
                                  );
                                  if (result != null) {
                                    final response = result['response']
                                        as Map<String, dynamic>?;
                                    final allowNameAgeUpdate =
                                        result['allowNameAgeUpdate'] == true;
                                    if (response != null) {
                                      setState(() {
                                        postProcessChatGptResult(
                                          entry,
                                          response,
                                          save: false,
                                          allowNameAgeUpdate:
                                              allowNameAgeUpdate,
                                        );
                                      });
                                      await StorageUtils.save(entry);
                                    }
                                  }
                                },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            // Non-blocking redo status banner for current image
            Positioned(
              top: 42,
              left: 8,
              right: 8,
              child: ValueListenableBuilder<Map<String, RedoJobStatus>>(
                valueListenable: RedoJobManager.instance.statuses,
                builder: (context, map, _) {
                  final st = map[_current.identifier];
                  if (st == null) return const SizedBox.shrink();
                  final failed = !st.processing && st.message == 'Failed';
                  final queued = !st.processing && st.message == 'Queued';
                  final processing = st.processing;
                  Color bg;
                  Color fg;
                  Widget leading;
                  String text;
                  if (failed) {
                    bg = Colors.deepOrange.withOpacity(0.15);
                    fg = Colors.deepOrange;
                    leading = const Icon(Icons.error_outline,
                        size: 16, color: Colors.deepOrange);
                    text = 'Redo failed — open panel to retry';
                  } else if (processing) {
                    bg = Colors.blue.withOpacity(0.15);
                    fg = Colors.blue;
                    leading = const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2));
                    text = 'Updating… Redo in progress';
                  } else if (queued) {
                    bg = Colors.blueGrey.withOpacity(0.14);
                    fg = Colors.blueGrey;
                    leading = const Icon(Icons.schedule,
                        size: 16, color: Colors.blueGrey);
                    text = 'Redo queued…';
                  } else {
                    return const SizedBox.shrink();
                  }
                  return IgnorePointer(
                    ignoring: true,
                    child: Container(
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: fg.withOpacity(0.35)),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          leading,
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              text,
                              style: TextStyle(color: fg),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                            padding:
                                const EdgeInsets.symmetric(horizontal: 56.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: _showDetailsSheet,
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16),
                                      minimumSize: const Size(0, 44),
                                    ),
                                    icon:
                                        const Icon(Icons.description_outlined),
                                    label: const FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text('Details'),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => setState(
                                        () => _editorOpen = !_editorOpen),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      side: const BorderSide(
                                          color: Colors.white70),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16),
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
                                ? () => _pageController.animateToPage(
                                    _index - 1,
                                    duration: const Duration(milliseconds: 200),
                                    curve: Curves.easeOut)
                                : null,
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            color: Colors.white,
                            icon: const Icon(Icons.chevron_right, size: 30),
                            onPressed: _index < widget.images.length - 1
                                ? () => _pageController.animateToPage(
                                    _index + 1,
                                    duration: const Duration(milliseconds: 200),
                                    curve: Curves.easeOut)
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
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(16)),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 12,
                          offset: const Offset(0, -2))
                    ],
                  ),
                  child: Column(
                    children: [
                      // Drag handle area: only this area resizes the panel
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragUpdate: (d) {
                          final h = MediaQuery.of(context).size.height;
                          setState(() {
                            _dockPerc = (_dockPerc - d.primaryDelta! / h)
                                .clamp(_dockMin, _dockMax);
                          });
                        },
                        onVerticalDragEnd: (_) {
                          // snap to nearest
                          final targets = [_dockMin, _dockMid, _dockMax];
                          double closest = targets.first;
                          for (final t in targets) {
                            if ((t - _dockPerc).abs() <
                                (closest - _dockPerc).abs()) closest = t;
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
                                decoration: BoxDecoration(
                                    color: Colors.grey.shade400,
                                    borderRadius: BorderRadius.circular(2)),
                              ),
                              const SizedBox(height: 6),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12.0),
                                child: Row(
                                  children: [
                                    const Icon(Icons.manage_accounts),
                                    const SizedBox(width: 8),
                                    const Text('Handles & Verification',
                                        style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700)),
                                    const Spacer(),
                                    TextButton(
                                      onPressed: () =>
                                          setState(() => _editorOpen = false),
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
                          onAimHighlight: (v) =>
                              setState(() => _aimHighlight = v),
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
      painter: _AimBandPainter(
          centerY: centerY, bandHeightFraction: bandHeightFraction),
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
    final bandRect = Rect.fromLTWH(
        0,
        (center - bandHeight / 2).clamp(0.0, size.height - bandHeight),
        size.width,
        bandHeight);

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
    return old.centerY != centerY ||
        old.bandHeightFraction != bandHeightFraction;
  }
}

// --- Small helper value class for meta items ---
class _MetaItem {
  final IconData icon;
  final String label;
  final String value;
  _MetaItem({required this.icon, required this.label, required this.value});
}

// --- Collapsed info button ---
class _InfoButton extends StatelessWidget {
  final VoidCallback onTap;
  const _InfoButton({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const StadiumBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Icon(Icons.info_outline, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}

// --- Expanded side card ---
class _MetaCard extends StatelessWidget {
  final List<Widget> Function() rowsBuilder;
  final String Function() summaryBuilder;
  final VoidCallback onClose;
  const _MetaCard({
    required this.rowsBuilder,
    required this.summaryBuilder,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Material(
        color: Colors.black.withOpacity(0.6),
        elevation: 3,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.white70, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      summaryBuilder(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                    onPressed: onClose,
                    icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ...rowsBuilder(),
            ],
          ),
        ),
      ),
    );
  }
}
