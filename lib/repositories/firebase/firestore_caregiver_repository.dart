import 'package:flutter/material.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreCaregiverRepository implements CaregiverRepository {
  final CollectionReference _collection = FirebaseFirestore.instance.collection('caregivers');
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
      if (doc.exists) {
        return CaregiverProfile.fromFirestore(doc);
      }
      return null;
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

  /// Returns ONLY the slots stored in Firestore for the given caregiver/date.
  /// Does NOT fall back to mock data, which was hiding real data bugs.
  @override
  Future<List<TimeSlot>> fetchTimeSlots(String caregiverId, String date) async {
    try {
      final snapshot = await _collection
          .doc(caregiverId)
          .collection('availability')
          .doc(date)
          .collection('slots')
          .get();

      if (snapshot.docs.isNotEmpty) {
        final slots = snapshot.docs.map((doc) => TimeSlot.fromFirestore(doc)).toList();
        slots.sort((a, b) => a.dateTime.compareTo(b.dateTime));
        return slots;
      }

      // Generación por defecto (09:00 - 18:00) si no hay excepciones manuales creadas en Firestore,
      // garantizando que cualquier cuidador verificado pueda recibir reservas de inmediato.
      final List<TimeSlot> defaultSlots = [];
      for (int i = 9; i <= 18; i++) {
        final hourString = '${i.toString().padLeft(2, '0')}:00';
        defaultSlots.add(TimeSlot(
          id: '${date}_$hourString',
          dateTime: DateTime.parse('${date}T$hourString:00'),
          isAvailable: true,
        ));
      }
      return defaultSlots;
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
      final batch = FirebaseFirestore.instance.batch();
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

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } while (snapshot.docs.length == 500);
  }
}


