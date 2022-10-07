import 'package:PhotoWordFind/utils/cloud_utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageUtils{


  static Future<SharedPreferences> _getStorageInstance({@required bool reload}) async{
    var ret = await SharedPreferences.getInstance();
    if(reload)
      ret.reload();

    return ret;
  }

  static Future save(String key, String value) async{
    (await _getStorageInstance(reload: false)).setString(key, value);

    // Save to cloud
    // TODO: Put this inside a timer that saves a few seconds after a save call
    if(await CloudUtils.isSignedin()){
      await CloudUtils.updateCloudJson();
    }
  }

  static Future<String> get(String key, {@required bool reload}) async{
    return (await _getStorageInstance(reload: reload)).getString(key);

  }

  static Future merge(Map<String, String> cloud){
    for(String key in cloud.keys){
      if(get(key, reload: true) == null){
        save(key, cloud[key]);
        debugPrint("Saving...");
      }
      else{
        // Print whether cloud value and Storage values match
        get(key, reload: false).then((value) {
          // debugPrint("String ($key) matches: ${(value == cloud[key])}");

          if(value != cloud[key]){
            throw Exception("Cloud and local copies don't match");
          }
        });
      }
    }
  }

  static Future<Map<String, String>> toMap() async{
    var store = await _getStorageInstance(reload: true);
    Map<String, String> ret = Map();

    for(String key in store.getKeys()){
      ret[key] = store.getString(key);
    }

    return ret;
  }
}