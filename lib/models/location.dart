import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:mobx/mobx.dart';
import 'dart:convert';
import 'package:json_annotation/json_annotation.dart';

part 'location.g.dart';

@JsonSerializable()
class Location = _Location with _$Location;

abstract class _Location with Store {
  @observable
  String? rawLocation;

  @observable
  String? timezone;

  @observable
  int? utcOffset;

  _Location({
    required this.rawLocation,
    required this.timezone,
  }) : utcOffset = timezone != null
            ? tz.getLocation(timezone).currentTimeZone.offset
            : null;

  Map<String, dynamic> toJson() {
    return {
      "name": rawLocation,
      "timezone": timezone,
      "utc-offset": utcOffset,
    };
  }

  factory _Location.fromJson(Map<String, dynamic> json) {
    return Location(
      rawLocation: json["name"] ?? "",
      timezone: json["timezone"] as String?,
    );
  }
}
