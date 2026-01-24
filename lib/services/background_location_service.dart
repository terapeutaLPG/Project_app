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

  factory BackgroundLocationService() {
    return _instance;
  }

  BackgroundLocationService._internal();

  Future<void> startBackgroundTracking() async {
    if (_positionStreamSubscription != null) return;

    final placeService = PlaceService();
    final result = await placeService.fetchPlacesOrFallback();
    _places = result.places;
    _claimedPlaceIds = !result.usedFallback
        ? await placeService.getClaimedPlaceIds()
        : {};

    const locationSettings = geo.LocationSettings(
      accuracy: geo.LocationAccuracy.high,
      distanceFilter: 10,
    );

    _positionStreamSubscription = geo.Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((geo.Position position) {
      _checkBackgroundProximity(position);
    });
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
  }

  void dispose() {
    stopBackgroundTracking();
  }
}
