import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/tile_model.dart';
import '../models/tile_calculator.dart';

class TileService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> saveTile(double lat, double lon) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final tile = TileCalculator.getTileBounds(lat, lon);
    
    final tileRef = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('tiles')
        .doc(tile.tileId);

    final doc = await tileRef.get();
    if (doc.exists) return;

    await tileRef.set({
      'tileId': tile.tileId,
      'minLat': tile.minLat,
      'minLon': tile.minLon,
      'maxLat': tile.maxLat,
      'maxLon': tile.maxLon,
      'visitedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<bool> isTileDiscovered(String tileId) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    final doc = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('tiles')
        .doc(tileId)
        .get();

    return doc.exists;
  }

  Future<List<TileModel>> getDiscoveredTiles() async {
    final user = _auth.currentUser;
    if (user == null) return [];

    final snapshot = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('tiles')
        .get();

    return snapshot.docs
        .map((doc) => TileModel.fromFirestore(doc.data()))
        .toList();
  }

  Future<void> clearAllTiles() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final snapshot = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('tiles')
        .get();

    final batch = _firestore.batch();
    for (var doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
