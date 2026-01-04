import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:geolocator/geolocator.dart' as geo;

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  MapboxMap? mapboxMap;
  bool _locationPermissionGranted = false;

  @override
  void initState() {
    super.initState();
    final token = dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';
    if (token.isNotEmpty) {
      MapboxOptions.setAccessToken(token);
    }
    _checkAndRequestLocationPermission();
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
  }

  _onMapCreated(MapboxMap map) {
    mapboxMap = map;
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
