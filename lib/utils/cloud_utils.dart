import 'dart:convert';
import 'dart:typed_data';

import 'package:PhotoWordFind/utils/storate_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:_discoveryapis_commons/src/requests.dart' as client_requests;

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

class CloudUtils{

  static drive.File _cloudRef = null;

  static String _json_mimetype = "application/json";
  static Function get isSignedin => _googleSignIn.isSignedIn;

  static GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'https://www.googleapis.com/auth/userinfo.profile',
      'openid',
      "https://www.googleapis.com/auth/drive.file" ,
      "https://www.googleapis.com/auth/userinfo.email",
      "https://www.googleapis.com/auth/drive",
    ],
  );

  static Future handleSignIn() async {
    try {
      if(!(await _googleSignIn.isSignedIn()) || (await _googleSignIn.authenticatedClient()) == null) {
        debugPrint("Signing in...");
        final GoogleSignInAccount googleUser = await _googleSignIn.signIn();
        // GoogleAuthClient((await googleUser.authHeaders));
        debugPrint("authHeader-beginning: ${(await googleUser.authHeaders)}");
        final GoogleSignInAuthentication googleAuth = await googleUser?.authentication;
        debugPrint("user signed in: ${googleUser.email}");

      }
    } catch (error) {
      debugPrint("Google sign-in error: $error");
    }

  }

  static Future<void> handleSignOut() => _googleSignIn.disconnect();

  // Returns if device is currently connected to internet
  static Future<bool> isConnected() async{
    var connectivityResult = await Connectivity().checkConnectivity();
    debugPrint("Checking connection...");
    debugPrint( (connectivityResult == ConnectivityResult.none ? "Not " : "" ) + "Connected.");
    return connectivityResult != ConnectivityResult.none;
  }


  static Future<AuthClient> getAuthClient() async{
    handleSignIn();
    return await _googleSignIn.authenticatedClient();
  }
  static Future<GoogleAuthClient> getGoogleAuthClient() async{
    handleSignIn();
    return GoogleAuthClient((await _googleSignIn.currentUser.authHeaders));
  }

  static Future createJson(String filename)async{

    // Check connection
    if(!(await isConnected())) throw NoInternetException();

    /*
    Create JSON file
     */
    List<int> uInt8List = "{}".codeUnits;
    var uploadMedia = drive.Media(Future.value(uInt8List).asStream(), uInt8List.length);
    useDriveAPI((drive.DriveApi api) async {
      api.files.create(drive.File()
        ..name = '$filename'
        ..mimeType = '$_json_mimetype',
        uploadMedia: uploadMedia,
        /*..parents=[]*/
      );
    });

  }


  /// Returns list of existing directories names along a given path
  static Future<bool> getJSON(String name) async{

    return await useDriveAPI((drive.DriveApi api) async{

      _cloudRef = await api.files.list(
        // Set parentID if idx is passed root
          q: """mimeType = '$_json_mimetype' and name = '$name'""",
          spaces: 'drive').then((folders) {
        drive.File sub_ = folders.files.length > 0
            ? folders.files[0]
            : null;
        return sub_;
      }, onError: (e) => print("Create: " + e.toString()));


      /*
      Download raw data
       */
      drive.Media jsonMediaFile = (await api.files.get(_cloudRef.id, downloadOptions: client_requests.DownloadOptions.fullMedia));
      Stream jsonStream = jsonMediaFile.stream;
      Codec<String, String> stringToBase64 = utf8.fuse(base64);
      List<int> uInt8List = ((await jsonStream.toList())).expand(( list) => list as Uint8List).toList();
      String rawBase64 = base64.encode(uInt8List);
      String rawJSON = stringToBase64.decode(rawBase64);
      debugPrint("Raw: $rawJSON");
      Map<String, String > cloud_local_json = new Map.from(json.decode(rawJSON));


      // StorageUtils.merge(cloud_local_json);

      return _cloudRef != null;
    });
  }

  static Future updateCloudJson() async{

    return await useDriveAPI((drive.DriveApi api) async {

      /*
       Convert data to bytes
       */
      String jsonStr = json.encode(await StorageUtils.toJson());

      Codec<String, String> stringToBase64 = utf8.fuse(base64);
      String encoded = stringToBase64.encode(jsonStr);
      debugPrint("base64 encoded: $encoded}");
      debugPrint("base46: ${base64.decode(encoded)}");
      debugPrint("json: $jsonStr");
      List<int> uInt8List = base64.decode(encoded);
      debugPrint("decoded: ${String.fromCharCodes(uInt8List)}");


      /*
      Convert bytes to Drive file
       */
      Stream<List<int>> fileStream = Future.value(uInt8List).asStream();
      var uploadMedia = drive.Media(fileStream, uInt8List.length, contentType: "$_json_mimetype; charset=base64");

      /*
      Upload file
       */
      _cloudRef = await api.files.update(drive.File()
        ..name = '${_cloudRef.name}'
        ..mimeType = '${_cloudRef.mimeType}; charset=UTF-16', _cloudRef.id, uploadMedia: uploadMedia, uploadOptions: drive.UploadOptions.defaultOptions);
    });
  }

  static Future useDriveAPI(Function callback) async{
    if(!(await _googleSignIn.isSignedIn())){
      throw Exception();
    }
    final AuthClient client = await getAuthClient();

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