import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/place.dart';

class PlaceService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<List<Place>> getPlaces() async {
    try {
      final snapshot = await _firestore.collection('places').get();
      
      final places = snapshot.docs
          .map((doc) => Place.fromFirestore(doc.data(), doc.id))
          .toList();
      
      places.sort((a, b) => a.name.compareTo(b.name));
      
      return places;
    } catch (e) {
      return [];
    }
  }

  Future<void> seedPlacesIfEmpty() async {
    if (kReleaseMode) return;

    try {
      final snapshot = await _firestore.collection('places').limit(1).get();
      if (snapshot.docs.isNotEmpty) return;

      final places = [
        {'name': 'Rynek Wroclaw', 'lat': 51.1097, 'lon': 17.0319},
        {'name': 'Ostrow Tumski', 'lat': 51.1150, 'lon': 17.0447},
        {'name': 'Uniwersytet Wroclawski', 'lat': 51.1139, 'lon': 17.0329},
        {'name': 'Hala Stulecia', 'lat': 51.1067, 'lon': 17.0772},
        {'name': 'Panorama Raclawiecka', 'lat': 51.1100, 'lon': 17.0438},
        {'name': 'ZOO Wroclaw', 'lat': 51.1047, 'lon': 17.0757},
        {'name': 'Hydropolis', 'lat': 51.1079, 'lon': 17.0542},
        {'name': 'Ogrod Japonski', 'lat': 51.1086, 'lon': 17.0788},
        {'name': 'Most Grunwaldzki', 'lat': 51.1098, 'lon': 17.0464},
        {'name': 'Most Pokoju', 'lat': 51.1106, 'lon': 17.0628},
        {'name': 'Afrykarium', 'lat': 51.1049, 'lon': 17.0761},
        {'name': 'Sky Tower', 'lat': 51.0949, 'lon': 17.0228},
        {'name': 'Teatr Narodowy', 'lat': 51.1037, 'lon': 17.0377},
        {'name': 'Opera Wroclawska', 'lat': 51.1076, 'lon': 17.0293},
        {'name': 'Muzeum Narodowe', 'lat': 51.1118, 'lon': 17.0464},
        {'name': 'Kosciol sw Elzbiety', 'lat': 51.1104, 'lon': 17.0311},
        {'name': 'Archikatedra', 'lat': 51.1150, 'lon': 17.0451},
        {'name': 'Park Szczytnicki', 'lat': 51.1103, 'lon': 17.0822},
        {'name': 'Iglica', 'lat': 51.1072, 'lon': 17.0777},
        {'name': 'Stadion Wroclaw', 'lat': 51.1409, 'lon': 16.9428},
        {'name': 'Pergola', 'lat': 51.1073, 'lon': 17.0781},
        {'name': 'Wzgorze Partyzantow', 'lat': 51.1155, 'lon': 17.0897},
        {'name': 'Fontanna Multimedialna', 'lat': 51.1077, 'lon': 17.0779},
        {'name': 'Pasaz Niepolda', 'lat': 51.1094, 'lon': 17.0323},
        {'name': 'Galeria Dominikanska', 'lat': 51.1091, 'lon': 17.0378},
        {'name': 'Magnolia Park', 'lat': 51.1273, 'lon': 16.9907},
        {'name': 'Wroclavia', 'lat': 51.0930, 'lon': 17.0146},
        {'name': 'Market Hall', 'lat': 51.1142, 'lon': 17.0289},
        {'name': 'Stary Ratusz', 'lat': 51.1096, 'lon': 17.0316},
        {'name': 'Okraglak', 'lat': 51.0982, 'lon': 17.0380},
        {'name': 'Dworzec Glowny', 'lat': 51.0977, 'lon': 17.0363},
        {'name': 'Plac Solny', 'lat': 51.1106, 'lon': 17.0328},
        {'name': 'Hala Targowa', 'lat': 51.1142, 'lon': 17.0289},
        {'name': 'Biblioteka Uniwersytecka', 'lat': 51.1159, 'lon': 17.0336},
        {'name': 'Politechnika Wroclawska', 'lat': 51.1077, 'lon': 17.0586},
        {'name': 'AWF Wroclaw', 'lat': 51.1118, 'lon': 17.0633},
        {'name': 'Park Poludniowy', 'lat': 51.0840, 'lon': 17.0146},
        {'name': 'Las Osobowicki', 'lat': 51.1449, 'lon': 17.0942},
        {'name': 'Zakrzow', 'lat': 51.0694, 'lon': 17.0033},
        {'name': 'Psie Pole', 'lat': 51.1382, 'lon': 17.0825},
        {'name': 'Nadodrze', 'lat': 51.1158, 'lon': 17.0189},
        {'name': 'Gaj', 'lat': 51.1292, 'lon': 16.9517},
        {'name': 'Borek', 'lat': 51.0631, 'lon': 17.0258},
        {'name': 'Ksieze Male', 'lat': 51.0775, 'lon': 17.0108},
        {'name': 'Pawlowice', 'lat': 51.1654, 'lon': 16.9469},
        {'name': 'Karlowice', 'lat': 51.1441, 'lon': 17.0250},
        {'name': 'Kosmonautow', 'lat': 51.1517, 'lon': 17.0153},
        {'name': 'Krzyki', 'lat': 51.0817, 'lon': 17.0203},
        {'name': 'Fabryczna', 'lat': 51.1119, 'lon': 16.9947},
        {'name': 'Plac Grunwaldzki', 'lat': 51.1111, 'lon': 17.0577},
      ];

      final batch = _firestore.batch();
      for (var place in places) {
        final slug = _createSlug(place['name'] as String);
        final docRef = _firestore.collection('places').doc(slug);
        batch.set(docRef, {
          'name': place['name'],
          'lat': place['lat'],
          'lon': place['lon'],
          'radiusMeters': 40,
          'points': 10,
        });
      }
      await batch.commit();
    } catch (e) {}
  }

  String _createSlug(String text) {
    final map = {
      'ą': 'a', 'ć': 'c', 'ę': 'e', 'ł': 'l', 'ń': 'n',
      'ó': 'o', 'ś': 's', 'ź': 'z', 'ż': 'z',
      'Ą': 'a', 'Ć': 'c', 'Ę': 'e', 'Ł': 'l', 'Ń': 'n',
      'Ó': 'o', 'Ś': 's', 'Ź': 'z', 'Ż': 'z',
    };
    
    var slug = text.toLowerCase();
    map.forEach((key, value) {
      slug = slug.replaceAll(key, value);
    });
    slug = slug.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    slug = slug.replaceAll(RegExp(r'^-+|-+$'), '');
    
    return slug;
  }
}
