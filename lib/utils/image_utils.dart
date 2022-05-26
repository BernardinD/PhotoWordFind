import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;


import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:image/image.dart' as crop_image;
import 'package:image_size_getter/file_input.dart';
import 'package:image_size_getter/image_size_getter.dart';


// Extracts text from image

Future<String> OCR(String path) async {

  final inputImage = InputImage.fromFilePath(path);
  final textDetector = GoogleMlKit.vision.textDetector();
  final RecognisedText recognisedText = await textDetector.processImage(inputImage);
  textDetector.close();
  return recognisedText.text;
  // return await FlutterTesseractOcr.extractText(path, language: 'eng');
}

// Scans in file as the Image object with adjustable features
crop_image.Image getImage(String filePath){

  List<int> bytes = File(filePath).readAsBytesSync();
  return crop_image.decodeImage(bytes);

}

// Crops image (ideally in the section of the image that has the bio)
crop_image.Image crop(crop_image.Image image, String filePath, ui.Size screenSize){

  Size size = ImageSizeGetter.getSize(FileInput(File(filePath)));
  var physicalScreenSize = ui.window.physicalSize;
  ui.Size screenSize_ = physicalScreenSize/ui.window.devicePixelRatio;


  int originX = 0,
      originY = min(size.height, (2.5 * screenSize_.height).toInt() ),
      width = size.width,
      height = min(size.height, (1.5 * screenSize_.height).toInt() );


  return crop_image.copyCrop(image, originX, originY, width, height);
}

/// Creates a cropped and resized image by passing the file and the `parent` directory to save the temporary image
File createCroppedImage(String filePath, Directory parent, ui.Size size){

  crop_image.Image image = getImage(filePath);

  // Separate the cropping and resize opperations so that the thread memory isn't used up
  crop_image.Image croppedFile = crop(image, filePath, size);
  croppedFile = crop_image.copyResize(croppedFile, height: croppedFile.height~/3 );

  // Save temp image
  String file_name = filePath.split("/").last;
  File temp_cropped = File('${parent.path}/temp-${file_name}');
  temp_cropped.writeAsBytesSync(crop_image.encodeNamedImage(croppedFile, filePath));

  return temp_cropped;
}