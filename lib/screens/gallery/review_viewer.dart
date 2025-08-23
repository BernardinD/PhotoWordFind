import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:PhotoWordFind/models/contactEntry.dart';
import 'package:PhotoWordFind/screens/gallery/widgets/handles_sheet.dart';

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

  ContactEntry get _current => widget.images[_index];

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.images.length - 1);
    _pageController = PageController(initialPage: _index);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: widget.images.length,
              onPageChanged: (i) => setState(() => _index = i),
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
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black54],
                  ),
                ),
                child: Row(
                  children: [
                    FilledButton.icon(
                      onPressed: _showDetailsSheet,
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('Details'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await showHandlesSheet(context, _current);
                        setState(() {});
                      },
                      icon: const Icon(Icons.manage_accounts),
                      label: const Text('Handles'),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white70)),
                    ),
                    const Spacer(),
                    IconButton(
                      color: Colors.white,
                      icon: const Icon(Icons.chevron_left, size: 30),
                      onPressed: _index > 0
                          ? () => _pageController.animateToPage(_index - 1, duration: const Duration(milliseconds: 200), curve: Curves.easeOut)
                          : null,
                    ),
                    IconButton(
                      color: Colors.white,
                      icon: const Icon(Icons.chevron_right, size: 30),
                      onPressed: _index < widget.images.length - 1
                          ? () => _pageController.animateToPage(_index + 1, duration: const Duration(milliseconds: 200), curve: Curves.easeOut)
                          : null,
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
