import 'package:PhotoWordFind/utils/storage_utils.dart';
import 'package:device_apps/device_apps.dart';
import 'package:flutter/material.dart';

class SocialIcon extends StatelessWidget {
  static late final _snapchatIconButton = SocialIcon._(_snapchatUri),
    _galleryIconButton = SocialIcon._(_galleryUri),
    _bumbleIconButton = SocialIcon._(_bumbleUri),
    _instagramIconButton = SocialIcon._(_instagramUri),
    _discordIconButton = SocialIcon._(_discordUri),
    _kikIconButton = SocialIcon._(_kikUri);

  static SocialIcon? get snapchatIconButton => _snapchatIconButton;
  static SocialIcon? get galleryIconButton => _galleryIconButton;
  static SocialIcon? get instagramIconButton => _instagramIconButton;
  static SocialIcon? get kikIconButton => _kikIconButton;
  static SocialIcon? get bumbleIconButton => _bumbleIconButton;
  static SocialIcon? get discordIconButton => _discordIconButton;

  static final String _snapchatUri = 'com.snapchat.android',
      _galleryUri = 'com.sec.android.gallery3d',
      _bumbleUri = 'com.bumble.app',
      _instagramUri = 'com.instagram.android',
      _discordUri = 'com.discord',
      _kikUri = 'kik.android';

  final String socialUri;
  late final Widget socialIcon = getSocialIconFromUri();
  final Widget notFound = CircleAvatar(
      child: Icon(
    Icons.not_interested,
    color: Colors.red,
    size: 24.0,
    semanticLabel: 'Text to announce in accessibility modes',
  ));
  SocialIcon._(this.socialUri);

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: null,
      key: ValueKey(socialUri),
      backgroundColor: Colors.white,
      onPressed: openApp ,
      child: socialIcon,
    );
  }

  void openApp(){
    DeviceApps.openApp(socialUri);
  }

  Widget getSocialIconFromUri() {
    return FutureBuilder(
      // Get icon
      future: DeviceApps.getApp(socialUri, true),
      // Build icon when retrieved
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          var value = snapshot.data;
          ApplicationWithIcon? app;
          app = (value as ApplicationWithIcon?);
          return (app != null) ? Image.memory(app.icon) : notFound;
        } else {
          return CircularProgressIndicator();
        }
      },
    );
  }
}


enum SocialType{
  Snapchat,
  Instagram,
  Discord,
  Kik,

}

extension SocialTypeExtension on SocialType{
  Widget? get icon{
    switch (this) {
      case SocialType.Snapchat:
        return SocialIcon.snapchatIconButton!.socialIcon;
      case SocialType.Instagram:
        return SocialIcon.instagramIconButton!.socialIcon;
      case SocialType.Discord:
        return SocialIcon.discordIconButton!.socialIcon;
      case SocialType.Kik:
        return SocialIcon.kikIconButton!.socialIcon;
      default:
        return null;
    }
  }

  Future getUserName(String key) async{
    switch (this) {
      case SocialType.Snapchat:
        return StorageUtils.get(key, reload: false, snap:true);
      case SocialType.Instagram:
      return StorageUtils.get(key, reload: false, insta:true);
      case SocialType.Discord:
        return StorageUtils.get(key, reload: false, discord:true);
      case SocialType.Kik:
      // return SocialIcon.kikIconButton.socialIcon;
      default:
        return null;
    }
  }

  saveUsername(String key, String value, {required bool overriding}) async {
    switch (this) {
      case SocialType.Snapchat:
        StorageUtils.save(key, backup: true, snap:value, overridingUsername: overriding);
        break;
      case SocialType.Instagram:
        StorageUtils.save(key, backup: true, insta:value, overridingUsername: overriding);
        break;
      case SocialType.Discord:
        StorageUtils.save(key, backup: true, discord:value, overridingUsername: overriding);
        break;
      case SocialType.Kik:
      // return SocialIcon.kikIconButton.socialIcon;
      default:
        return null;
    }
  }

  isAdded(String key) async {
    switch (this) {
      case SocialType.Snapchat:
        return StorageUtils.get(key, reload: false, snapAdded:true);
      case SocialType.Instagram:
        return StorageUtils.get(key, reload: false, instaAdded:true);
      case SocialType.Discord:
        return StorageUtils.get(key, reload: false, discordAdded:true);
      case SocialType.Kik:
      // return SocialIcon.kikIconButton.socialIcon;
      default:
        return null;
    }
  }

  String? userNameSubkey(){
    switch (this) {
      case SocialType.Snapchat:
        return SubKeys.SnapUsername;
      case SocialType.Instagram:
        return SubKeys.InstaUsername;
      case SocialType.Discord:
        return SubKeys.DiscordUsername;
      case SocialType.Kik:
      // return SocialIcon.kikIconButton.socialIcon;
      default:
        return null;
    }
  }
}