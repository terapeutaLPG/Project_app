import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/place.dart';

class ClaimPlaceResult {
  final bool success;
  final bool alreadyClaimed;
  final String? error;

  const ClaimPlaceResult({
    required this.success,
    this.alreadyClaimed = false,
    this.error,
  });
}

class PlaceFetchResult {
  final List<Place> places;
  final bool usedFallback;

  PlaceFetchResult({required this.places, required this.usedFallback});
}

class PlaceService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<PlaceFetchResult> fetchPlacesOrFallback() async {
    final places = await getPlaces();
    if (places.isNotEmpty) {
      return PlaceFetchResult(places: places, usedFallback: false);
    }
    final fallback = _generateFallbackPlaces();
    return PlaceFetchResult(places: fallback, usedFallback: true);
  }

  Future<Set<String>> getClaimedPlaceIds() async {
    final user = _auth.currentUser;
    if (user == null) return {};

    try {
      // Primary source: user subcollection to match claim writes
      final claimedSnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('claimed_places')
          .get();

      final claimedIds = claimedSnapshot.docs.map((doc) => doc.id).toSet();
      if (claimedIds.isNotEmpty) return claimedIds;

      // Legacy fallback: array stored in claimed_places/{uid}
      final doc = await _firestore.collection('claimed_places').doc(user.uid).get();
      final data = doc.data();
      if (data == null) return {};
      final list = (data['placeIds'] as List?)?.whereType<String>().toList() ?? [];
      return list.toSet();
    } catch (_) {
      return {};
    }
  }

  Future<ClaimPlaceResult> claimPlace(String placeId, int gainedPoints) async {
    final user = _auth.currentUser;
    if (user == null) {
      return const ClaimPlaceResult(success: false, error: 'Brak zalogowanego użytkownika');
    }
    try {
      final userRef = _firestore.collection('users').doc(user.uid);
      final placeRef = userRef.collection('claimed_places').doc(placeId);

      final claimed = await _firestore.runTransaction<ClaimPlaceResult>((tx) async {
        // READS FIRST (per Firestore requirements)
        final claimedSnap = await tx.get(placeRef);
        final userSnap = await tx.get(userRef);
        if (claimedSnap.exists) {
          return const ClaimPlaceResult(success: false, alreadyClaimed: true);
        }

        final data = userSnap.data() ?? {};
        final currentTotal = (data['totalPoints'] as num?)?.toInt() ?? 0;
        final currentLevel = (data['level'] as num?)?.toInt() ?? 1;
        final currentNext = (data['nextLevelPoints'] as num?)?.toInt() ?? 30;

        var newTotal = currentTotal + gainedPoints;
        var newLevel = currentLevel;
        var newNext = currentNext;

        while (newTotal >= newNext) {
          newLevel += 1;
          newNext = newNext * 2;
        }

        final updateData = <String, dynamic>{
          'totalPoints': newTotal,
          'level': newLevel,
          'nextLevelPoints': newNext,
          'email': data['email'] ?? user.email,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        if (data['createdAt'] == null) {
          updateData['createdAt'] = FieldValue.serverTimestamp();
        }

        // WRITES AFTER ALL READS
        tx.set(placeRef, {
          'claimedAt': FieldValue.serverTimestamp(),
          'gainedPoints': gainedPoints,
          'placeId': placeId,
          'userId': user.uid,
        }, SetOptions(merge: true));

        // Keep legacy aggregate list in sync for older reads
        final claimedListRef = _firestore.collection('claimed_places').doc(user.uid);
        tx.set(claimedListRef, {
          'placeIds': FieldValue.arrayUnion([placeId]),
        }, SetOptions(merge: true));

        tx.set(userRef, updateData, SetOptions(merge: true));
        return const ClaimPlaceResult(success: true);
      });

      return claimed;
    } on FirebaseException catch (e) {
      return ClaimPlaceResult(success: false, error: e.message ?? e.code);
    } catch (e) {
      return ClaimPlaceResult(success: false, error: e.toString());
    }
  }

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

  List<Place> _generateFallbackPlaces() {
    const centerLat = 51.1079;
    const centerLon = 17.0385;
    const innerRadius = 0.01;
    const outerRadius = 0.02;
    const minLat = 51.07;
    const maxLat = 51.15;
    const minLon = 16.95;
    const maxLon = 17.12;

    final random = Random();
    final places = <Place>[];

    double _clamp(double value, double min, double max) {
      if (value < min) return min;
      if (value > max) return max;
      return value;
    }

    double _gaussian(Random rng) {
      final u1 = rng.nextDouble().clamp(1e-6, 1.0);
      final u2 = rng.nextDouble();
      return sqrt(-2.0 * log(u1)) * cos(2 * pi * u2);
    }

    for (var i = 0; i < 50; i++) {
      final useInner = random.nextDouble() < 0.7;
      final radius = useInner ? innerRadius : outerRadius;
      final dx = _gaussian(random) * radius;
      final dy = _gaussian(random) * radius;
      final lat = _clamp(centerLat + dy, minLat, maxLat);
      final lon = _clamp(centerLon + dx, minLon, maxLon);

      places.add(Place(
        id: 'fallback-${i + 1}',
        name: 'punkt ${i + 1}',
        lat: lat,
        lon: lon,
        radiusMeters: 40,
        points: 10,
      ));
    }

    return places;
  }
}
