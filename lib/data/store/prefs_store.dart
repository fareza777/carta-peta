import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../model/place.dart';

enum SavedSpot { home, work }

/// Lightweight preferences: recent searches and last-used studio settings.
class PrefsStore {
  static const _kRecent = 'recent_places';
  static const _kStyle = 'last_style';
  static const _kFormat = 'last_format';
  static const _kLang = 'language';
  static const _kOnboarded = 'onboarded_v1';
  static const _kHome = 'place_home';
  static const _kWork = 'place_work';

  Future<SharedPreferences> get _p => SharedPreferences.getInstance();

  Future<List<PlaceRef>> recentPlaces() async {
    final raw = (await _p).getStringList(_kRecent) ?? const [];
    final out = <PlaceRef>[];
    for (final s in raw) {
      try {
        out.add(PlaceRef.fromJson(Map<String, dynamic>.from(jsonDecode(s) as Map)));
      } catch (_) {
        // ignore malformed
      }
    }
    return out;
  }

  Future<void> pushRecent(PlaceRef place) async {
    final p = await _p;
    final current = await recentPlaces();
    current.removeWhere((e) =>
        e.name == place.name &&
        (e.centre.lat - place.centre.lat).abs() < 0.0005 &&
        (e.centre.lon - place.centre.lon).abs() < 0.0005);
    current.insert(0, place);
    final trimmed = current.take(12).map((e) => jsonEncode(e.toJson())).toList();
    await p.setStringList(_kRecent, trimmed);
  }

  Future<String?> lastStyleId() async => (await _p).getString(_kStyle);
  Future<void> setLastStyleId(String id) async => (await _p).setString(_kStyle, id);

  Future<String?> lastFormatId() async => (await _p).getString(_kFormat);
  Future<void> setLastFormatId(String id) async => (await _p).setString(_kFormat, id);

  Future<String?> languageCode() async => (await _p).getString(_kLang);
  Future<void> setLanguageCode(String code) async => (await _p).setString(_kLang, code);

  /// The two places a commute poster is made of. Stored so "home to work" is
  /// two taps the second time.
  Future<PlaceRef?> savedPlace(SavedSpot spot) async {
    final raw = (await _p).getString(spot == SavedSpot.home ? _kHome : _kWork);
    if (raw == null) return null;
    try {
      return PlaceRef.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } on FormatException {
      return null;
    }
  }

  Future<void> setSavedPlace(SavedSpot spot, PlaceRef place) async =>
      (await _p).setString(
          spot == SavedSpot.home ? _kHome : _kWork, jsonEncode(place.toJson()));

  Future<bool> hasOnboarded() async => (await _p).getBool(_kOnboarded) ?? false;
  Future<void> setOnboarded() async => (await _p).setBool(_kOnboarded, true);
}
