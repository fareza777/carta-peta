import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ad_config.dart';

/// Owns every ad in the app.
///
/// Two rules shape it. Nothing an ad network does may break the app: every
/// call is guarded and a failure is a silent no-op, never an exception that
/// reaches the user. And nothing the user paid attention to is interrupted:
/// the interstitial waits for an export to finish, skips the first few, and
/// stays quiet for minutes afterwards.
class AdService {
  AdService();

  final Completer<bool> _initialised = Completer<bool>();
  bool _ready = false;
  bool _consentDone = false;
  bool _adsRemoved = false;
  int _exportCount = 0;
  DateTime _lastInterstitial = DateTime.fromMillisecondsSinceEpoch(0);

  InterstitialAd? _interstitial;
  bool _loadingInterstitial = false;

  RewardedAd? _rewarded;
  bool _loadingRewarded = false;

  bool get isReady => _ready;
  bool get adsRemoved => _adsRemoved;

  /// Completes with whether ads are usable at all. Widgets await this instead
  /// of sampling [isReady], which would race the background initialise.
  Future<bool> get whenReady => _initialised.future;

  /// True once the user has watched a rewarded ad this session. Deliberately
  /// not persisted: the reward is a session unlock, not a purchase.
  bool bigExportsUnlocked = false;

  Future<void> initialize() async {
    if (_initialised.isCompleted) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _adsRemoved = prefs.getBool('carta_remove_ads_v1') ?? false;
    } on Exception catch (e) {
      debugPrint('AdService: purchase state read failed: $e');
    }
    if (_adsRemoved) {
      _initialised.complete(false);
      return;
    }
    if (!AdConfig.supported) {
      _initialised.complete(false);
      return;
    }
    try {
      await MobileAds.instance.initialize();
      _ready = true;
      _initialised.complete(true);
      unawaited(_gatherConsent());
      preloadInterstitial();
    } on Exception catch (e) {
      debugPrint('AdService: initialise failed: $e');
      if (!_initialised.isCompleted) _initialised.complete(false);
    }
  }

  /// Called by the purchase stream after Google Play grants the entitlement.
  /// Loaded ads are disposed immediately so one cannot appear after checkout.
  Future<void> setAdsRemoved() async {
    _adsRemoved = true;
    _interstitial?.dispose();
    _rewarded?.dispose();
    _interstitial = null;
    _rewarded = null;
    if (!_initialised.isCompleted) _initialised.complete(false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('carta_remove_ads_v1', true);
    } on Exception catch (e) {
      debugPrint('AdService: purchase state write failed: $e');
    }
  }

  /// Google's User Messaging Platform: required before serving personalised
  /// ads in the EEA and the UK. Outside those regions it resolves to "no form
  /// needed" and costs one cheap call.
  Future<void> _gatherConsent() async {
    if (_consentDone) return;
    _consentDone = true;
    final done = Completer<void>();
    try {
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () async {
          try {
            await ConsentForm.loadAndShowConsentFormIfRequired((error) {
              if (error != null) {
                debugPrint('AdService: consent form: ${error.message}');
              }
              if (!done.isCompleted) done.complete();
            });
          } on Exception catch (e) {
            debugPrint('AdService: consent form failed: $e');
            if (!done.isCompleted) done.complete();
          }
        },
        (error) {
          debugPrint('AdService: consent update failed: ${error.message}');
          if (!done.isCompleted) done.complete();
        },
      );
    } on Exception catch (e) {
      debugPrint('AdService: consent failed: $e');
      if (!done.isCompleted) done.complete();
    }
    return done.future.timeout(const Duration(seconds: 20), onTimeout: () {});
  }

  // ----------------------------------------------------------- interstitial

  void preloadInterstitial() {
    if (_adsRemoved ||
        !_ready ||
        _interstitial != null ||
        _loadingInterstitial) {
      return;
    }
    _loadingInterstitial = true;
    InterstitialAd.load(
      adUnitId: AdConfig.interstitialUnit,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingInterstitial = false;
          _interstitial = ad;
        },
        onAdFailedToLoad: (error) {
          _loadingInterstitial = false;
          _interstitial = null;
          debugPrint('AdService: interstitial failed: ${error.message}');
        },
      ),
    );
  }

  /// Called when an export finishes. Returns true if an ad was shown.
  Future<bool> onExportFinished() async {
    if (_adsRemoved || !_ready) return false;
    _exportCount++;
    if (_exportCount < AdConfig.exportsBeforeInterstitial) {
      preloadInterstitial();
      return false;
    }
    if (DateTime.now().difference(_lastInterstitial) <
        AdConfig.interstitialCooldown) {
      return false;
    }
    final ad = _interstitial;
    if (ad == null) {
      preloadInterstitial();
      return false;
    }

    _interstitial = null;
    _exportCount = 0;
    _lastInterstitial = DateTime.now();
    final shown = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        preloadInterstitial();
        if (!shown.isCompleted) shown.complete(true);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        preloadInterstitial();
        debugPrint('AdService: interstitial show failed: ${error.message}');
        if (!shown.isCompleted) shown.complete(false);
      },
    );
    try {
      await ad.show();
    } on Exception catch (e) {
      debugPrint('AdService: interstitial show threw: $e');
      if (!shown.isCompleted) shown.complete(false);
    }
    return shown.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () => false,
    );
  }

  // --------------------------------------------------------------- rewarded

  void preloadRewarded() {
    if (_adsRemoved || !_ready || _rewarded != null || _loadingRewarded) return;
    _loadingRewarded = true;
    RewardedAd.load(
      adUnitId: AdConfig.rewardedUnit,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingRewarded = false;
          _rewarded = ad;
        },
        onAdFailedToLoad: (error) {
          _loadingRewarded = false;
          _rewarded = null;
          debugPrint('AdService: rewarded failed: ${error.message}');
        },
      ),
    );
  }

  bool get rewardedReady => _rewarded != null;

  /// Shows a rewarded ad. Returns true only when the user actually earned the
  /// reward, so a dismissed ad unlocks nothing.
  Future<bool> showRewarded() async {
    if (_adsRemoved || !_ready) return false;
    final ad = _rewarded;
    if (ad == null) {
      preloadRewarded();
      return false;
    }
    _rewarded = null;

    var earned = false;
    final finished = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        preloadRewarded();
        if (!finished.isCompleted) finished.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        preloadRewarded();
        debugPrint('AdService: rewarded show failed: ${error.message}');
        if (!finished.isCompleted) finished.complete(false);
      },
    );
    try {
      await ad.show(onUserEarnedReward: (_, __) => earned = true);
    } on Exception catch (e) {
      debugPrint('AdService: rewarded show threw: $e');
      if (!finished.isCompleted) finished.complete(false);
    }
    final result = await finished.future.timeout(
      const Duration(minutes: 4),
      onTimeout: () => false,
    );
    if (result) bigExportsUnlocked = true;
    return result;
  }

  void dispose() {
    _interstitial?.dispose();
    _rewarded?.dispose();
    _interstitial = null;
    _rewarded = null;
  }
}
