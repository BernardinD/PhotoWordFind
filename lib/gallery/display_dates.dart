import 'package:PhotoWordFind/constants/constants.dart';
import 'package:PhotoWordFind/social_icons.dart';

Map<SocialType?, int> enumPriorities = {
  SocialType.Snapchat: 0,
  SocialType.Instagram: 1,
  SocialType.Discord: 2,
  null: 3,
};

snapchatDisplayDate(DateTime date){
  return "Snapchat Added on: \n ${dateFormat.format(date)}";
}
instagramDisplayDate(DateTime date){
  return "Instagram Added on: \n ${dateFormat.format(date)}";
}
discordDisplayDate(DateTime date){
  return "Discord Added on: \n ${dateFormat.format(date)}";
}
