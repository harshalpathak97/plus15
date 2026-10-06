class AppConstants {
  static const String appName = 'Plus 15';

  /// White +15 logo mark; tint it with `Image.asset(color: ...)`.
  static const String logoMark = 'assets/icons/plus15_mark.png';
  static const double defaultWalkingSpeedKmh = 4.5;
  static const int animDurationMs = 300;

  static const String contactEmail = 'developer@harshalpathak.com';
  static const String privacyUrl = 'https://harshalpathak97.github.io/plus15/privacy.html';

  static double estimateWalkTimeMinutes(double distanceM,
      {double speedKmh = defaultWalkingSpeedKmh}) {
    return (distanceM / 1000) / speedKmh * 60;
  }
}
