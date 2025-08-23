import 'package:flutter/material.dart';
import 'package:PhotoWordFind/models/contactEntry.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'package:PhotoWordFind/utils/storage_utils.dart';

/// Opens a bottom sheet to view, edit, and verify usernames for a contact entry.
Future<void> showHandlesSheet(BuildContext context, ContactEntry contact) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.25,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          final theme = Theme.of(context);
          return Container(
            decoration: BoxDecoration(
              color: theme.canvasColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 12,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: _HandlesSheet(contact: contact, scrollController: scrollController),
          );
        },
      );
    },
  );
}

class _HandlesSheet extends StatefulWidget {
  final ContactEntry contact;
  final ScrollController scrollController;
  const _HandlesSheet({required this.contact, required this.scrollController});

  @override
  State<_HandlesSheet> createState() => _HandlesSheetState();
}

class _HandlesSheetState extends State<_HandlesSheet> {
  late TextEditingController _snap;
  late TextEditingController _insta;
  late TextEditingController _discord;

  @override
  void initState() {
    super.initState();
    _snap = TextEditingController(text: widget.contact.snapUsername ?? '');
    _insta = TextEditingController(text: widget.contact.instaUsername ?? '');
    _discord = TextEditingController(text: widget.contact.discordUsername ?? '');
  }

  @override
  void dispose() {
    _snap.dispose();
    _insta.dispose();
    _discord.dispose();
    super.dispose();
  }

  void _setCurrent(String platform, String value) async {
    setState(() {
      if (platform == SubKeys.SnapUsername) {
        widget.contact.updateSnapchat(value);
        _snap.text = value;
      } else if (platform == SubKeys.InstaUsername) {
        widget.contact.updateInstagram(value);
        _insta.text = value;
      } else if (platform == SubKeys.DiscordUsername) {
        widget.contact.updateDiscord(value);
        _discord.text = value;
      }
    });
  }

  void _toggleVerified(String platform) {
    setState(() {
      if (platform == SubKeys.SnapUsername) {
        if (widget.contact.addedOnSnap) {
          widget.contact.resetSnapchatAdd();
        } else {
          widget.contact.addSnapchat();
        }
      } else if (platform == SubKeys.InstaUsername) {
        if (widget.contact.addedOnInsta) {
          widget.contact.resetInstagramAdd();
        } else {
          widget.contact.addInstagram();
        }
      } else if (platform == SubKeys.DiscordUsername) {
        if (widget.contact.addedOnDiscord) {
          widget.contact.resetDiscordAdd();
        } else {
          widget.contact.addDiscord();
        }
      }
    });
  }

  void _openExternal(String platform) {
    String? value;
    if (platform == SubKeys.SnapUsername) {
      value = widget.contact.snapUsername;
    } else if (platform == SubKeys.InstaUsername) {
      value = widget.contact.instaUsername;
    } else if (platform == SubKeys.DiscordUsername) {
      value = widget.contact.discordUsername;
    }
    if (value == null || value.isEmpty) return;
    if (platform == SubKeys.SnapUsername) {
      launchUrl(Uri.parse('https://www.snapchat.com/add/${value.toLowerCase()}'), mode: LaunchMode.externalApplication);
    } else if (platform == SubKeys.InstaUsername) {
      launchUrl(Uri.parse('https://www.instagram.com/$value'), mode: LaunchMode.externalApplication);
    } else if (platform == SubKeys.DiscordUsername) {
      Clipboard.setData(ClipboardData(text: value));
    }
  }

