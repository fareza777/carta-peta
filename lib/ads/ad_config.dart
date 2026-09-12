import 'dart:io';

/// Where the ad unit ids come from.
///
/// The defaults are Google's own public test units. Real units are supplied at
/// build time with `--dart-define`, so no account-specific id is committed and
/// a development build can never serve real ads to its own developer — that is
/// what gets an AdMob account suspended.
///
///   flutter build appbundle \
///     --dart-define=CARTA_BANNER_UNIT=ca-app-pub-.../... \
///     --dart-define=CARTA_INTERSTITIAL_UNIT=ca-app-pub-.../... \
///     --dart-define=CARTA_REWARDED_UNIT=ca-app-pub-.../...
///
/// The matching application id goes in the Android manifest, via
/// `-PadmobAppId=` (see android/app/build.gradle.kts).
class AdConfig {
  const AdConfig._();

  static const _testBannerAndroid = 'ca-app-pub-3940256099942544/6300978111';
  static const _testBannerIos = 'ca-app-pub-3940256099942544/2934735716';
  static const _testInterstitialAndroid = 'ca-app-pub-3940256099942544/1033173712';
  static const _testInterstitialIos = 'ca-app-pub-3940256099942544/4411468910';
  static const _testRewardedAndroid = 'ca-app-pub-3940256099942544/5224354917';
  static const _testRewardedIos = 'ca-app-pub-3940256099942544/1712485313';

  static const _banner = String.fromEnvironment('CARTA_BANNER_UNIT');
  static const _interstitial = String.fromEnvironment('CARTA_INTERSTITIAL_UNIT');
  static const _rewarded = String.fromEnvironment('CARTA_REWARDED_UNIT');

  /// True once real unit ids have been supplied at build time.
  static bool get isLive => _banner.isNotEmpty || _interstitial.isNotEmpty;

  static bool get _android => Platform.isAndroid;

  static String get bannerUnit => _banner.isNotEmpty
      ? _banner
      : (_android ? _testBannerAndroid : _testBannerIos);

  static String get interstitialUnit => _interstitial.isNotEmpty
      ? _interstitial
      : (_android ? _testInterstitialAndroid : _testInterstitialIos);

  static String get rewardedUnit => _rewarded.isNotEmpty
      ? _rewarded
      : (_android ? _testRewardedAndroid : _testRewardedIos);

  /// Ads are only a thing on the two mobile platforms; on desktop the plugin
  /// is not even there.
  static bool get supported => Platform.isAndroid || Platform.isIOS;

  // ------------------------------------------------------------- behaviour

  /// An interstitial is shown after an export, but never on the first one and
  /// never twice in quick succession: an ad that interrupts the moment someone
  /// is admiring their artwork is the fastest way to lose them.
  static const int exportsBeforeInterstitial = 3;
  static const Duration interstitialCooldown = Duration(minutes: 4);

  /// Resolutions above this are the reward. Everything at or below it is free,
  /// so the app is fully usable without ever watching an ad.
  static const int freeExportWidth = 4096;
}
