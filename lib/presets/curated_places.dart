import '../core/geo.dart';
import '../model/place.dart';

/// A hand-picked starting grid so the first screen is never empty.
const List<PlaceRef> kCuratedPlaces = [
  PlaceRef(
      name: 'Jakarta',
      context: 'DKI Jakarta, Indonesia',
      country: 'Indonesia',
      centre: LatLng(-6.1944, 106.8229)),
  PlaceRef(
      name: 'Bandung',
      context: 'West Java, Indonesia',
      country: 'Indonesia',
      centre: LatLng(-6.9175, 107.6191)),
  PlaceRef(
      name: 'Yogyakarta',
      context: 'Special Region, Indonesia',
      country: 'Indonesia',
      centre: LatLng(-7.7956, 110.3695)),
  PlaceRef(
      name: 'Ubud',
      context: 'Bali, Indonesia',
      country: 'Indonesia',
      centre: LatLng(-8.5069, 115.2625)),
  PlaceRef(
      name: 'Singapore',
      context: 'Singapore',
      country: 'Singapore',
      centre: LatLng(1.2897, 103.8501)),
  PlaceRef(
      name: 'Tokyo',
      context: 'Kanto, Japan',
      country: 'Japan',
      centre: LatLng(35.6812, 139.7671)),
  PlaceRef(
      name: 'Kyoto',
      context: 'Kansai, Japan',
      country: 'Japan',
      centre: LatLng(35.0116, 135.7681)),
  PlaceRef(
      name: 'Paris',
      context: 'Ile-de-France, France',
      country: 'France',
      centre: LatLng(48.8566, 2.3522)),
  PlaceRef(
      name: 'London',
      context: 'England, United Kingdom',
      country: 'United Kingdom',
      centre: LatLng(51.5074, -0.1278)),
  PlaceRef(
      name: 'New York',
      context: 'New York, United States',
      country: 'United States',
      centre: LatLng(40.7580, -73.9855)),
  PlaceRef(
      name: 'Barcelona',
      context: 'Catalonia, Spain',
      country: 'Spain',
      centre: LatLng(41.3874, 2.1686)),
  PlaceRef(
      name: 'Amsterdam',
      context: 'North Holland, Netherlands',
      country: 'Netherlands',
      centre: LatLng(52.3676, 4.9041)),
  PlaceRef(
      name: 'Venice',
      context: 'Veneto, Italy',
      country: 'Italy',
      centre: LatLng(45.4408, 12.3155)),
  PlaceRef(
      name: 'Istanbul',
      context: 'Marmara, Turkiye',
      country: 'Turkiye',
      centre: LatLng(41.0082, 28.9784)),
  PlaceRef(
      name: 'Sydney',
      context: 'New South Wales, Australia',
      country: 'Australia',
      centre: LatLng(-33.8688, 151.2093)),
  PlaceRef(
      name: 'San Francisco',
      context: 'California, United States',
      country: 'United States',
      centre: LatLng(37.7749, -122.4194)),
];