  Iterable<String> _candidatesFor(String platform) {
    final set = <String>{};
    final social = widget.contact.socialMediaHandles;
    if (social != null) {
      final value = social[platform];
      if (value != null && value.isNotEmpty) set.add(value);
    }
    final prev = widget.contact.previousHandles;
    if (prev != null && prev[platform] != null) {
      set.addAll(prev[platform]!.where((e) => e.isNotEmpty));
    }
    // Heuristic: scan sections for obvious candidates
    final sections = widget.contact.sections;
    if (sections != null) {
      for (final map in sections) {
        for (final entry in map.entries) {
          final v = entry.value;
          if (platform == SubKeys.InstaUsername && (entry.key.toLowerCase().contains('insta') || v.startsWith('@'))) {
            set.add(v.replaceFirst('@', ''));
          }
          if (platform == SubKeys.SnapUsername && entry.key.toLowerCase().contains('snap')) {
            set.add(v);
          }
          if (platform == SubKeys.DiscordUsername && entry.key.toLowerCase().contains('discord')) {
            set.add(v);
          }
        }
      }
    }
    // Remove the current to avoid duplicate chip emphasizing
    String? current;
    if (platform == SubKeys.SnapUsername) {
      current = widget.contact.snapUsername;
    } else if (platform == SubKeys.InstaUsername) {
      current = widget.contact.instaUsername;
    } else if (platform == SubKeys.DiscordUsername) {
      current = widget.contact.discordUsername;
    }
    if (current != null) set.remove(current);
    return set.take(12);
  }

  Widget _platformSection({
    required String title,
    required String platformKey,
    required TextEditingController controller,
    required bool verified,
    DateTime? verifiedAt,
  }) {
  final suggestions = _candidatesFor(platformKey).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              if (verified)
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.verified, size: 16, color: Colors.white),
                  backgroundColor: Colors.green.shade600,
                  label: Text(verifiedAt != null ? 'Verified ${_fmt(verifiedAt)}' : 'Verified', style: const TextStyle(color: Colors.white)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    labelText: 'Username',
                  ),
                  onSubmitted: (v) => _setCurrent(platformKey, v.trim()),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Set current',
                onPressed: () => _setCurrent(platformKey, controller.text.trim()),
                icon: const Icon(Icons.check_circle_outline),
              ),
              IconButton(
                tooltip: 'Open',
                onPressed: () => _openExternal(platformKey),
                icon: const Icon(Icons.open_in_new),
              ),
              IconButton(
                tooltip: verified ? 'Unmark verified' : 'Mark verified',
                onPressed: () => _toggleVerified(platformKey),
                icon: Icon(verified ? Icons.verified : Icons.verified_outlined, color: verified ? Colors.green : null),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (suggestions.isNotEmpty)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                leading: const Icon(Icons.lightbulb_outline),
                title: Text('Suggestions (${suggestions.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
                childrenPadding: EdgeInsets.zero,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: suggestions
                        .map((c) => ActionChip(
                              label: Text(c),
                              avatar: const Icon(Icons.flip_to_front, size: 16),
                              onPressed: () => _setCurrent(platformKey, c),
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
          left: 16,
          right: 16,
          top: 8,
        ),
        child: SingleChildScrollView(
          controller: widget.scrollController,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.manage_accounts),
                  const SizedBox(width: 8),
                  const Text('Handles & Verification', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (File(widget.contact.imagePath).existsSync())
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(widget.contact.imagePath),
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              const SizedBox(height: 12),
              _platformSection(
                title: 'Snapchat',
                platformKey: SubKeys.SnapUsername,
                controller: _snap,
                verified: widget.contact.addedOnSnap,
                verifiedAt: widget.contact.dateAddedOnSnap,
              ),
              _platformSection(
                title: 'Instagram',
                platformKey: SubKeys.InstaUsername,
                controller: _insta,
                verified: widget.contact.addedOnInsta,
                verifiedAt: widget.contact.dateAddedOnInsta,
              ),
              _platformSection(
                title: 'Discord',
                platformKey: SubKeys.DiscordUsername,
                controller: _discord,
                verified: widget.contact.addedOnDiscord,
                verifiedAt: widget.contact.dateAddedOnDiscord,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

String _fmt(DateTime dt) {
  final now = DateTime.now();
  final isSameDay = dt.year == now.year && dt.month == now.month && dt.day == now.day;
  if (isSameDay) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }
  return '${dt.month}/${dt.day}/${dt.year}';
}
