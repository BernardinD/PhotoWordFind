import 'dart:ui';

import 'package:device_apps/device_apps.dart';
import 'package:flutter/material.dart';

class SocialIcon extends StatelessWidget {
  static var _snapchat_icon,
      _gallery_icon,
      _bumble_icon,
      _instagram_icon,
      _discord_icon,
      _kik_icon;

  static SocialIcon get snapchat_icon => _snapchat_icon;
  static SocialIcon get gallery_icon => _gallery_icon;
  static SocialIcon get instagram_icon => _instagram_icon;
  static SocialIcon get kik_icon => _kik_icon;
  static SocialIcon get bumble_icon => _bumble_icon;
  static SocialIcon get discord_icon => _discord_icon;

  static final String _snapchat_uri = 'com.snapchat.android',
      _gallery_uri = 'com.sec.android.gallery3d',
      _bumble_uri = 'com.bumble.app',
      _instagram_uri = 'com.instagram.android',
      _discord_uri = 'com.discord',
      _kik_uri = 'kik.android';

  String social_uri;
  Widget social_icon;
  Widget not_found = CircleAvatar(
      child: Icon(
    Icons.not_interested,
    color: Colors.red,
    size: 24.0,
    semanticLabel: 'Text to announce in accessibility modes',
  ));
  SocialIcon._(String this.social_uri);

  static initializeIcons() {
    _snapchat_icon = SocialIcon._(_snapchat_uri);
    _gallery_icon = SocialIcon._(_gallery_uri);
    _bumble_icon = SocialIcon._(_bumble_uri);
    _instagram_icon = SocialIcon._(_instagram_uri);
    _discord_icon = SocialIcon._(_discord_uri);
    _kik_icon = SocialIcon._(_kik_uri);
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: null,
      key: ValueKey(social_uri),
      backgroundColor: Colors.white,
      onPressed: () => DeviceApps.openApp(social_uri),
      child: social_icon ??
          FutureBuilder(
              // Get icon
              future: DeviceApps.getApp(social_uri, true),
              // Build icon when retrieved
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done) {
                  var value = snapshot.data;
                  ApplicationWithIcon app;
                  app = (value as ApplicationWithIcon);
                  social_icon =
                      (app != null) ? Image.memory(app.icon) : not_found;
                  return social_icon;
                } else {
                  return CircularProgressIndicator();
                }
              }),
    );
  }
}
