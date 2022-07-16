import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:PhotoWordFind/social_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/src/widgets/container.dart';
import 'package:flutter_test/flutter_test.dart';

getTestImageBytes() async{
  Uint8List bytes = (await rootBundle.load('android/app/src/main/res/mipmap-hdpi/ic_launcher.png')).buffer.asUint8List();

  // File file = File(r"C:\Users\deziu\Documents\PhotoWordFind\web\icons\Icon-512.png");
  // Uint8List bytes = Uint8List.fromList(file.readAsBytesSync());
  return base64.encode(bytes);
}

void main(){
  setUp((){

  });

  testWidgets("Test Successful icon", (tester) async {


    const channel = MethodChannel('g123k/device_apps');
    handler(MethodCall methodCall) async {
      print("Came in");
      print("Returning...");
      return <String, dynamic>{
        'appName': 'myapp',
        'packageName': 'com.mycompany.myapp',
        'appIcon': 'com.mycompany.myapp',
        'version': '0.0.1',
        'buildNumber': '1',
        'app_icon' : await getTestImageBytes(),
        'package_name' : "",
        'app_name': "",
        'apk_file_path': "",
        'version_name': "",
        'version_code': 0,
        'data_dir': "",
        'system_app': false,
        'install_time': 0,
        'update_time': 0,
        'is_enabled': false,
        'category':-1,
      };
    }

    TestWidgetsFlutterBinding.ensureInitialized();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);

    var test = SocialIcon('Test');
    await tester.pumpWidget(MaterialApp(home: test));
    await tester.pump();

    expect(test.social_icon, isNotNull);
  });
}