import 'package:PhotoWordFind/models/contactEntry.dart';
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

  Future<String?> getUserName(ContactEntry? entry) async{
    switch (this) {
      case SocialType.Snapchat:
        return entry?.snapUsername;
      case SocialType.Instagram:
        return entry?.instaUsername;
      case SocialType.Discord:
        return entry?.discordUsername;
      case SocialType.Kik:
      // return SocialIcon.kikIconButton.socialIcon;
      default:
        return null;
    }
  }

  saveUsername(ContactEntry entry, String value, {required bool overriding}) async {
    switch (this) {
      case SocialType.Snapchat:
        entry.snapUsername = value;
        break;
      case SocialType.Instagram:
        entry.instaUsername = value;
        break;
      case SocialType.Discord:
        entry.discordUsername = value;
        break;
      case SocialType.Kik:
      // return SocialIcon.kikIconButton.socialIcon;
      default:
        return null;
    }
  }

  Future<bool> isAdded(ContactEntry? entry) async {
    if (entry == null) return false;
    switch (this) {
      case SocialType.Snapchat:
        return entry.addedOnSnap;
      case SocialType.Instagram:
        return entry.addedOnInsta;
      case SocialType.Discord:
        return entry.addedOnDiscord;
      case SocialType.Kik:
      // return SocialIcon.kikIconButton.socialIcon;
      default:
        return false;
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