import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ads/ad_banner.dart';
import '../core/strings.dart';
import '../data/map_repository.dart';
import '../data/osm/nominatim_client.dart';
import '../data/routing/osrm_client.dart';
import '../data/store/design_store.dart';
import '../data/store/prefs_store.dart';
import '../purchases/purchase_service.dart';

final mapRepositoryProvider = Provider<MapRepository>((ref) {
  final repo = MapRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

final nominatimProvider = Provider<NominatimClient>((ref) {
  final client = NominatimClient();
  ref.onDispose(client.close);
  return client;
});

final routingProvider = Provider<OsrmClient>((ref) {
  final client = OsrmClient();
  ref.onDispose(client.close);
  return client;
});

final designStoreProvider = Provider<DesignStore>((_) => DesignStore());

final prefsStoreProvider = Provider<PrefsStore>((_) => PrefsStore());

/// One-time Google Play entitlement. It shares the ad service's persisted
/// state so an ad never flashes while the billing stream is restoring.
final purchaseServiceProvider = ChangeNotifierProvider<PurchaseService>((ref) {
  final service = PurchaseService(
    onAdsRemoved: () => ref.read(adServiceProvider).setAdsRemoved(),
  );
  unawaited(service.initialize());
  ref.onDispose(service.dispose);
  return service;
});

/// App language, remembered between launches.
class LanguageController extends StateNotifier<AppLanguage> {
  LanguageController(this._prefs) : super(AppLanguage.english) {
    _restore();
  }

  final PrefsStore _prefs;

  Future<void> _restore() async {
    final code = await _prefs.languageCode();
    if (mounted && code != null) state = languageFromCode(code);
  }

  Future<void> set(AppLanguage language) async {
    state = language;
    await _prefs.setLanguageCode(language.code);
  }
}

final languageProvider = StateNotifierProvider<LanguageController, AppLanguage>(
  (ref) => LanguageController(ref.watch(prefsStoreProvider)),
);

/// Localised strings for the active language.
final stringsProvider = Provider<S>((ref) => S(ref.watch(languageProvider)));
