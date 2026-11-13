import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreCaregiverRepository implements CaregiverRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth? _auth;

  FirestoreCaregiverRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth;

  CollectionReference get _collection => _firestore.collection('caregivers');
  DocumentSnapshot? _lastDocument;
  bool _hasMore = true;

  @override
  Future<List<CaregiverProfile>> fetchCaregivers({String specialty = 'Todos', String query = '', bool refresh = false, double? mapLat, double? mapLng}) async {
    if (refresh) {
      _lastDocument = null;
      _hasMore = true;
    }

    if (!_hasMore) return [];

    try {
      Query firestoreQuery = _collection.where('verificationStatus', isEqualTo: 'approved');
      
      if (mapLat != null && mapLng != null) {
        double latDelta = 0.5; // roughly 50km
        firestoreQuery = firestoreQuery
            .where('latitude', isGreaterThanOrEqualTo: mapLat - latDelta)
            .where('latitude', isLessThanOrEqualTo: mapLat + latDelta);
      }
      
      firestoreQuery = firestoreQuery.limit(30);
      
      if (_lastDocument != null) {
        firestoreQuery = firestoreQuery.startAfterDocument(_lastDocument!);
      }

      QuerySnapshot querySnapshot;
      try {
        querySnapshot = await firestoreQuery.get();
      } catch (e) {
        debugPrint('Warning: Compound query failed ($e). Falling back to approved caregivers query.');
        querySnapshot = await _collection.where('verificationStatus', isEqualTo: 'approved').limit(30).get();
      }
      
      if (querySnapshot.docs.length < 20) {
        _hasMore = false;
      }

      if (querySnapshot.docs.isNotEmpty) {
        _lastDocument = querySnapshot.docs.last;
      }
      
      List<CaregiverProfile> caregivers = querySnapshot.docs
          .map((doc) => CaregiverProfile.fromFirestore(doc))
          .toList();
      
      if (specialty != 'Todos') {
        caregivers = caregivers.where((c) => c.specialties.contains(specialty)).toList();
      }
      
      if (query.trim().isNotEmpty) {
        final q = query.trim().toLowerCase();
        caregivers = caregivers.where((c) {
          return c.name.toLowerCase().contains(q) ||
              c.title.toLowerCase().contains(q) ||
              c.bio.toLowerCase().contains(q) ||
              c.homeAddress.toLowerCase().contains(q) ||
              c.specialties.any((s) => s.toLowerCase().contains(q));
        }).toList();
      }

      return caregivers;
    } catch (e) {
      debugPrint('==================================================');
      debugPrint('âš ï¸ Error fetching caregivers from Firestore: $e');
      debugPrint('==================================================');
      rethrow;
    }
  }

  @override
  Future<CaregiverProfile?> getCaregiver(String id) async {
    try {
      final doc = await _collection.doc(id).get();
      if (!doc.exists) return null;
      final profile = CaregiverProfile.fromFirestore(doc);
      final currentUid = (_auth ?? FirebaseAuth.instance).currentUser?.uid;
      if (currentUid == id) {
        try {
          final privateDoc = await _collection
              .doc(id)
              .collection('private')
              .doc('verification')
              .get();
          if (privateDoc.exists) {
            final pData = privateDoc.data() ?? {};
            final privateDni = pData['dniUrl']?.toString() ?? '';
            final privateCriminal = pData['criminalRecordUrl']?.toString() ?? '';
            if (privateDni.isNotEmpty || privateCriminal.isNotEmpty) {
              return CaregiverProfile(
                id: profile.id,
                name: profile.name,
                title: profile.title,
                bio: profile.bio,
                pricePerHour: profile.pricePerHour,
                rating: profile.rating,
                reviewsCount: profile.reviewsCount,
                distance: profile.distance,
                latitude: profile.latitude,
                longitude: profile.longitude,
                imageUrl: profile.imageUrl,
                voiceIntroUrl: profile.voiceIntroUrl,
                specialties: profile.specialties,
                verified: profile.verified,
                availableSlots: profile.availableSlots,
                dniUrl: privateDni.isNotEmpty ? privateDni : profile.dniUrl,
                criminalRecordUrl: privateCriminal.isNotEmpty ? privateCriminal : profile.criminalRecordUrl,
                hasDniSubmitted: profile.hasDniSubmitted || privateDni.isNotEmpty,
                hasCriminalSubmitted: profile.hasCriminalSubmitted || privateCriminal.isNotEmpty,
                maxDistanceRadius: profile.maxDistanceRadius,
                homeAddress: profile.homeAddress,
                verificationStatus: profile.verificationStatus,
                stripeAccountId: profile.stripeAccountId,
                onboardingComplete: profile.onboardingComplete,
                isKycVerified: profile.isKycVerified,
                hasSeenCaregiverTutorial: profile.hasSeenCaregiverTutorial,
                noShowsCount: profile.noShowsCount,
                incidentDates: profile.incidentDates,
                blockedUntil: profile.blockedUntil,
                accountStatus: profile.accountStatus,
              );
            }
          }
        } catch (_) {
          // Non-owner or offline: return public profile safely
        }
      }
      return profile;
    } catch (e) {
      debugPrint('Error fetching caregiver: $e');
      throw Exception('Error fetching caregiver: $e');
    }
  }

  @override
  Future<void> updateCaregiverAvailability(String id, String day, List<String> hours) async {
    await _collection.doc(id).update({
      'availableSlots.$day': hours,
    });
  }

  @override
  Future<void> updateProfile(String id, Map<String, dynamic> data) async {
    await _collection.doc(id).set(data, SetOptions(merge: true));
  }

  /// Combina el horario base (09:00 - 18:00) con cualquier excepción o franja
  /// personalizada almacenada en Firestore para el día indicado.
  static List<TimeSlot> mergeDayTimeSlots(
    String date,
    List<TimeSlot> storedSlots,
  ) {
    final Map<String, TimeSlot> byHourKey = {};
    for (final slot in storedSlots) {
      final hourKey =
          '${slot.dateTime.hour.toString().padLeft(2, '0')}:${slot.dateTime.minute.toString().padLeft(2, '0')}';
      byHourKey[hourKey] = slot;
    }

    final Map<String, TimeSlot> merged = {};
    for (int i = 9; i <= 18; i++) {
      final hourString = '${i.toString().padLeft(2, '0')}:00';
      merged[hourString] = byHourKey[hourString] ??
          TimeSlot(
            id: '${date}_$hourString',
            dateTime: DateTime.parse('${date}T$hourString:00'),
            isAvailable: true,
          );
    }
    for (final entry in byHourKey.entries) {
      merged.putIfAbsent(entry.key, () => entry.value);
    }

    final slots = merged.values.toList();
    slots.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    return slots;
  }

  /// Returns base schedule merged with Firestore slot overrides for the given caregiver/date.
  @override
  Future<List<TimeSlot>> fetchTimeSlots(String caregiverId, String date) async {
    try {
      final snapshot = await _collection
          .doc(caregiverId)
          .collection('availability')
          .doc(date)
          .collection('slots')
          .get();

      final stored = snapshot.docs.map((doc) => TimeSlot.fromFirestore(doc)).toList();
      return mergeDayTimeSlots(date, stored);
    } catch (e) {
      debugPrint('Error fetching timeslots from Firestore: $e');
      rethrow;
    }
  }

  @override
  Future<void> updateTimeSlot(String caregiverId, String date, TimeSlot slot) async {
    try {
      await _collection
          .doc(caregiverId)
          .collection('availability')
          .doc(date)
          .collection('slots')
          .doc(slot.id)
          .set(slot.toFirestore(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error updating timeslot: $e');
      rethrow; // Propagate so callers can handle failures properly
    }
  }

  /// Atomically writes up to 500 slots for a single day using a Firestore WriteBatch.
  /// If slots exceed 500, they are split into multiple sequential batches.
  @override
  Future<void> setBatchTimeSlots(String caregiverId, String date, List<TimeSlot> slots) async {
    if (slots.isEmpty) return;

    final slotsRef = _collection
        .doc(caregiverId)
        .collection('availability')
        .doc(date)
        .collection('slots');

    // Firestore batches support up to 500 operations
    const batchSize = 500;
    for (int i = 0; i < slots.length; i += batchSize) {
      final batch = _firestore.batch();
      final chunk = slots.sublist(i, (i + batchSize).clamp(0, slots.length));
      for (final slot in chunk) {
        batch.set(slotsRef.doc(slot.id), slot.toFirestore());
      }
      await batch.commit();
    }
  }

  /// Deletes all slot documents for a given day in batches of 500.
  @override
  Future<void> clearDaySlots(String caregiverId, String date) async {
    final slotsRef = _collection
        .doc(caregiverId)
        .collection('availability')
        .doc(date)
        .collection('slots');

    // Read all existing docs and delete in batches
    QuerySnapshot snapshot;
    do {
      snapshot = await slotsRef.limit(500).get();
      if (snapshot.docs.isEmpty) break;

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } while (snapshot.docs.length == 500);
  }
}


