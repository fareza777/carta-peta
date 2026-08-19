import 'dart:async';

import 'package:http/http.dart' as http;

/// Fetches raw Overpass JSON, rotating through mirrors when one is busy.
class OverpassClient {
  OverpassClient({http.Client? client}) : _client = client ?? http.Client();

  static const List<String> endpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
    'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
  ];

  static const _userAgent = 'CARTA-MapArtStudio/1.0 (Android; contact via app store listing)';

  final http.Client _client;

  /// Returns the response body, or throws [OverpassFailure].
  Future<String> fetch(
    String query, {
    Duration timeout = const Duration(seconds: 75),
    void Function(String status)? onStatus,
  }) async {
    Object? lastError;
    for (var i = 0; i < endpoints.length; i++) {
      final url = endpoints[i];
      try {
        onStatus?.call(i == 0
            ? 'Contacting OpenStreetMap...'
            : 'Mirror ${i + 1} of ${endpoints.length}...');
        final res = await _client
            .post(
              Uri.parse(url),
              headers: const {
                'User-Agent': _userAgent,
                'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
              },
              body: 'data=${Uri.encodeQueryComponent(query)}',
            )
            .timeout(timeout);
        if (res.statusCode == 200) {
          final body = res.body;
          if (body.trimLeft().startsWith('{')) return body;
          // Overpass answers 200 with an HTML page when a mirror is overloaded
          // or the query hit a runtime limit.
          lastError = OverpassFailure(_readableError(body));
          continue;
        }
        if (res.statusCode == 429 || res.statusCode == 504) {
          lastError = OverpassFailure('Server busy, trying another mirror');
          continue;
        }
        lastError = OverpassFailure('Map server error ${res.statusCode}');
      } on TimeoutException {
        lastError = OverpassFailure('Timed out. Try a smaller area.');
      } catch (e) {
        lastError = OverpassFailure('Network problem: $e');
      }
    }
    throw lastError is OverpassFailure
        ? lastError
        : OverpassFailure('Could not reach any OpenStreetMap server.');
  }

  /// Turns an Overpass HTML error page into something worth showing a user.
  static String _readableError(String html) {
    final match = RegExp(r'Error</strong>:(.*?)</p>', dotAll: true).firstMatch(html);
    final raw = match?.group(1)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '';
    if (raw.contains('too busy') || raw.contains('timeout')) {
      return 'The OpenStreetMap servers are busy. Try again in a moment, or '
          'pick a smaller area.';
    }
    if (raw.contains('memory')) {
      return 'That area is too large for one request. Try a smaller radius.';
    }
    return raw.isEmpty ? 'Unexpected response from the map server.' : raw;
  }

  void close() => _client.close();
}

class OverpassFailure implements Exception {
  final String message;
  OverpassFailure(this.message);
  @override
  String toString() => message;
}
