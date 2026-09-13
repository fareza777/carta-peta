import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/theme.dart';
import 'ad_config.dart';
import 'ad_service.dart';

final adServiceProvider = Provider<AdService>((ref) {
  final service = AdService();
  ref.onDispose(service.dispose);
  return service;
});

/// An anchored adaptive banner. It occupies no space at all until an ad has
/// actually loaded, so a failed or unsupported load leaves the layout exactly
/// as it was rather than a grey hole.
class AdBanner extends ConsumerStatefulWidget {
  const AdBanner({super.key});

  @override
  ConsumerState<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends ConsumerState<AdBanner> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    if (!AdConfig.supported) return;
    if (ref.read(adServiceProvider).adsRemoved) return;
    final width = MediaQuery.of(context).size.width.truncate();
    // Initialising the ads SDK happens in the background at launch, so the
    // banner waits for it rather than sampling a flag that is not set yet.
    if (!await ref.read(adServiceProvider).whenReady) return;
    if (!mounted) return;
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (size == null || !mounted) return;

    final ad = BannerAd(
      size: size,
      adUnitId: AdConfig.bannerUnit,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted) setState(() => _ad = null);
        },
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null || !_loaded) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      height: ad.size.height.toDouble(),
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Shade.bgAlt,
        border: Border(top: BorderSide(color: Shade.line)),
      ),
      child: SizedBox(
        width: ad.size.width.toDouble(),
        height: ad.size.height.toDouble(),
        child: AdWidget(ad: ad),
      ),
    );
  }
}
