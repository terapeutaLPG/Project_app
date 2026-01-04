import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'services/tile_service.dart';
import 'models/tile_model.dart';
import 'models/tile_calculator.dart';
import 'dart:async';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  MapboxMap? mapboxMap;
  bool _locationPermissionGranted = false;
  final TileService _tileService = TileService();
  PolygonAnnotationManager? _polygonManager;
  final Map<String, PolygonAnnotation> _tilePolygons = {};
  StreamSubscription<geo.Position>? _positionStreamSubscription;
  String? _currentTileId;
  int _discoveredTilesCount = 0;

  @override
  void initState() {
    super.initState();
    final token = dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';
    if (token.isNotEmpty) {
      MapboxOptions.setAccessToken(token);
    }
    _checkAndRequestLocationPermission();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    super.dispose();
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
      _processLocation(position.latitude, position.longitude);
    });
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
    
    await _loadDiscoveredTiles();
    
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
      body: MapWidget(
        key: const ValueKey("mapWidget"),
        cameraOptions: CameraOptions(
          center: Point(coordinates: Position(17.0326, 51.1097)),
          zoom: 15.0,
        ),
        styleUri: MapboxStyles.DARK,
        onMapCreated: _onMapCreated,
      ),
    );
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
}
