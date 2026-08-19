import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/map_repository.dart';
import '../data/osm/nominatim_client.dart';
import '../data/store/design_store.dart';
import '../data/store/prefs_store.dart';

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

final designStoreProvider = Provider<DesignStore>((_) => DesignStore());

final prefsStoreProvider = Provider<PrefsStore>((_) => PrefsStore());
