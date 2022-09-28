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
    if(CloudUtils.isSignedin()){
      // ...
    }
  }

  static Future get(String key, {@required bool reload}) async{
    (await _getStorageInstance(reload: reload)).getString(key);

  }

  static Future merge(Map<String, String> cloud){
    for(String key in cloud.keys){
      if(get(key) != null){
        save(key, cloud[key]);
      }
    }
  }
}