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
  // static String _jsonTestingNewUIBackup = "testing_new_UI.json";
  static String _jsonBackupFile = "test_auto_create_file2.json";

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

  /// Returns the email of the currently signed in user, or null if not signed in.
  static String? get currentUserEmail => _googleSignIn.currentUser?.email;

  /// Optional progress callback for UI layers (old or new UIs) to observe
  /// cloud operations. UI can assign a function to receive progress updates
  /// instead of CloudUtils depending on a concrete ProgressDialog.
  /// value: 0.0-1.0 (nullable if only message update)
  /// message: status text
  /// done: whether the operation has finished (success or error)
  /// error: whether the operation ended with error
  static void Function({double? value, String? message, bool done, bool error})?
      progressCallback;

  static void _reportProgress(
      {double? value, String? message, bool done = false, bool error = false}) {
    try {
      progressCallback?.call(
          value: value, message: message, done: done, error: error);
    } catch (e) {
      debugPrint("progressCallback threw: $e");
    }
  }

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
    return signOut();
  }

  /// Signs out the current Google session.
  /// 1. Optionally syncs (updateCloudJson) before disconnect (default true)
  /// 2. Disconnects Google sign-in
  /// No UI side-effects; callers hook into [progressCallback] if desired.
  static Future<void> signOut({bool syncBefore = true}) async {
    _reportProgress(value: 0, message: "Signing out...");
    try {
      if (syncBefore) {
        _reportProgress(message: "Updating cloud backup...");
        await updateCloudJson();
      }
      _reportProgress(message: "Disconnecting account...");
      await handleSignOut();
      _reportProgress(value: 1, message: "Signed out", done: true);
    } catch (e, s) {
      debugPrint("signOut error: $e\n$s");
      _reportProgress(message: "Sign out failed: $e", done: true, error: true);
      rethrow; // Allow caller to decide
    }
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
    try {
      final bool wasSignedIn = await _googleSignIn.isSignedIn();
      GoogleSignInAccount? user;
      try {
        user = await _googleSignIn.signInSilently();
      } catch (e) {
        debugPrint('Silent sign-in threw: $e');
      }
      user ??= _googleSignIn.currentUser;
      if (user == null && !wasSignedIn) {
        debugPrint('No signed-in Google account available for auth client.');
        return null;
      }
      final client = await _googleSignIn.authenticatedClient();
      if (client == null) {
        debugPrint('Authenticated client was null after silent refresh.');
      }
      return client;
    } catch (e) {
      debugPrint('Failed to obtain authenticated client: $e');
      return null;
    }
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
          ..name = '$_jsonBackupFile'
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
  static Future<bool> getCloudJson({bool merge = true}) async {
    debugPrint("Entering getCloudJson()...");

    return await (_useDriveAPI((drive.DriveApi api) async {
      _cloudRef = await api.files.list(
          // Set parentID if idx is passed root
          q: """mimeType = '$_jsonMimetype' and name = '$_jsonBackupFile'""",
          spaces: 'drive').then((folders) {
        drive.File? sub_ = folders.files![0];
        return sub_;
      });

      if (_cloudRef == null) {
        debugPrint("Could not find file");
        return false;
      }

      if (!merge) {
        debugPrint("Leaving getCloudJson() (metadata only)...");
        return _cloudRef != null;
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

      StorageUtils.merge(cloudLocalJson)
          .then((value) => LegacyAppShell.updateFrame?.call(() => null));

      debugPrint("Leaving getCloudJson()...");
      return _cloudRef != null;
    }));
  }

  /// Ensures [_cloudRef] points to the Drive file backing the JSON backup.
  /// Fetches the existing file metadata or attempts creation if missing.
  static Future<void> _ensureCloudReference() async {
    if (_cloudRef != null) return;
    final found = await getCloudJson(merge: false);
    if (found) {
      debugPrint('Cloud reference loaded.');
      return;
    }
    final created = await createCloudJson();
    if (!created) {
      throw StateError('Failed to create cloud backup file.');
    }
    if (!await getCloudJson(merge: false)) {
      throw StateError('Unable to load cloud backup file after creation.');
    }
    debugPrint('Cloud reference created.');
  }

  static Future updateCloudJson() async {
    debugPrint('Starting cloud JSON update...');
    await _ensureCloudReference();
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
      debugPrint('Cloud JSON update complete.');
    });
  }

  static Future _useDriveAPI(Function callback) async {
    if (!(await _googleSignIn.isSignedIn())) {
      throw StateError('Google account is not signed in.');
    }
    final AuthClient? client = await _getAuthClient();
    if (client == null) {
      throw StateError('Unable to obtain Google auth client for Drive access.');
    }

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
