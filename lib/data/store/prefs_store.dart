import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../model/place.dart';

/// Lightweight preferences: recent searches and last-used studio settings.
class PrefsStore {
  static const _kRecent = 'recent_places';
  static const _kStyle = 'last_style';
  static const _kFormat = 'last_format';

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
}
