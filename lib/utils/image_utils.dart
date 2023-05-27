import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;


import 'package:flutter/widgets.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as crop_image;


// Extracts text from image

// ignore: non_constant_identifier_names
Future<String> OCR(String path) async {

  final inputImage = InputImage.fromFilePath(path);
  final textDetector = TextRecognizer();
  final RecognizedText recognisedText = await textDetector.processImage(inputImage);
  textDetector.close();
  return recognisedText.text;
}

// Scans in file as the Image object with adjustable features
crop_image.Image getImage(String filePath){

  List<int> bytes = File(filePath).readAsBytesSync();
  return crop_image.decodeImage(bytes as Uint8List)!;

}

// Crops image (ideally in the section of the image that has the bio)
crop_image.Image crop(crop_image.Image image, String filePath, ui.Size screenSize){

  debugPrint("Entering crop()...");
  var physicalScreenSize = ui.window.physicalSize;
  ui.Size screenSize_ = physicalScreenSize/ui.window.devicePixelRatio;

  debugPrint("physicalScreenSize: $physicalScreenSize");
  debugPrint("screenSize vs. screenSize_  >> $screenSize vs. $screenSize_");

  int originX = 0,
      originY = min(image.height, (2.5 * screenSize.height).toInt() ),
      width = image.width,
      height = min(image.height, (1.5 * screenSize.height).toInt() );


  debugPrint("Leaving crop()...");
  return crop_image.copyCrop(image, x: originX, y: originY, width: width, height: height);
}

/// Creates a cropped and resized image by passing the file and the `parent` directory to save the temporary image
File createCroppedImage(String filePath, Directory parent, ui.Size size){

  debugPrint("Entering createCroppedImage()...");
  crop_image.Image image = getImage(filePath);

  // Separate the cropping and resize operations so that the thread memory isn't used up
  crop_image.Image croppedFile = crop(image, filePath, size);
  croppedFile = crop_image.copyResize(croppedFile, height: croppedFile.height~/3 );

  // Save temp image
  String fileName = filePath.split("/").last;
  File tempCropped = File('${parent.path}/temp-$fileName');
  tempCropped.writeAsBytesSync(crop_image.encodeNamedImage(filePath, croppedFile)!);

  debugPrint("Leaving createCroppedImage()...");
  return tempCropped;
}