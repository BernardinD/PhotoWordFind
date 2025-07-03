import 'dart:convert';
import 'dart:io';

import 'package:PhotoWordFind/main.dart';
import 'package:PhotoWordFind/models/contactEntry.dart';
import 'package:PhotoWordFind/utils/storage_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:_discoveryapis_commons/_discoveryapis_commons.dart'
    as client_requests;

import 'package:googleapis_auth/auth_io.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';

import 'package:googleapis/drive/v3.dart' as drive;

import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';

class AppException implements Exception {
  String cause;
  AppException(this.cause);
}

class NoInternetException extends AppException {
  NoInternetException() : super("No Internet. Check connection");
}

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;

  final http.Client _client = new http.Client();

  GoogleAuthClient(this._headers);

  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}

class CloudUtils {
  static drive.File? _cloudRef;

  static String _jsonMimetype = "application/json";
  static Function get isSignedin => _googleSignIn.isSignedIn;
  static JsonEncoder _jsonEncoder = JsonEncoder.withIndent('    ');
  // static String _jsonBackupFile = "PWF_scans_backup.json";
  static String _jsonTestingNewUIBackup = "testing_new_UI.json";
  // static String _jsonBackupFile = "test_auto_create_file2.json";

  static GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'https://www.googleapis.com/auth/userinfo.profile',
      'openid',
      "https://www.googleapis.com/auth/drive.file",
      "https://www.googleapis.com/auth/userinfo.email",
      "https://www.googleapis.com/auth/drive",
    ],
  );

  static Future<bool> firstSignIn() {
    return handleSignIn().then((bool value) {
      if (value) {
        CloudUtils.getCloudJson().then((bool found) {
          if (!found) {
            CloudUtils.createCloudJson();
          }
        }).onError((dynamic error, stackTrace) async =>
            Future.value(debugPrint("$error \n $stackTrace") as Null));
      }

      return value;
    });
  }

  static Future possibleSignOut() async {
    // TODO: Show confirmation dialog
    // ...

    return signOut();
  }

  static Future signOut() async {
    MyApp.pr.show(max: 1);
    MyApp.pr.update(value: 0, msg: "Signing out...");
    await updateCloudJson();

    // TODO: Clear current local storage
    // ...

    return handleSignOut().then((value) => MyApp.pr.update(value: 1));
  }

  static Future<bool> handleSignIn() async {
    try {
      if (!(await _googleSignIn.isSignedIn()) ||
          (await _googleSignIn.authenticatedClient()) == null) {
        debugPrint("Signing in...");
        final GoogleSignInAccount googleUser = (await _googleSignIn.signIn())!;
        debugPrint("authHeader-beginning: ${(await googleUser.authHeaders)}");
        debugPrint("user signed in: ${googleUser.email}");
        return _googleSignIn.isSignedIn();
      }
    } catch (error) {
      debugPrint("Google sign-in error: $error");
    }

    return false;
  }

  static Future<void> handleSignOut() => _googleSignIn.disconnect();

  // Returns if device is currently connected to internet
  static Future<bool> isConnected() async {
    var connectivityResult = await Connectivity().checkConnectivity();
    debugPrint("Checking connection...");
    debugPrint((connectivityResult == ConnectivityResult.none ? "Not " : "") +
        "Connected.");
    return connectivityResult != ConnectivityResult.none;
  }

  static Future<AuthClient?> _getAuthClient() async {
    handleSignIn();
    return await _googleSignIn.authenticatedClient();
  }

  static Future<bool> createCloudJson() async {
    // Check connection
    if (!(await isConnected())) throw NoInternetException();

    /*
    Create JSON file
     */
    debugPrint("Creating new json");
    List<int> uInt8List = "{}".codeUnits;
    var uploadMedia =
        drive.Media(Future.value(uInt8List).asStream(), uInt8List.length);
    Future response = _useDriveAPI((drive.DriveApi api) async {
      return api.files.create(
        drive.File()
          ..name = '$_jsonTestingNewUIBackup'
          ..mimeType = '$_jsonMimetype',
        uploadMedia: uploadMedia,
        /*..parents=[]*/
      );
    });

    return response.then((value) => getCloudJson()).then((value) {
      if (value) debugPrint("File created");
      return value;
    });
  }

  /// Returns list of existing directories names along a given path
  static Future<bool> getCloudJson() async {
    debugPrint("Entering getCloudJson()...");

    return await (_useDriveAPI((drive.DriveApi api) async {
      _cloudRef = await api.files.list(
          // Set parentID if idx is passed root
          q: """mimeType = '$_jsonMimetype' and name = '$_jsonTestingNewUIBackup'""",
          spaces: 'drive').then((folders) {
        drive.File? sub_ = folders.files![0];
        return sub_;
      });

      if (_cloudRef == null) {
        debugPrint("Could not find file");
        return false;
      }

      /*
      Download raw data
       */
      Future getFile = api.files.get(_cloudRef!.id!,
          downloadOptions: client_requests.DownloadOptions.fullMedia);
      drive.Media jsonMediaFile = (await getFile) as drive.Media;
      Stream jsonStream = jsonMediaFile.stream;
      Codec<String, String> stringToBase64 = utf8.fuse(base64);
      List<int> uInt8List = ((await jsonStream.toList()))
          .expand((list) => list as Uint8List)
          .toList();
      String rawBase64 = base64.encode(uInt8List);
      String rawJSON = stringToBase64.decode(rawBase64);
      // debugPrint("Raw: $rawJSON");
      Map<String, String> cloudLocalJson = new Map.from(json.decode(rawJSON));

      // TODO: move this logic into merge()
      List<ContactEntry> images = [];
      List<String> dirs = ["Buzz buzz", "Honey", "Strings", "Stale", "Comb"];
      cloudLocalJson.forEach((String key, dynamic value) {
        String? dir = null;
        dirs.forEach((_dir) {
          if (File("/storage/emulated/0/DCIM/$_dir/$key.jpg").existsSync()) {
            dir = _dir;
          }
        });
        if (dir == null) {
          return;
        }
        images.add(ContactEntry.fromJson(
            key, "/storage/emulated/0/DCIM/$dir/$key.jpg", jsonDecode(value)));
      });

      await StorageUtils.merge(cloudLocalJson);
      MyApp.updateFrame(() => null);

      debugPrint("Leaving getCloudJson()...");
      return _cloudRef != null;
    }));
  }

  static Future updateCloudJson() async {
    return await _useDriveAPI((drive.DriveApi api) async {
      /*
       Convert data to bytes
       */
      String jsonStr = _jsonEncoder.convert(await StorageUtils.toMap());

      Codec<String, String> stringToBase64 = utf8.fuse(base64);
      String encoded = stringToBase64.encode(jsonStr);

      List<int> uInt8List = base64.decode(encoded);

      /*
      Convert bytes to Drive file
       */
      Stream<List<int>> fileStream = Future.value(uInt8List).asStream();
      var uploadMedia = drive.Media(fileStream, uInt8List.length,
          contentType: "$_jsonMimetype");

      /*
      Upload file
       */
      debugPrint("backup file: ${_cloudRef!.name}");
      _cloudRef = await api.files.update(
          drive.File()
            ..name = '${_cloudRef!.name}'
            ..mimeType = '${_cloudRef!.mimeType}',
          _cloudRef!.id!,
          uploadMedia: uploadMedia,
          uploadOptions: drive.UploadOptions.defaultOptions);
    });
  }

  static Future _useDriveAPI(Function callback) async {
    if (!(await _googleSignIn.isSignedIn())) {
      throw Exception();
    }
    final AuthClient client = (await _getAuthClient())!;

    // Initialize DriveAPI
    // developer.log("getting DriveApi");
    var api = new drive.DriveApi(client);
    // developer.log("retrieved DriveApi.");

    // Run custom function
    var ret = await callback(api);
    client.close();

    // Return result of dynamic callback
    return ret;
  }
}
