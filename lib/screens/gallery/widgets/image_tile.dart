import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:PhotoWordFind/models/contactEntry.dart';
import 'package:intl/intl.dart';
import 'package:photo_view/photo_view.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:PhotoWordFind/social_icons.dart';
// import 'package:PhotoWordFind/utils/storage_utils.dart';
// import 'package:PhotoWordFind/utils/chatgpt_post_utils.dart';
import 'package:PhotoWordFind/widgets/note_dialog.dart';
import 'package:PhotoWordFind/widgets/confirmation_dialog.dart';
import 'package:PhotoWordFind/screens/gallery/redo_crop_screen.dart';
import 'package:PhotoWordFind/screens/gallery/widgets/handles_sheet.dart';
import 'package:PhotoWordFind/utils/memory_utils.dart';
import 'package:PhotoWordFind/services/redo_job_manager.dart';
import 'package:path/path.dart' as p;

class ImageTile extends StatefulWidget {
  final String imagePath;
  final bool isSelected;
  final String extractedText;
  final String identifier;
  final String sortOption;
  final Function(String) onSelected;
  final Function(String, String) onMenuOptionSelected;
  final ContactEntry contact;
  final bool gridMode;
  final VoidCallback? onOpenFullScreen;
  final bool selectionMode;
  // Secondary selection: flagged for "never friended back" bulk action
  final bool neverBackSelected;
  final VoidCallback? onToggleNeverBack;

  const ImageTile({
    super.key,
    required this.imagePath,
    required this.isSelected,
    required this.extractedText,
    required this.identifier,
    required this.sortOption,
    required this.onSelected,
    required this.onMenuOptionSelected,
    required this.contact,
    this.gridMode = false,
    this.onOpenFullScreen,
    this.selectionMode = false,
  this.neverBackSelected = false,
  this.onToggleNeverBack,
  });

  @override
  State<ImageTile> createState() => _ImageTileState();
}

