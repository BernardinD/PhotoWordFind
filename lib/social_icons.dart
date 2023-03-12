import 'package:device_apps/device_apps.dart';
import 'package:flutter/material.dart';

class SocialIcon extends StatelessWidget {
  static var _snapchatIconButton,
      _galleryIconButton,
      _bumbleIconButton,
      _instagramIconButton,
      _discordIconButton,
      _kikIconButton;

  static SocialIcon get snapchatIconButton => _snapchatIconButton;
  static SocialIcon get galleryIconButton => _galleryIconButton;
  static SocialIcon get instagramIconButton => _instagramIconButton;
  static SocialIcon get kikIconButton => _kikIconButton;
  static SocialIcon get bumbleIconButton => _bumbleIconButton;
  static SocialIcon get discordIconButton => _discordIconButton;

  static final String _snapchatUri = 'com.snapchat.android',
      _galleryUri = 'com.sec.android.gallery3d',
      _bumbleUri = 'com.bumble.app',
      _instagramUri = 'com.instagram.android',
      _discordUri = 'com.discord',
      _kikUri = 'kik.android';

  final String socialUri;
  Widget socialIcon;
  final Widget notFound = CircleAvatar(
      child: Icon(
    Icons.not_interested,
    color: Colors.red,
    size: 24.0,
    semanticLabel: 'Text to announce in accessibility modes',
  ));
  SocialIcon._(this.socialUri);

  static initializeIcons() {
    _snapchatIconButton = SocialIcon._(_snapchatUri);
    _galleryIconButton = SocialIcon._(_galleryUri);
    _bumbleIconButton = SocialIcon._(_bumbleUri);
    _instagramIconButton = SocialIcon._(_instagramUri);
    _discordIconButton = SocialIcon._(_discordUri);
    _kikIconButton = SocialIcon._(_kikUri);
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: null,
      key: ValueKey(socialUri),
      backgroundColor: Colors.white,
      onPressed: () => DeviceApps.openApp(socialUri),
      child: socialIcon ??
          FutureBuilder(
              // Get icon
              future: DeviceApps.getApp(socialUri, true),
              // Build icon when retrieved
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done) {
                  var value = snapshot.data;
                  ApplicationWithIcon app;
                  app = (value as ApplicationWithIcon);
                  socialIcon =
                      (app != null) ? Image.memory(app.icon) : notFound;
                  return socialIcon;
                } else {
                  return CircularProgressIndicator();
                }
              }),
    );
  }
}
