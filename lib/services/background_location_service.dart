import 'dart:async';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'place_service.dart';
import '../models/place.dart';

class BackgroundLocationService {
  static final BackgroundLocationService _instance = BackgroundLocationService._internal();
  StreamSubscription<geo.Position>? _positionStreamSubscription;
  List<Place> _places = [];
  Set<String> _claimedPlaceIds = {};
  Timer? _refreshTimer;

  factory BackgroundLocationService() {
    return _instance;
  }

  BackgroundLocationService._internal();

  Future<void> startBackgroundTracking() async {
    if (_positionStreamSubscription != null) return;

    await _refreshPlaces();

    const locationSettings = geo.LocationSettings(
      accuracy: geo.LocationAccuracy.high,
      distanceFilter: 5,
    );

    _positionStreamSubscription = geo.Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((geo.Position position) {
      _checkBackgroundProximity(position);
    });

    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      await _refreshPlaces();
    });
  }

  Future<void> _refreshPlaces() async {
    try {
      final placeService = PlaceService();
      final result = await placeService.fetchPlacesOrFallback();
      _places = result.places;
      _claimedPlaceIds = !result.usedFallback
          ? await placeService.getClaimedPlaceIds()
          : {};
    } catch (e) {
      print('Error refreshing places: $e');
    }
  }

  void _checkBackgroundProximity(geo.Position position) {
    for (final place in _places) {
      if (_claimedPlaceIds.contains(place.id)) continue;

      final distance = geo.Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        place.lat,
        place.lon,
      );

      if (distance <= 100) {
        FlutterRingtonePlayer().play(
          android: AndroidSounds.notification,
          ios: IosSounds.triTone,
          looping: false,
          volume: 1.0,
        );
        break;
      }
    }
  }

  void stopBackgroundTracking() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  void dispose() {
    stopBackgroundTracking();
  }
}
