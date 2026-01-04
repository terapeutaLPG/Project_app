import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'dart:async';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  MapboxMap? mapboxMap;
  bool _locationPermissionGranted = false;
  PointAnnotationManager? _pointAnnotationManager;
  PointAnnotation? _userLocationMarker;
  StreamSubscription<geo.Position>? _positionStreamSubscription;

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

  Future<void> _startLocationTracking() async {
    if (!_locationPermissionGranted) return;

    // Utwórz menedżer adnotacji punktowych
    if (mapboxMap != null && _pointAnnotationManager == null) {
      _pointAnnotationManager = await mapboxMap!.annotations.createPointAnnotationManager();
    }

    // Pobierz aktualną pozycję i wycentruj mapę
    try {
      final position = await geo.Geolocator.getCurrentPosition();
      _updateUserLocationMarker(position.latitude, position.longitude);
      
      // Wycentruj mapę na użytkowniku
      mapboxMap?.flyTo(
        CameraOptions(
          center: Point(coordinates: Position(position.longitude, position.latitude)),
          zoom: 16.0,
        ),
        MapAnimationOptions(duration: 1000),
      );
    } catch (e) {
      debugPrint('Błąd pobierania pozycji: $e');
    }

    // Subskrybuj strumień pozycji w czasie rzeczywistym
    const locationSettings = geo.LocationSettings(
      accuracy: geo.LocationAccuracy.high,
      distanceFilter: 10, // Aktualizuj co 10 metrów
    );

    _positionStreamSubscription = geo.Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((geo.Position position) {
      _updateUserLocationMarker(position.latitude, position.longitude);
    });
  }

  Future<void> _updateUserLocationMarker(double lat, double lon) async {
    if (_pointAnnotationManager == null) return;

    // Usuń stary marker jeśli istnieje
    if (_userLocationMarker != null) {
      await _pointAnnotationManager!.delete(_userLocationMarker!);
    }

    // Dodaj nowy marker na aktualnej pozycji
    final pointAnnotationOptions = PointAnnotationOptions(
      geometry: Point(coordinates: Position(lon, lat)),
      iconSize: 1.5,
      iconImage: "user-location-icon",
      iconColor: Colors.blue.value,
    );

    _userLocationMarker = await _pointAnnotationManager!.create(pointAnnotationOptions);
  }

  Future<void> _checkAndRequestLocationPermission() async {
    bool serviceEnabled;
    geo.LocationPermission permission;

    // Sprawdź czy usługi lokalizacji są włączone
    serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Usługi lokalizacji są wyłączone. Włącz je w ustawieniach.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    // Sprawdź status uprawnień
    permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      // Poproś o uprawnienia - wyświetli systemowy dialog
      permission = await geo.Geolocator.requestPermission();
      if (permission == geo.LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Uprawnienia do lokalizacji zostały odrzucone.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }
    }

    if (permission == geo.LocationPermission.deniedForever) {
      // Uprawnienia odrzucone na stałe
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Uprawnienia do lokalizacji odrzucone na stałe. Zmień w ustawieniach.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    // Uprawnienia przyznane
    setState(() {
      _locationPermissionGranted = true;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dostęp do lokalizacji przyznany!'),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.green,
        ),
      );
    }

    // Rozpocznij śledzenie lokalizacji
    _startLocationTracking();
  }

  _onMapCreated(MapboxMap map) {
    mapboxMap = map;
    // Jeśli uprawnienia już przyznane, uruchom śledzenie
    if (_locationPermissionGranted) {
      _startLocationTracking();
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
        title: const Text('Mapa'),
        actions: [
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
        styleUri: MapboxStyles.MAPBOX_STREETS,
        onMapCreated: _onMapCreated,
      ),
    );
  }
}
