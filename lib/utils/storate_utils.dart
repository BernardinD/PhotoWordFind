import 'package:PhotoWordFind/utils/cloud_utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageUtils{


  Future<SharedPreferences> _getStorageInstance({@required bool reload}) async{
    var ret = await SharedPreferences.getInstance();
    ret.reload();
    return ret;
  }

  Future save(String key, String value) async{
    (await _getStorageInstance(reload: false)).setString(key, value);

    // Save to cloud
    if(CloudUtils.isSignedin()){
      // ...
    }
  }

  Future get(String key, {@required bool reload}) async{
    (await _getStorageInstance(reload: reload)).getString(key);

  }
}