class AppConstants {
  static const String appName = 'Plus 15';

  /// White +15 logo mark; tint it with `Image.asset(color: ...)`.
  static const String logoMark = 'assets/icons/plus15_mark.png';
  static const double defaultWalkingSpeedKmh = 4.5;
  static const double mapMinScale = 0.3;
  static const double mapMaxScale = 4.0;
  static const double mapDefaultScale = 0.6;
  static const int animDurationMs = 300;

  static const Map<String, Map<String, String>> operatingHours = {
    'weekday': {'open': '06:00', 'close': '21:00'},
    'weekend': {'open': '09:00', 'close': '19:00'},
  };

  static double estimateWalkTimeMinutes(double distanceM,
      {double speedKmh = defaultWalkingSpeedKmh}) {
    return (distanceM / 1000) / speedKmh * 60;
  }
}
