import 'dart:ui';

import 'package:device_apps/device_apps.dart';
import 'package:flutter/material.dart';

class SocialIcon extends StatelessWidget{

  String social_uri;
  Widget social_icon;
  Widget not_found =  CircleAvatar(
      child:Icon(
        Icons.not_interested,
        color: Colors.red,
        size: 24.0,
        semanticLabel: 'Text to announce in accessibility modes',
      )
  );
  SocialIcon(String this.social_uri);

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: null,
      key: ValueKey(social_uri),
      backgroundColor: Colors.white,
      onPressed: () => DeviceApps.openApp(social_uri),
      child: social_icon?? FutureBuilder(
        // Get icon
          future: DeviceApps.getApp(social_uri, true),
          // Build icon when retrieved
          builder: (context, snapshot) {
            if(snapshot.connectionState == ConnectionState.done){
              var value = snapshot.data;
              ApplicationWithIcon app;
              app = (value as ApplicationWithIcon);
              social_icon = (app != null) ? Image.memory(app.icon) : not_found;
              return social_icon;
            }
            else{
              return CircularProgressIndicator();
            }
          }
      ),
    );
  }

}