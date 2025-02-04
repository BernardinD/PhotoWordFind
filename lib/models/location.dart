import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class Location {
  final String rawLocation;
  final String? timezone;
  final int? UTCOffset;

  /// 🌍 **Constructor uses extracted data (everything is ready immediately)**
  Location({
    required this.rawLocation,
    required this.timezone,
  }) : UTCOffset = timezone != null ? tz.getLocation(timezone).currentTimeZone.offset : null; // ✅ Get time zone synchronously!


  @override
  String toString() {
    return "$rawLocation ($timezone [$UTCOffset])";
  }
}
