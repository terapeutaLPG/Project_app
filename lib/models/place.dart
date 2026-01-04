class Place {
  final String id;
  final String name;
  final double lat;
  final double lon;
  final double radiusMeters;
  final int points;

  Place({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.radiusMeters,
    required this.points,
  });

  factory Place.fromFirestore(Map<String, dynamic> data, String docId) {
    return Place(
      id: docId,
      name: data['name'] as String? ?? '',
      lat: (data['lat'] as num?)?.toDouble() ?? 0.0,
      lon: (data['lon'] as num?)?.toDouble() ?? 0.0,
      radiusMeters: (data['radiusMeters'] as num?)?.toDouble() ?? 50.0,
      points: data['points'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'lat': lat,
      'lon': lon,
      'radiusMeters': radiusMeters,
      'points': points,
    };
  }
}
