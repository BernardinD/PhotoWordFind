import 'dart:io';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:PhotoWordFind/utils/image_utils.dart';

class RedoCropScreen extends StatefulWidget {
  const RedoCropScreen({super.key, required this.imageFile});

  final File imageFile;

  @override
  State<RedoCropScreen> createState() => _RedoCropScreenState();
}

class _RedoCropScreenState extends State<RedoCropScreen> {
  final CropController _controller = CropController();
  bool _processing = false;
  static bool _hintShown = false;
  late bool _showHint;

  @override
  void initState() {
    super.initState();
    _showHint = !_hintShown;
    _hintShown = true;
  }

  Future<void> _onCropped(CropResult result) async {
    if (result is! CropSuccess) return;
    setState(() => _processing = true);
    final dir = await getTemporaryDirectory();
    final file = await File('${dir.path}/redo.png').create();
    await file.writeAsBytes(result.croppedImage);
    final text = await OCR(file.path);
    if (!mounted) return;
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Crop(
            controller: _controller,
            image: widget.imageFile.readAsBytesSync(),
            onCropped: _onCropped,
          ),
          if (_showHint)
            Positioned(
              top: 40,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.black54,
                  child: const Text(
                    'Select the area to scan again',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: _processing
                  ? const SizedBox(
                      height: 40,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () => _controller.crop(),
                          child: const Text('Redo'),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
