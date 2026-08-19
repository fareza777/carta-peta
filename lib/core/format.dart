import 'geo.dart';

/// "6°12'54\"S  106°49'01\"E"
String formatDms(LatLng p, {bool compact = false}) {
  final lat = _dms(p.lat.abs(), compact);
  final lon = _dms(p.lon.abs(), compact);
  final ns = p.lat >= 0 ? 'N' : 'S';
  final ew = p.lon >= 0 ? 'E' : 'W';
  return '$lat$ns   $lon$ew';
}

String _dms(double v, bool compact) {
  var deg = v.floor();
  final minutesFull = (v - deg) * 60;
  var min = minutesFull.floor();
  var sec = ((minutesFull - min) * 60).round();
  if (sec == 60) {
    sec = 0;
    min += 1;
  }
  if (min == 60) {
    min = 0;
    deg += 1;
  }
  final m = min.toString().padLeft(2, '0');
  if (compact) return '$deg°$m\' ';
  final s = sec.toString().padLeft(2, '0');
  return '$deg°$m\'$s" ';
}

/// "-6.2088, 106.8456"
String formatDecimal(LatLng p) =>
    '${p.lat.toStringAsFixed(4)}, ${p.lon.toStringAsFixed(4)}';

String formatRadius(double metres) =>
    metres >= 1000 ? '${(metres / 1000).toStringAsFixed(metres % 1000 == 0 ? 0 : 1)} km' : '${metres.round()} m';

String formatDistance(double metres) {
  if (metres >= 10000) return '${(metres / 1000).toStringAsFixed(0)} km';
  if (metres >= 1000) return '${(metres / 1000).toStringAsFixed(2)} km';
  return '${metres.round()} m';
}

const _months = [
  'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE',
  'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'
];

String formatPosterDate(DateTime d) => '${_months[d.month - 1]} ${d.year}';

String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}
