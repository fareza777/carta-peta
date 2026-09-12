import 'package:geolocator/geolocator.dart';

import '../core/format.dart';
import '../core/geo.dart';
import '../model/place.dart';
import 'osm/nominatim_client.dart';

enum LocationOutcome { ok, denied, unavailable }

class LocatedPlace {
  const LocatedPlace(this.outcome, [this.place]);
  final LocationOutcome outcome;
  final PlaceRef? place;
}

/// Finds where the device is and gives that point a name.
///
/// The outcome is returned rather than thrown so each caller can word the
/// refusal in its own voice; a denied permission is a normal answer, not an
/// error.
Future<LocatedPlace> locateDevice(
  NominatimClient places, {
  String fallbackName = 'My location',
}) async {
  try {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return const LocatedPlace(LocationOutcome.denied);
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
    );
    final here = LatLng(position.latitude, position.longitude);
    final resolved = await places.reverse(here);
    return LocatedPlace(
      LocationOutcome.ok,
      PlaceRef(
        name: resolved?.name.isNotEmpty == true ? resolved!.name : fallbackName,
        context: resolved?.context ?? formatDecimal(here),
        country: resolved?.country ?? '',
        // Always the measured point: the reverse lookup names the area, it
        // does not improve on the fix.
        centre: here,
      ),
    );
  } on Exception {
    return const LocatedPlace(LocationOutcome.unavailable);
  }
}
