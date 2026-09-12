/// One place for everything that points outside the app: the store listing,
/// the privacy policy, support. Nothing here is a secret, and nothing else in
/// the code should hard-code a URL.
class AppLinks {
  const AppLinks._();

  static const String appName = 'CARTA';
  static const String tagline = 'Map Art Studio';
  static const String version = '1.4.0';
  static const String packageId = 'studio.carta.mapart';

  static const String playListing =
      'https://play.google.com/store/apps/details?id=$packageId';

  /// Opens the installed Play Store straight on the listing. Falls back to
  /// [playListing] in a browser when the store app is not there.
  static const String playMarket = 'market://details?id=$packageId';

  /// Required by Google Play for any app that shows ads. Replace with the
  /// real page before publishing; it is deliberately one constant.
  static const String privacyPolicy = 'https://carta.studio/privacy';

  static const String supportEmail = 'support@carta.studio';

  static const String osmCopyright = 'https://www.openstreetmap.org/copyright';

  static String shareMessage() =>
      'I made this with $appName, a map poster studio for Android. $playListing';
}
