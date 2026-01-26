import 'dart:io';
import 'package:image/image.dart' as imglib;

/// Splits tall screenshots into overlapping square slices (width x width)
/// to keep vertical text readable by vision models while preserving color data.
List<File> sliceImageIntoOverlappingSquares(
  File imageFile, {
  double overlapRatio = 0.25,
}) {
  final image = imglib.decodeImage(imageFile.readAsBytesSync());

  if (image == null) {
    throw Exception('Unable to decode image.');
  }

  if (overlapRatio < 0 || overlapRatio >= 1) {
    throw ArgumentError('overlapRatio must be in [0, 1).');
  }

  final int chunkWidth = image.width;
  final int chunkHeight =
      image.width <= image.height ? image.width : image.height;
  int stride = chunkHeight - (chunkHeight * overlapRatio).round();
  if (stride < 1) {
    stride = 1;
  }

  final List<File> chunks = [];
  int startY = 0;
  int index = 0;

  while (true) {
    final int safeY = startY + chunkHeight > image.height
        ? image.height - chunkHeight
        : startY;

    final chunk = imglib.copyCrop(
      image,
      x: 0,
      y: safeY,
      width: chunkWidth,
      height: chunkHeight,
    );

    final chunkFile = File('${imageFile.path}_chunk_$index.jpg')
      ..writeAsBytesSync(imglib.encodeJpg(chunk));
    chunks.add(chunkFile);

    if (safeY + chunkHeight >= image.height) {
      break;
    }

    startY += stride;
    index++;
  }

  return chunks;
}
