import 'package:cloud_firestore/cloud_firestore.dart';
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
}