class _ImageTileState extends State<ImageTile> {
  bool _metaExpanded = false;
  // Only show tooltips on platforms where hover is common (web/desktop).
  bool get _enableTooltips {
    if (kIsWeb) return true;
    try {
      return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    } catch (_) {
      return false;
    }
  }
  ImageProvider _providerForWidth(double logicalWidth) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    // Clamp to a sane range to avoid decoding very large bitmaps in list/grid
    final targetWidth = (logicalWidth * dpr).clamp(64.0, 2048.0).round();
    return ResizeImage(FileImage(File(widget.imagePath)), width: targetWidth);
  }

  String get _truncatedText {
    const maxChars = 120;
    if (widget.extractedText.length <= maxChars) return widget.extractedText;
    return '${widget.extractedText.substring(0, maxChars)}...';
  }

  String get _displayLabel {
    switch (widget.sortOption) {
      case 'Date found':
        return DateFormat.yMd().format(widget.contact.dateFound);
      case 'Snap Added Date':
        final snapDate = widget.contact.dateAddedOnSnap;
        return snapDate != null ? DateFormat.yMd().format(snapDate) : 'No date';
      case 'Instagram Added Date':
        final instaDate = widget.contact.dateAddedOnInsta;
        return instaDate != null
            ? DateFormat.yMd().format(instaDate)
            : 'No date';
      case 'Added on Snapchat':
        return widget.contact.addedOnSnap ? 'Added' : 'Not Added';
      case 'Added on Instagram':
        return widget.contact.addedOnInsta ? 'Added' : 'Not Added';
      case 'Location':
        final loc = widget.contact.location;
        if (loc == null) return 'No location';
        final relative = _formatRelativeOffset(loc.utcOffset);
        if (relative != null) return relative;
        // Fallbacks if offset is unavailable
        final absLabel = _formatUtcOffset(loc.utcOffset);
        if (absLabel != null) return absLabel;
        if ((loc.rawLocation?.isNotEmpty ?? false)) return loc.rawLocation!;
        return 'Location';
      case 'Name':
        return widget.contact.name ?? widget.identifier;
      default:
        return widget.identifier;
    }
  }

  // Always-on compact metadata summary shown on the tile regardless of sort.
  // Format: Name • Time offset • Platform @ date • Found date
  String get _metaSummary {
    final parts = <String>[];
    // Name or filename (without extension) fallback
    final name = (widget.contact.name != null &&
            widget.contact.name!.trim().isNotEmpty)
        ? widget.contact.name!.trim()
        : _fallbackBaseName(widget.imagePath);
    parts.add(name);

    // Time offset (relative preferred; else absolute UTC±HH:MM)
    final offsetRel = _formatRelativeOffset(widget.contact.location?.utcOffset);
    final offsetAbs = _formatUtcOffset(widget.contact.location?.utcOffset);
    if (offsetRel != null) {
      parts.add(offsetRel);
    } else if (offsetAbs != null) {
      parts.add(offsetAbs);
    }

    // Platform @ date (verified-first, else added if present)
    final platformAtDate = _primaryPlatformAtDate();
    if (platformAtDate != null) parts.add(platformAtDate);

    // Date found
    parts.add('Found ${DateFormat.yMd().format(widget.contact.dateFound)}');

    return parts.join(' • ');
  }

  String _fallbackBaseName(String path) {
    try {
      return p.basenameWithoutExtension(path);
    } catch (_) {
      return widget.identifier;
    }
  }

  String? _primaryPlatformAtDate() {
    // Pick a primary platform: verified-first, else added, else any username
    SocialType? s = _getPrimaryVerifiedSocial();
    s ??= _getPrimaryAddedSocial();
    s ??= _getAnySocial();
    if (s == null) return null;

    final label = s.name;
    DateTime? when;
    switch (s) {
      case SocialType.Snapchat:
        when = widget.contact.dateAddedOnSnap ?? widget.contact.verifiedOnSnapAt;
        break;
      case SocialType.Instagram:
        when = widget.contact.dateAddedOnInsta ?? widget.contact.verifiedOnInstaAt;
        break;
      case SocialType.Discord:
        when = widget.contact.dateAddedOnDiscord ?? widget.contact.verifiedOnDiscordAt;
        break;
      default:
        when = null;
    }
    final dateStr = (when != null) ? DateFormat.yMd().format(when) : '—';
    return '$label @ $dateStr';
  }

  SocialType? _getPrimaryAddedSocial() {
    if (widget.contact.addedOnSnap) return SocialType.Snapchat;
    if (widget.contact.addedOnInsta) return SocialType.Instagram;
    if (widget.contact.addedOnDiscord) return SocialType.Discord;
    return null;
  }

  SocialType? _getAnySocial() {
    if (widget.contact.snapUsername?.isNotEmpty == true) return SocialType.Snapchat;
    if (widget.contact.instaUsername?.isNotEmpty == true) return SocialType.Instagram;
    if (widget.contact.discordUsername?.isNotEmpty == true) return SocialType.Discord;
    return null;
  }

  // Multi-line metadata block for better readability on tiles.
  Widget _buildMetaBlock({bool expanded = false}) {
    // Derive components so we can place them on separate lines if needed
    final name = (widget.contact.name != null &&
            widget.contact.name!.trim().isNotEmpty)
        ? widget.contact.name!.trim()
        : _fallbackBaseName(widget.imagePath);
    final offsetRel = _formatRelativeOffset(widget.contact.location?.utcOffset);
    final offsetAbs = _formatUtcOffset(widget.contact.location?.utcOffset);
    final offset = offsetRel ?? offsetAbs;
    final platformAt = _primaryPlatformAtDate();
    final found = 'Found ${DateFormat.yMd().format(widget.contact.dateFound)}';

    // Derive lines
    final lines = <String>[];
    final line1 = name;
    final line2 = [if (offset != null) offset, if (platformAt != null) platformAt].join(' • ');
    final line3 = found;
    if (line1.isNotEmpty) lines.add(line1);
    if (line2.isNotEmpty) lines.add(line2);
    lines.add(line3);

    // Determine which line to emphasize based on current sort
    int? emphasizeIndex;
    switch (widget.sortOption) {
      case 'Name':
        emphasizeIndex = 0; // name line
        break;
      case 'Date found':
        emphasizeIndex = lines.length - 1; // found line
        break;
      case 'Snap Added Date':
      case 'Instagram Added Date':
        // emphasize platform/date line if present
        emphasizeIndex = lines.length > 1 ? 1 : null;
        break;
      case 'Added on Snapchat':
      case 'Added on Instagram':
        // append added/not added tag and emphasize that line
        final addedLabel = () {
          if (widget.sortOption == 'Added on Snapchat') {
            return widget.contact.addedOnSnap ? 'Added' : 'Not Added';
          }
          return widget.contact.addedOnInsta ? 'Added' : 'Not Added';
        }();
        // integrate to line2
        if (lines.length > 1) {
          lines[1] = lines[1].isNotEmpty ? '${lines[1]} • $addedLabel' : addedLabel;
          emphasizeIndex = 1;
        } else {
          lines.add(addedLabel);
          emphasizeIndex = lines.length - 1;
        }
        break;
      case 'Location':
        // emphasize offset if we have it
        if (lines.length > 1 && (offset != null)) emphasizeIndex = 1;
        break;
      default:
        emphasizeIndex = null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < lines.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 1),
            child: () {
              final isEmph = emphasizeIndex == i;
              final text = Text(
                lines[i],
                maxLines: expanded ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isEmph ? Colors.white : Colors.white.withOpacity(0.93),
                  fontSize: isEmph
                      ? (expanded ? 12.0 : 11.0)
                      : (expanded ? 11.5 : 10.5),
                  fontWeight: isEmph ? FontWeight.w700 : FontWeight.w500,
                ),
              );
              if (!isEmph) return text;
              return Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(4),
                  border: Border(
                    left: BorderSide(
                      color: Colors.lightBlueAccent.withOpacity(0.85),
                      width: 2,
                    ),
                  ),
                ),
                padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 6),
                child: text,
              );
            }(),
          ),
      ],
    );
  }

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
    // Normalize contact offset to seconds across possible units
    final contactSec = _normalizeOffsetToSeconds(contactRawOffset);
    final localSec = DateTime.now().timeZoneOffset.inSeconds;
    final deltaMin = ((contactSec - localSec) / 60).round();
    if (deltaMin == 0) return 'Same time';
    final ahead = deltaMin > 0; // contact is ahead of local time
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
    // Offsets should be within +/- 18 hours. We infer the incoming unit by magnitude.
    final abs = raw.abs();
    const maxHours = 18;
    const maxMinutes = maxHours * 60; // 1080
    const maxSeconds = maxHours * 3600; // 64800
    const maxMillis = maxSeconds * 1000; // 64800000
    const maxMicros = maxMillis * 1000; // 64800000000

    if (abs <= maxMinutes) {
      // Likely minutes
      return raw * 60;
    }
    if (abs <= maxSeconds) {
      // Seconds
      return raw;
    }
    if (abs <= maxMillis) {
      // Milliseconds
      return (raw / 1000).round();
    }
    if (abs <= maxMicros) {
      // Microseconds
      return (raw / 1000000).round();
    }
    // Fallback: clamp to sign * 0 to avoid absurd values
    return raw.isNegative ? -0 : 0;
  }

  SocialType? _getPrimarySocial() {
    if (widget.contact.snapUsername?.isNotEmpty == true)
      return SocialType.Snapchat;
    if (widget.contact.instaUsername?.isNotEmpty == true)
      return SocialType.Instagram;
    if (widget.contact.discordUsername?.isNotEmpty == true)
      return SocialType.Discord;
    return null;
  }

  String? _getPrimaryUsername(SocialType social) {
    switch (social) {
      case SocialType.Snapchat:
        return widget.contact.snapUsername;
      case SocialType.Instagram:
        return widget.contact.instaUsername;
      case SocialType.Discord:
        return widget.contact.discordUsername;
      default:
        return null;
    }
  }

  void _showPopupMenu(BuildContext context, String imagePath) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.info),
              title: const Text('View Details'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showDetailsDialog(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.manage_accounts),
              title: const Text('Handles & Verification'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await showHandlesSheet(context, widget.contact);
                setState(() {});
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Redo text extraction'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _redoTextExtraction();
              },
            ),
            if (widget.contact.snapUsername?.isNotEmpty ?? false)
              ListTile(
                leading: const Icon(Icons.chat_bubble),
                title: const Text('Open on Snap'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final u = widget.contact.snapUsername!;
                  _openSocial(SocialType.Snapchat, u);
                  if (!widget.contact.addedOnSnap &&
                      widget.contact.verifiedOnSnapAt != null) {
                    setState(() {
                      widget.contact.addSnapchat();
                    });
                  }
                },
              ),
            if (widget.contact.instaUsername?.isNotEmpty ?? false)
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Open on Insta'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openSocial(
                      SocialType.Instagram, widget.contact.instaUsername!);
                },
              ),
            if (widget.contact.discordUsername?.isNotEmpty ?? false)
              ListTile(
                leading: const Icon(Icons.discord),
                title: const Text('Open on Discord'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openSocial(
                      SocialType.Discord, widget.contact.discordUsername!);
                },
              ),
            if (widget.contact.addedOnSnap) ...[
              ListTile(
                leading: const Icon(Icons.person_off),
                title: const Text('Quick Unfriend on Snap'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _unfriendSocial(
                    SocialType.Snapchat,
                    autoReason: 'no response',
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_remove),
                title: const Text('Unfriend on Snap with Note'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _unfriendSocial(
                    SocialType.Snapchat,
                    promptForNote: true,
                    autoReason: 'conversation ended',
                  );
                },
              ),
            ],
            if (widget.contact.addedOnInsta) ...[
              ListTile(
                leading: const Icon(Icons.person_off),
                title: const Text('Quick Unfriend on Insta'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _unfriendSocial(
                    SocialType.Instagram,
                    autoReason: 'no response',
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_remove),
                title: const Text('Unfriend on Insta with Note'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _unfriendSocial(
                    SocialType.Instagram,
                    promptForNote: true,
                    autoReason: 'conversation ended',
                  );
                },
              ),
            ],
            if (widget.contact.addedOnDiscord) ...[
              ListTile(
                leading: const Icon(Icons.person_off),
                title: const Text('Quick Unfriend on Discord'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _unfriendSocial(
                    SocialType.Discord,
                    autoReason: 'no response',
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_remove),
                title: const Text('Unfriend on Discord with Note'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _unfriendSocial(
                    SocialType.Discord,
                    promptForNote: true,
                    autoReason: 'conversation ended',
                  );
                },
              ),
            ],
            ListTile(
              leading: const Icon(Icons.note_alt_outlined),
              title: const Text('Edit Notes'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await showNoteDialog(
                  context,
                  widget.contact.identifier,
                  widget.contact,
                  existingNotes: widget.contact.notes,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.move_to_inbox),
              title: const Text('Move'),
              onTap: () {
                widget.onMenuOptionSelected(widget.imagePath, 'move');
                Navigator.pop(sheetContext);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _redoTextExtraction() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => RedoCropScreen(
          imageFile: File(widget.imagePath),
          contact: widget.contact,
          initialAllowNameAgeUpdate: (widget.contact.name == null ||
              widget.contact.name!.isEmpty ||
              widget.contact.age == null),
        ),
      ),
    );
    if (result != null && result['queued'] == true) {
      // Background job enqueued; show a brief hint
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Redo queued and running in background.')),
        );
        setState(() {});
      }
    }
  }

  void _showDetailsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              constraints: const BoxConstraints(maxHeight: 300),
              child: PhotoView(
                imageProvider: FileImage(File(widget.imagePath)),
                backgroundDecoration: const BoxDecoration(color: Colors.white),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 2.5,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Text(
                widget.extractedText.isNotEmpty
                    ? widget.extractedText
                    : 'No text found',
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirm(BuildContext context,
      {String message = 'Are you sure?'}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmationDialog(message: message),
    );
    return result ?? false;
  }

  Future<void> _editUsernames(BuildContext context) async {
    final originalSnap = widget.contact.snapUsername ?? '';
    final originalInsta = widget.contact.instaUsername ?? '';
    final originalDiscord = widget.contact.discordUsername ?? '';

    final snapController = TextEditingController(text: originalSnap);
    final instaController = TextEditingController(text: originalInsta);
    final discordController = TextEditingController(text: originalDiscord);

    bool changed = false;
    void updateChanged() {
      changed = snapController.text != originalSnap ||
          instaController.text != originalInsta ||
          discordController.text != originalDiscord;
    }

    snapController.addListener(updateChanged);
    instaController.addListener(updateChanged);
    discordController.addListener(updateChanged);

    final result = await showDialog<List<String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return WillPopScope(
          onWillPop: () async {
            if (changed) {
              return await _confirm(context, message: 'Discard changes?');
            }
            return true;
          },
          child: AlertDialog(
            title: const Text('Edit Usernames'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: snapController,
                  decoration: const InputDecoration(labelText: 'Snapchat'),
                ),
                TextField(
                  controller: instaController,
                  decoration: const InputDecoration(labelText: 'Instagram'),
                ),
                TextField(
                  controller: discordController,
                  decoration: const InputDecoration(labelText: 'Discord'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  if (changed) {
                    final discard =
                        await _confirm(context, message: 'Discard changes?');
                    if (!discard) return;
                  }
                  Navigator.pop(context);
                },
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  if (changed) {
                    final confirmSave =
                        await _confirm(context, message: 'Save changes?');
                    if (!confirmSave) return;
                  }
                  Navigator.pop(context, [
                    snapController.text,
                    instaController.text,
                    discordController.text,
                  ]);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );

    if (result != null) {
      if (result[0] != widget.contact.snapUsername) {
        await SocialType.Snapchat.saveUsername(widget.contact, result[0],
            overriding: true);
      }
      if (result[1] != widget.contact.instaUsername) {
        await SocialType.Instagram.saveUsername(widget.contact, result[1],
            overriding: true);
      }
      if (result[2] != widget.contact.discordUsername) {
        await SocialType.Discord.saveUsername(widget.contact, result[2],
            overriding: true);
      }
      setState(() {});
    }
  }

  void _openSocial(SocialType social, String username) async {
    // Proactively free decoded images to reduce memory pressure before switching apps
    MemoryUtils.trimImageCaches();
    Uri url;
    switch (social) {
      case SocialType.Snapchat:
        url =
            Uri.parse('https://www.snapchat.com/add/${username.toLowerCase()}');
        break;
      case SocialType.Instagram:
        url = Uri.parse('https://www.instagram.com/$username');
        break;
      case SocialType.Discord:
        Clipboard.setData(ClipboardData(text: username));
        SocialIcon.discordIconButton?.openApp();
        return;
      default:
        return;
    }
    if (!url.hasEmptyPath) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _unfriendSocial(
    SocialType social, {
    bool promptForNote = false,
    String? autoReason,
  }) async {
    final username = await social.getUserName(widget.contact);
    if (username == null || username.isEmpty) return;

    _openSocial(social, username);
    bool res = await _confirm(context, message: 'Confirm unfriended?');
    if (!res) return;

    setState(() {
      widget.contact.state = 'Strings';

      final now = DateFormat.yMd().add_jm().format(DateTime.now());
      String note = 'Unfriended from ${social.name} on $now';
      if (autoReason != null && autoReason.isNotEmpty) {
        note += ' ($autoReason)';
      }
      if (widget.contact.notes == null || widget.contact.notes!.isEmpty) {
        widget.contact.notes = note;
      } else {
        widget.contact.notes = '${widget.contact.notes}\n$note';
      }
    });

    if (promptForNote) {
      final extra = await showNoteDialog(
        context,
        widget.contact.identifier,
        widget.contact,
      );
      if (extra != null && extra.isNotEmpty) {
        setState(() {
          widget.contact.notes = '${widget.contact.notes}\n$extra';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        onTap: () async {
          // In selection mode, tapping toggles selection instead of opening.
          if (widget.selectionMode) {
            widget.onSelected(widget.identifier);
            return;
          }
          if (widget.gridMode && widget.onOpenFullScreen != null) {
            widget.onOpenFullScreen!.call();
          } else {
            _showDetailsDialog(context);
          }
        },
        onLongPress: () => widget.onSelected(widget.identifier),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool isGrid = widget.gridMode;
            final logicalWidth =
                isGrid ? constraints.maxWidth : (constraints.maxWidth * 0.8);
            final imageProvider = _providerForWidth(logicalWidth);
            final tile = Container(
              margin: isGrid
                  ? EdgeInsets.zero
                  : const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              width: isGrid ? double.infinity : constraints.maxWidth * 0.8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 6,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    // Fill the tile fully; in grid use cover, in non-grid use contain.
                    Positioned.fill(
                      child: Image(
                        image: imageProvider,
                        fit: isGrid ? BoxFit.cover : BoxFit.contain,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.low,
                        errorBuilder: (ctx, _, __) =>
                            const ColoredBox(color: Colors.black12),
                      ),
                    ),
                    // Selection highlight overlay (does not affect layout size).
                    if (widget.isSelected)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: Colors.blueAccent, width: 3),
                            ),
                          ),
                        ),
                      ),
                    // Top-right: selection icon in selection mode; otherwise the 3-dot menu
                    Positioned(
                      top: 8,
                      right: 8,
                      child: widget.selectionMode
                          ? Material(
                              color: Colors.transparent,
                              shape: const CircleBorder(),
                              elevation: 4,
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () =>
                                    widget.onSelected(widget.identifier),
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.black.withOpacity(0.55),
                                    border: Border.all(
                                        color: Colors.white, width: 2),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 8,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Icon(
                                      widget.isSelected
                                          ? Icons.check_circle
                                          : Icons.radio_button_unchecked,
                                      color: widget.isSelected
                                          ? Colors.lightBlueAccent
                                          : Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : Material(
                              color: Colors.transparent,
                              shape: const CircleBorder(),
                              elevation: 4,
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () =>
                                    _showPopupMenu(context, widget.imagePath),
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.black.withOpacity(0.55),
                                    border: Border.all(
                                        color: Colors.white, width: 2),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 8,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Center(
                                      child: Icon(Icons.more_vert,
                                          color: Colors.white, size: 20)),
                                ),
                              ),
                            ),
                    ),
                    // Secondary toggle chip: "never friended back" under selection icon
                    if (widget.selectionMode && widget.isSelected)
                      Positioned(
                        top: 48,
                        right: 8,
                        child: Material(
                          color: Colors.transparent,
                          elevation: 4,
                          borderRadius: BorderRadius.circular(999),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: widget.onToggleNeverBack,
                            child: Container(
                              height: 28,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.55),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: widget.neverBackSelected
                                      ? Colors.redAccent
                                      : Colors.white,
                                  width: 1.5,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                      color: Colors.black26, blurRadius: 6),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    widget.neverBackSelected
                                        ? Icons.person_off
                                        : Icons.person_outline,
                                    size: 16,
                                    color: widget.neverBackSelected
                                        ? Colors.redAccent
                                        : Colors.white,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Never-back',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    // Processing/failed overlay and interaction control
                    Positioned.fill(
                      child: ValueListenableBuilder<Map<String, RedoJobStatus>>(
                        valueListenable: RedoJobManager.instance.statuses,
                        builder: (context, map, _) {
                          final status = map[widget.contact.identifier];
                          if (status == null) return const SizedBox.shrink();
                          if (status.processing || status.message == 'Queued') {
                            // Absorb interactions while queued/processing
                            return AbsorbPointer(
                              absorbing: true,
                              child: Container(
                                color: Colors.black38,
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.black87,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.white24),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        ),
                                        SizedBox(width: 10),
                                        Text('Redoing...',
                                            style:
                                                TextStyle(color: Colors.white)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }
                          // Failed state: show a small bottom-left chip with retry
                          if (!status.processing &&
                              status.message == 'Failed') {
                            return Stack(
                              children: [
                                Positioned(
                                  left: 8,
                                  bottom: 64, // above the bottom gradient bar
                                  child: Material(
                                    color: Colors.transparent,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withOpacity(0.95),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                        boxShadow: const [
                                          BoxShadow(
                                              color: Colors.black26,
                                              blurRadius: 4)
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.error_outline,
                                              size: 14, color: Colors.black),
                                          const SizedBox(width: 6),
                                          const Text('Failed',
                                              style: TextStyle(
                                                  color: Colors.black,
                                                  fontWeight: FontWeight.w600)),
                                          TextButton(
                                            style: TextButton.styleFrom(
                                                minimumSize: const Size(0, 0),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2)),
                                            onPressed: () {
                                              RedoJobManager.instance.retry(
                                                  widget.contact.identifier);
                                            },
                                            child: const Text('Retry',
                                                style: TextStyle(
                                                    color: Colors.black,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }
                          // Queued or idle state: no overlay
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      right: 56, // reserve space for the top-right action button
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Metadata block (tap to expand/collapse)
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(() => _metaExpanded = !_metaExpanded),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 4, horizontal: 6),
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: _buildMetaBlock(expanded: _metaExpanded),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        height: 56,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black54],
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _truncatedText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            // Compact primary actions: primary social, notes, handles
                            Row(
                              children: [
                                _buildVerifiedPrimaryOrPlaceholderButton(),
                                IconButton(
                                  tooltip: 'Notes',
                                  iconSize: 22,
                                  color: Colors.white,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints.tightFor(
                                      width: 36, height: 36),
                                  icon: const Icon(Icons.note_alt_outlined),
                                  onPressed: () async {
                                    await showNoteDialog(
                                      context,
                                      widget.contact.identifier,
                                      widget.contact,
                                      existingNotes: widget.contact.notes,
                                    );
                                  },
                                ),
                                IconButton(
                                  tooltip: 'Handles & Verification',
                                  iconSize: 22,
                                  color: Colors.white,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints.tightFor(
                                      width: 36, height: 36),
                                  icon: const Icon(Icons.manage_accounts),
                                  onPressed: () async {
                                    await showHandlesSheet(
                                        context, widget.contact);
                                    setState(() {});
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
            return isGrid ? AspectRatio(aspectRatio: 3 / 4, child: tile) : tile;
          },
        ),
      ),
    );
  }

  // --------------- Primary social button (verified-first) with badges ---------------
  Widget _buildPrimarySocialButton() {
    final s = _getPrimaryVerifiedSocial();
    if (s == null) {
      // Fallback should not occur here; wrapper uses placeholder when null
      return _buildNoVerifiedButton();
    }
    final username = _getPrimaryUsername(s);
    final addedForSocial = () {
      switch (s) {
        case SocialType.Snapchat:
          return widget.contact.addedOnSnap;
        case SocialType.Instagram:
          return widget.contact.addedOnInsta;
        case SocialType.Discord:
          return widget.contact.addedOnDiscord;
        default:
          return false;
      }
    }();
    final iconWidget = () {
      switch (s) {
        case SocialType.Snapchat:
          return SocialIcon.snapchatIconButton!.socialIcon;
        case SocialType.Instagram:
          return SocialIcon.instagramIconButton!.socialIcon;
        case SocialType.Discord:
          return SocialIcon.discordIconButton!.socialIcon;
        default:
          return const Icon(Icons.open_in_new, color: Colors.white);
      }
    }();

    // Base button
  final baseBtn = IconButton(
      tooltip: _enableTooltips ? 'Open ${s.name}' : null,
      iconSize: 22,
      color: Colors.white,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      onPressed: (username == null || username.isEmpty)
          ? null
          : () async {
              if (s == SocialType.Snapchat) {
                _openSocial(s, username);
                if (!widget.contact.addedOnSnap &&
                    widget.contact.verifiedOnSnapAt != null) {
                  setState(() {
                    widget.contact.addSnapchat();
                  });
                }
              } else {
                _openSocial(s, username);
              }
            },
      icon: iconWidget,
    );

  // Wrap with distinct single-badge states
  Widget buttonWithBadges = baseBtn;
  if (s == SocialType.Snapchat) {
      final added = widget.contact.addedOnSnap;
      final verified = widget.contact.verifiedOnSnapAt != null;
      if (!added && !verified) {
        buttonWithBadges = baseBtn;
      } else {
        // Single badge logic:
        // - verified && !added => blue verified badge (top-right)
        // - verified && added => green verified badge (top-right)
        // - !verified && added => green check badge (bottom-right)
        buttonWithBadges = Stack(
          clipBehavior: Clip.none,
          children: [
            baseBtn,
            if (verified)
              Positioned(
                right: -2,
                top: -2,
                child: _statusDot(
                  color: added ? Colors.lightGreenAccent.shade700 : Colors.blueAccent,
                  icon: Icons.verified,
                ),
              )
            else if (added)
              Positioned(
                right: -2,
                bottom: -2,
                child: _statusDot(
                  color: Colors.lightGreenAccent.shade700,
                  icon: Icons.check,
                ),
              ),
          ],
        );
      }
    } else {
      // Non-Snap: show verified badge if that platform is verified
      final verified = _isVerifiedFor(s);
      if (verified) {
        buttonWithBadges = Stack(
          clipBehavior: Clip.none,
          children: [
            baseBtn,
            Positioned(
              right: -2,
              top: -2,
              child: _statusDot(
                color: Colors.blueAccent,
                icon: Icons.verified,
              ),
            ),
          ],
        );
      } else {
        buttonWithBadges = baseBtn;
      }
    }

    // Long-press to unfriend sheet (only if marked Added on that platform)
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: addedForSocial
          ? () {
              HapticFeedback.mediumImpact();
              _showUnfriendSheet(s);
            }
          : null,
      child: buttonWithBadges,
    );
  }

  Widget _statusDot({required Color color, required IconData icon}) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: Colors.black87,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 2, offset: Offset(0, 1)),
        ],
      ),
      child: Center(
        child: Icon(icon, size: 12, color: color),
      ),
    );
  }

  // Wrapper: choose verified platform if available; else show placeholder
  Widget _buildVerifiedPrimaryOrPlaceholderButton() {
    final s = _getPrimaryVerifiedSocial();
  if (s == null) return _buildNoVerifiedButton();
  return _buildPrimarySocialButton();
  }

  SocialType? _getPrimaryVerifiedSocial() {
    final hasSnap =
        (widget.contact.snapUsername?.isNotEmpty ?? false) &&
            widget.contact.verifiedOnSnapAt != null;
    if (hasSnap) return SocialType.Snapchat;
    final hasInsta =
        (widget.contact.instaUsername?.isNotEmpty ?? false) &&
            (widget.contact.verifiedOnInstaAt != null);
    if (hasInsta) return SocialType.Instagram;
    final hasDiscord =
        (widget.contact.discordUsername?.isNotEmpty ?? false) &&
            (widget.contact.verifiedOnDiscordAt != null);
    if (hasDiscord) return SocialType.Discord;
    return null;
  }

  bool _isVerifiedFor(SocialType s) {
    switch (s) {
      case SocialType.Snapchat:
        return widget.contact.verifiedOnSnapAt != null;
      case SocialType.Instagram:
        return widget.contact.verifiedOnInstaAt != null;
      case SocialType.Discord:
        return widget.contact.verifiedOnDiscordAt != null;
      default:
        return false;
    }
  }

  // Placeholder button when no verified handles exist; opens handles sheet
  Widget _buildNoVerifiedButton() {
    return IconButton(
  tooltip: _enableTooltips ? 'No verified handle • Tap to edit' : null,
      iconSize: 22,
      color: Colors.white,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      onPressed: () async {
        await showHandlesSheet(context, widget.contact);
        setState(() {});
      },
      icon: Stack(
        clipBehavior: Clip.none,
        children: const [
          Icon(Icons.verified_outlined, color: Colors.white70),
          Positioned(
            right: -2,
            top: -2,
            child: Icon(Icons.block, size: 14, color: Colors.redAccent),
          ),
        ],
      ),
    );
  }

  // Former Snapchat add sheet removed in favor of open-then-confirm flow

  void _showUnfriendSheet(SocialType s) {
    final added = () {
      switch (s) {
        case SocialType.Snapchat:
          return widget.contact.addedOnSnap;
        case SocialType.Instagram:
          return widget.contact.addedOnInsta;
        case SocialType.Discord:
          return widget.contact.addedOnDiscord;
        default:
          return false;
      }
    }();

    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        if (!added) {
          return ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text('Not added on ${s.name}'),
            subtitle: const Text('Add first to enable unfriend actions'),
          );
        }
        return ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.person_off),
              title: Text('Quick Unfriend on ${s.name}'),
              onTap: () async {
                Navigator.pop(ctx);
                await _unfriendSocial(
                  s,
                  autoReason: 'no response',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_remove),
              title: Text('Unfriend on ${s.name} with Note'),
              onTap: () async {
                Navigator.pop(ctx);
                await _unfriendSocial(
                  s,
                  promptForNote: true,
                  autoReason: 'conversation ended',
                );
              },
            ),
          ],
        );
      },
    );
  }
}
