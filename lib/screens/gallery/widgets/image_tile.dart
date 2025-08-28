import 'dart:io';
import 'package:flutter/material.dart';
import 'package:PhotoWordFind/models/contactEntry.dart';
import 'package:intl/intl.dart';
import 'package:photo_view/photo_view.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:PhotoWordFind/social_icons.dart';
import 'package:PhotoWordFind/utils/storage_utils.dart';
import 'package:PhotoWordFind/utils/chatgpt_post_utils.dart';
import 'package:PhotoWordFind/widgets/note_dialog.dart';
import 'package:PhotoWordFind/widgets/confirmation_dialog.dart';
import 'package:PhotoWordFind/screens/gallery/redo_crop_screen.dart';
import 'package:PhotoWordFind/screens/gallery/widgets/handles_sheet.dart';
import 'package:PhotoWordFind/utils/memory_utils.dart';

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
  });

  @override
  State<ImageTile> createState() => _ImageTileState();
}

class _ImageTileState extends State<ImageTile> {
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
        return instaDate != null ? DateFormat.yMd().format(instaDate) : 'No date';
      case 'Added on Snapchat':
        return widget.contact.addedOnSnap ? 'Added' : 'Not Added';
      case 'Added on Instagram':
        return widget.contact.addedOnInsta ? 'Added' : 'Not Added';
      case 'Name':
        return widget.contact.name ?? widget.identifier;
      default:
        return widget.identifier;
    }
  }

  SocialType? _getPrimarySocial() {
    if (widget.contact.snapUsername?.isNotEmpty == true) return SocialType.Snapchat;
    if (widget.contact.instaUsername?.isNotEmpty == true) return SocialType.Instagram;
    if (widget.contact.discordUsername?.isNotEmpty == true) return SocialType.Discord;
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
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openSocial(SocialType.Snapchat, widget.contact.snapUsername!);
                },
              ),
            if (widget.contact.instaUsername?.isNotEmpty ?? false)
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Open on Insta'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openSocial(SocialType.Instagram, widget.contact.instaUsername!);
                },
              ),
            if (widget.contact.discordUsername?.isNotEmpty ?? false)
              ListTile(
                leading: const Icon(Icons.discord),
                title: const Text('Open on Discord'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openSocial(SocialType.Discord, widget.contact.discordUsername!);
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
          initialAllowNameAgeUpdate: (widget.contact.name == null || widget.contact.name!.isEmpty || widget.contact.age == null),
        ),
      ),
    );
    if (result != null) {
      final response = result['response'] as Map<String, dynamic>?;
      final allowNameAgeUpdate = result['allowNameAgeUpdate'] == true;
      if (response != null) {
        setState(() {
          postProcessChatGptResult(
            widget.contact,
            response,
            save: false,
            allowNameAgeUpdate: allowNameAgeUpdate,
          );
        });
        await StorageUtils.save(widget.contact);
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
                widget.extractedText.isNotEmpty ? widget.extractedText : 'No text found',
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

  Future<bool> _confirm(BuildContext context, {String message = 'Are you sure?'}) async {
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
                    final discard = await _confirm(context, message: 'Discard changes?');
                    if (!discard) return;
                  }
                  Navigator.pop(context);
                },
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  if (changed) {
                    final confirmSave = await _confirm(context, message: 'Save changes?');
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
        await SocialType.Snapchat.saveUsername(widget.contact, result[0], overriding: true);
      }
      if (result[1] != widget.contact.instaUsername) {
        await SocialType.Instagram.saveUsername(widget.contact, result[1], overriding: true);
      }
      if (result[2] != widget.contact.discordUsername) {
        await SocialType.Discord.saveUsername(widget.contact, result[2], overriding: true);
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
        url = Uri.parse('https://www.snapchat.com/add/${username.toLowerCase()}');
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
          final logicalWidth = isGrid ? constraints.maxWidth : (constraints.maxWidth * 0.8);
          final imageProvider = _providerForWidth(logicalWidth);
          return Container(
            margin: isGrid ? const EdgeInsets.symmetric(vertical: 6, horizontal: 0) : const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            width: isGrid ? double.infinity : constraints.maxWidth * 0.8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: widget.isSelected ? Border.all(color: Colors.blueAccent, width: 3) : null,
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
                  if (isGrid)
                    // Fixed aspect thumbnail in grid mode to ensure a deterministic height
                    AspectRatio(
                      aspectRatio: 3 / 4,
                      child: Image(
                        image: imageProvider,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.low,
                        errorBuilder: (ctx, _, __) => const ColoredBox(color: Colors.black12),
                      ),
                    )
                  else
                    Positioned.fill(
                      child: Image(
                        image: imageProvider,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.low,
                        errorBuilder: (ctx, _, __) => const ColoredBox(color: Colors.black12),
                      ),
                    ),
                  // Top-right: menu button (moved here from bottom bar)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Material(
                      color: Colors.transparent,
                      shape: const CircleBorder(),
                      elevation: 4,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => _showPopupMenu(context, widget.imagePath),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withOpacity(0.55),
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Center(child: Icon(Icons.more_vert, color: Colors.white, size: 20)),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: constraints.maxWidth - 50),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _displayLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () => widget.onSelected(widget.identifier),
                          child: Icon(
                            widget.isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                            color: widget.isSelected ? Colors.blueAccent : Colors.grey,
                            size: 28,
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
                              if (_getPrimarySocial() != null)
                                IconButton(
                                  tooltip: 'Open ${_getPrimarySocial()!.name}',
                                  iconSize: 22,
                                  color: Colors.white,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                                  onPressed: () {
                                    final s = _getPrimarySocial()!;
                                    final u = _getPrimaryUsername(s);
                                    if (u != null && u.isNotEmpty) _openSocial(s, u);
                                  },
                                  icon: () {
                                    final s = _getPrimarySocial()!;
                                    switch (s) {
                                      case SocialType.Snapchat:
                                        return SocialIcon.snapchatIconButton!.socialIcon;
                                      case SocialType.Instagram:
                                        return SocialIcon.instagramIconButton!.socialIcon;
                                      case SocialType.Discord:
                                        return SocialIcon.discordIconButton!.socialIcon;
                                      default:
                                        return const Icon(Icons.open_in_new);
                                    }
                                  }(),
                                ),
                              IconButton(
                                tooltip: 'Notes',
                                iconSize: 22,
                                color: Colors.white,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(width: 36, height: 36),
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
                                constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                                icon: const Icon(Icons.manage_accounts),
                                onPressed: () async {
                                  await showHandlesSheet(context, widget.contact);
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
        },
      ),
      ),
    );
  }
}
