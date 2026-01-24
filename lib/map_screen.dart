import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'services/tile_service.dart';
import 'services/place_service.dart';
import 'services/proximity_service.dart';
import 'models/tile_model.dart';
import 'models/tile_calculator.dart';
import 'models/place.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _PointTapListener implements OnPointAnnotationClickListener {
  final bool Function(PointAnnotation) handler;
  _PointTapListener(this.handler);

  @override
  bool onPointAnnotationClick(PointAnnotation annotation) => handler(annotation);
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  MapboxMap? mapboxMap;
  bool _locationPermissionGranted = false;
  final TileService _tileService = TileService();
  final ProximityService _proximityService = ProximityService();
  PolygonAnnotationManager? _polygonManager;
  final Map<String, PolygonAnnotation> _tilePolygons = {};
  PointAnnotationManager? _placeManager;
  final List<PointAnnotation> _placeAnnotations = [];
  Set<String> _claimedPlaceIds = {};
  final Map<String, Place> _placesByAnnotationId = {};
  List<Place> _places = [];
  bool _usingFallback = false;
  StreamSubscription<geo.Position>? _positionStreamSubscription;
  String? _currentTileId;
  int _discoveredTilesCount = 0;
  geo.Position? _lastKnownPosition;
  String? _selectedPlaceId;
  bool _soundsEnabled = true;
  Timer? _proximityTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final token = dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';
    if (token.isNotEmpty) {
      MapboxOptions.setAccessToken(token);
    }
    _proximityService.initialize();
    _checkAndRequestLocationPermission();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _proximityTimer?.cancel();
    _proximityService.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPlaces();
    }
  }

  Future<void> _enableLocationTracking() async {
    if (mapboxMap == null || !_locationPermissionGranted) return;

    final location = await mapboxMap!.location;
    await location.updateSettings(LocationComponentSettings(
      enabled: true,
      puckBearingEnabled: true,
      pulsingEnabled: true,
    ));

    try {
      final position = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      
      _lastKnownPosition = position;
      await _processLocation(position.latitude, position.longitude);
      
      await mapboxMap!.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(position.longitude, position.latitude)),
          zoom: 16.0,
        ),
        MapAnimationOptions(duration: 1000),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Blad lokalizacji: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      
      try {
        final lastPosition = await geo.Geolocator.getLastKnownPosition();
        if (lastPosition != null) {
          _lastKnownPosition = lastPosition;
          await _processLocation(lastPosition.latitude, lastPosition.longitude);
          await mapboxMap!.flyTo(
            CameraOptions(
              center: Point(coordinates: Position(lastPosition.longitude, lastPosition.latitude)),
              zoom: 16.0,
            ),
            MapAnimationOptions(duration: 1000),
          );
        }
      } catch (_) {}
    }
    
    _startLocationStream();
  }

  void _startLocationStream() {
    const locationSettings = geo.LocationSettings(
      accuracy: geo.LocationAccuracy.high,
      distanceFilter: 5,
    );

    _positionStreamSubscription = geo.Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((geo.Position position) {
      _lastKnownPosition = position;
      _processLocation(position.latitude, position.longitude);
      _checkProximity(position);
      _updateProximitySignals(position);
      _checkAndStartPeriodicSound(position);
    });
  }

  void _checkAndStartPeriodicSound(geo.Position position) {
    Place? nearbyPlace;
    double nearbyDistance = double.infinity;

    for (final place in _places) {
      if (_claimedPlaceIds.contains(place.id)) continue;

      final distance = geo.Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        place.lat,
        place.lon,
      );

      if (distance <= 100 && distance < nearbyDistance) {
        nearbyDistance = distance;
        nearbyPlace = place;
      }
    }

    if (nearbyPlace != null) {
      _startPeriodicSound();
    } else {
      _stopPeriodicSound();
    }
  }

  void _startPeriodicSound() {
    if (_proximityTimer != null && _proximityTimer!.isActive) return;

    _proximityTimer = Timer.periodic(const Duration(minutes: 1), (timer) async {
      if (!_soundsEnabled || _lastKnownPosition == null) return;

      for (final place in _places) {
        if (_claimedPlaceIds.contains(place.id)) continue;

        final distance = geo.Geolocator.distanceBetween(
          _lastKnownPosition!.latitude,
          _lastKnownPosition!.longitude,
          place.lat,
          place.lon,
        );

        if (distance <= 100) {
          _proximityService.playProximitySound(
            AndroidSounds.notification,
            IosSounds.triTone,
          );
          break;
        }
      }
    });
  }

  void _stopPeriodicSound() {
    _proximityTimer?.cancel();
    _proximityTimer = null;
  }

  void _updateProximitySignals(geo.Position position) {
    if (_selectedPlaceId == null) return;

    final placeIndex = _places.indexWhere((p) => p.id == _selectedPlaceId);
    if (placeIndex == -1) return;

    final place = _places[placeIndex];
    final distance = geo.Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      place.lat,
      place.lon,
    );

    _proximityService.checkProximityAndTrigger(distance, _selectedPlaceId!);
  }

  void _checkProximity(geo.Position pos) {
    for (final place in _places) {
      if (_claimedPlaceIds.contains(place.id)) continue;
      final d = geo.Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        place.lat,
        place.lon,
      );
      if (d <= place.radiusMeters) {
        return;
      }
    }
  }

  Future<void> _processLocation(double lat, double lon) async {
    final tileId = TileCalculator.calculateTileId(lat, lon);
    
    if (_currentTileId == tileId) return;
    
    _currentTileId = tileId;
    
    final isDiscovered = await _tileService.isTileDiscovered(tileId);
    if (isDiscovered) return;
    
    await _tileService.saveTile(lat, lon);
    
    final tile = TileCalculator.getTileBounds(lat, lon);
    await _drawTileOnMap(tile);
  }

  Future<void> _checkAndRequestLocationPermission() async {
    bool serviceEnabled;
    geo.LocationPermission permission;

    serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Brak dostepu do lokalizacji'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
      if (permission == geo.LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Brak dostepu do lokalizacji'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }
    }

    if (permission == geo.LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Brak dostepu do lokalizacji'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    setState(() {
      _locationPermissionGranted = true;
    });

    _enableLocationTracking();
  }

  _onMapCreated(MapboxMap map) async {
    mapboxMap = map;
    
    _polygonManager = await map.annotations.createPolygonAnnotationManager();
    _placeManager = await map.annotations.createPointAnnotationManager();
    _placeManager?.addOnPointAnnotationClickListener(_PointTapListener(_onPlaceTapped));
    
    await _loadDiscoveredTiles();
    await _loadClaimedPlaces();
    await _refreshPlaces();
    
    if (_locationPermissionGranted) {
      _enableLocationTracking();
    }
  }

  Future<void> _loadDiscoveredTiles() async {
    if (_polygonManager == null) return;
    
    final tiles = await _tileService.getDiscoveredTiles();
    
    setState(() {
      _discoveredTilesCount = tiles.length;
    });
    
    for (var tile in tiles) {
      await _drawTileOnMap(tile);
    }
  }

  Future<void> _drawTileOnMap(TileModel tile) async {
    if (_polygonManager == null) return;
    if (_tilePolygons.containsKey(tile.tileId)) return;

    final points = [
      Point(coordinates: Position(tile.minLon, tile.minLat)),
      Point(coordinates: Position(tile.maxLon, tile.minLat)),
      Point(coordinates: Position(tile.maxLon, tile.maxLat)),
      Point(coordinates: Position(tile.minLon, tile.maxLat)),
      Point(coordinates: Position(tile.minLon, tile.minLat)),
    ];

    final polygonOptions = PolygonAnnotationOptions(
      geometry: Polygon(coordinates: [points.map((p) => p.coordinates).toList()]),
      fillColor: Colors.pink.withOpacity(0.3).value,
      fillOutlineColor: Colors.purple.value,
    );

    final polygon = await _polygonManager!.create(polygonOptions);
    _tilePolygons[tile.tileId] = polygon;
    
    setState(() {
      _discoveredTilesCount = _tilePolygons.length;
    });
  }

  Future<void> _loadClaimedPlaces() async {
    final placeService = PlaceService();
    final ids = await placeService.getClaimedPlaceIds();
    if (!mounted) return;
    setState(() {
      _claimedPlaceIds = ids;
    });
  }

  Future<void> _refreshPlaces({bool showCount = false}) async {
    if (!mounted) return;
    final placeService = PlaceService();
    final result = await placeService.fetchPlacesOrFallback();
    final places = result.places;
    _usingFallback = result.usedFallback;
    _places = places;
    if (!result.usedFallback) {
      _claimedPlaceIds = await placeService.getClaimedPlaceIds();
    } else {
      _claimedPlaceIds = {};
    }

    if (!mounted) return;
    if (_placeManager == null) return;

    if (_placeAnnotations.isNotEmpty) {
      for (final annotation in List<PointAnnotation>.from(_placeAnnotations)) {
        await _placeManager!.delete(annotation);
      }
      _placeAnnotations.clear();
    }
    _placesByAnnotationId.clear();

    if (result.usedFallback) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Brak miejsc do wyswietlenia'),
          duration: Duration(seconds: 2),
        ),
      );
    } else if (showCount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Zaladowano ${places.length} miejsc'),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    for (final place in places) {
      final claimed = _claimedPlaceIds.contains(place.id);
      final annotation = await _placeManager!.create(
        PointAnnotationOptions(
          geometry: Point(coordinates: Position(place.lon, place.lat)),
          textField: place.name,
          textSize: 10,
          textColor: claimed ? Colors.green.value : Colors.red.value,
          textOffset: [0.0, 2.0],
          iconImage: "marker-15",
          iconSize: 1.8,
          iconColor: claimed ? Colors.green.value : Colors.red.value,
          iconOpacity: 1.0,
        ),
      );
      _placeAnnotations.add(annotation);
      _placesByAnnotationId[annotation.id] = place;
    }

    _checkNearbyPlaces();
  }

  Future<void> _checkNearbyPlaces() async {
    if (_lastKnownPosition == null || _places.isEmpty) return;

    Place? nearestPlace;
    double nearestDistance = double.infinity;

    for (final place in _places) {
      if (_claimedPlaceIds.contains(place.id)) continue;

      final distance = geo.Geolocator.distanceBetween(
        _lastKnownPosition!.latitude,
        _lastKnownPosition!.longitude,
        place.lat,
        place.lon,
      );

      if (distance <= 300 && distance < nearestDistance) {
        nearestDistance = distance;
        nearestPlace = place;
      }
    }

    if (nearestPlace != null && mounted) {
      if (_soundsEnabled) {
        if (nearestDistance <= 100) {
          _proximityService.playProximitySound(AndroidSounds.notification, IosSounds.triTone);
        } else if (nearestDistance <= 200) {
          _proximityService.playProximitySound(AndroidSounds.alarm, IosSounds.glass);
        } else {
          _proximityService.playProximitySound(AndroidSounds.ringtone, IosSounds.electronic);
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Punkt w pobliżu: ${nearestPlace.name}\nOdległość: ${nearestDistance.toStringAsFixed(0)}m',
          ),
          duration: const Duration(seconds: 4),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  bool _onPlaceTapped(PointAnnotation annotation) {
    if (_usingFallback) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Brak danych o punktach'),
          duration: Duration(seconds: 2),
        ),
      );
      return true;
    }

    final place = _placesByAnnotationId[annotation.id];
    if (place == null) return true;
    
    _selectedPlaceId = place.id;
    _proximityService.setEnabled(_soundsEnabled);
    _proximityService.resetProximityState(place.id);
    
    final claimed = _claimedPlaceIds.contains(place.id);
    
    final pos = _lastKnownPosition;
    if (pos == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Brak bieżącej lokalizacji'),
          duration: Duration(seconds: 2),
        ),
      );
      return true;
    }

    final distance = geo.Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      place.lat,
      place.lon,
    );

    if (claimed) {
      showModalBottomSheet(
        context: context,
        builder: (ctx) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(place.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Text(
                  '✅ To miejsce zostało już odblokowane',
                  style: TextStyle(fontSize: 16, color: Colors.green.shade700),
                ),
              ],
            ),
          );
        },
      );
      return true;
    }

    if (distance > place.radiusMeters) {
      showModalBottomSheet(
        context: context,
        builder: (ctx) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(place.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Text(
                  '❌ Musisz podejść bliżej (${distance.toStringAsFixed(0)}m od miejsca)',
                  style: TextStyle(fontSize: 16, color: Colors.red.shade700),
                ),
              ],
            ),
          );
        },
      );
      return true;
    }

    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(place.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _claimPlace(place, annotation);
                },
                child: const Text('Odbierz'),
              ),
            ],
          ),
        );
      },
    );
    return true;
  }

  Future<void> _claimPlace(Place place, PointAnnotation annotation) async {
    final placeService = PlaceService();
    final ok = await placeService.claimPlace(place.id, place.points);
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nie udało się odebrać'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    _claimedPlaceIds.add(place.id);
    _selectedPlaceId = null;
    _proximityService.resetProximityStateForDistance();
    
    annotation.iconColor = Colors.green.value;
    annotation.textColor = Colors.green.value;
    await _placeManager?.update(annotation);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🎉 ${place.name} zostało odblokowane!'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final token = dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';

    if (token.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Mapa'),
        ),
        body: const Center(
          child: Text(
            'Brakuje MAPBOX_ACCESS_TOKEN w pliku .env',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Mapa'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.purple,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$_discoveredTilesCount',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _soundsEnabled ? Icons.volume_up : Icons.volume_off,
              color: _soundsEnabled ? Colors.green : Colors.red,
            ),
            onPressed: () {
              setState(() {
                _soundsEnabled = !_soundsEnabled;
                _proximityService.setEnabled(_soundsEnabled);
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _showClearMapDialog,
          ),
          if (_locationPermissionGranted)
            const Icon(Icons.location_on, color: Colors.green)
          else
            const Icon(Icons.location_off, color: Colors.red),
          const SizedBox(width: 16),
        ],
      ),
      body: Stack(
        children: [
          MapWidget(
            key: const ValueKey("mapWidget"),
            cameraOptions: CameraOptions(
              center: Point(coordinates: Position(17.0326, 51.1097)),
              zoom: 15.0,
            ),
            styleUri: MapboxStyles.DARK,
            onMapCreated: _onMapCreated,
          ),
          Positioned(
            top: 80,
            right: 16,
            child: FloatingActionButton(
              onPressed: _returnToMyLocation,
              backgroundColor: Colors.purple,
              child: const Icon(Icons.my_location, color: Colors.white),
            ),
          ),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () => _refreshPlaces(showCount: true),
                  child: const Text('Zaladuj miejsca'),
                ),
                const SizedBox(width: 10),
                if (kDebugMode)
                  ElevatedButton(
                    onPressed: _seedPlaces,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                    ),
                    child: const Text('Seed miejsc'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _returnToMyLocation() async {
    if (mapboxMap == null) return;

    if (_lastKnownPosition != null) {
      await mapboxMap!.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(
            _lastKnownPosition!.longitude,
            _lastKnownPosition!.latitude,
          )),
          zoom: 16.0,
        ),
        MapAnimationOptions(duration: 1000),
      );
    } else {
      try {
        final position = await geo.Geolocator.getCurrentPosition(
          locationSettings: const geo.LocationSettings(
            accuracy: geo.LocationAccuracy.high,
            timeLimit: Duration(seconds: 5),
          ),
        );
        _lastKnownPosition = position;
        await mapboxMap!.flyTo(
          CameraOptions(
            center: Point(coordinates: Position(
              position.longitude,
              position.latitude,
            )),
            zoom: 16.0,
          ),
          MapAnimationOptions(duration: 1000),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Nie można pobrać lokalizacji'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  void _showClearMapDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Wyczysc mape'),
        content: const Text('Czy na pewno chcesz usunac wszystkie odkryte kratki?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anuluj'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _clearMap();
            },
            child: const Text('Usun', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _clearMap() async {
    await _tileService.clearAllTiles();
    
    if (_polygonManager != null) {
      for (var polygon in _tilePolygons.values) {
        await _polygonManager!.delete(polygon);
      }
    }
    
    setState(() {
      _tilePolygons.clear();
      _discoveredTilesCount = 0;
      _currentTileId = null;
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mapa wyczyszczona'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _seedPlaces() async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Miejsca są już załadowane z Firestore'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}
