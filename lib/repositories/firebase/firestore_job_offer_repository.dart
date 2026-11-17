import 'package:flutter/material.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:senicare/core/globals.dart';

class FirestoreJobOfferRepository implements JobOfferRepository {
  final FirebaseFirestore _firestore;
  FirestoreJobOfferRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference get _offersRef => _firestore.collection('job_offers');
  CollectionReference get _usersRef => _firestore.collection('users');

  @override
  Future<String> createOffer(JobOffer offer) async {
    try {
      final docRef = await _offersRef.add(offer.toFirestore());
      return docRef.id;
    } catch (e) {
      debugPrint('Error creating offer: $e');
      rethrow;
    }
  }

  bool _isMissingIndexError(Object error) {
    if (error is FirebaseException && error.code == 'failed-precondition') {
      return true;
    }
    final msg = error.toString().toLowerCase();
    return msg.contains('failed-precondition') || msg.contains('requires an index');
  }

  List<JobOffer> _mapAndSortClientOffers(QuerySnapshot snapshot, {int? limit}) {
    final list = <JobOffer>[];
    for (final doc in snapshot.docs) {
      try {
        list.add(JobOffer.fromFirestore(doc));
      } catch (e) {
        debugPrint('Skipping malformed job offer ${doc.id}: $e');
      }
    }
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (limit != null && list.length > limit) {
      return list.take(limit).toList();
    }
    return list;
  }

  @override
  Stream<List<JobOffer>> streamClientOffers(String clientId, {int limit = 10}) async* {
    final indexedQuery = _offersRef
        .where('clientId', isEqualTo: clientId)
        .orderBy('createdAt', descending: true)
        .limit(limit);

    try {
      await for (final snapshot in indexedQuery.snapshots()) {
        yield _mapAndSortClientOffers(snapshot);
      }
    } catch (e) {
      if (!_isMissingIndexError(e)) {
        yield* Stream.error(e);
        return;
      }
      debugPrint('⚠️ streamClientOffers missing index ($e). Falling back to single-field query.');
      final fallbackQuery = _offersRef.where('clientId', isEqualTo: clientId);
      await for (final snapshot in fallbackQuery.snapshots()) {
        yield _mapAndSortClientOffers(snapshot, limit: limit);
      }
    }
  }

  @override
  Stream<List<JobOffer>> streamNearbyOffers(double lat, double lng, double maxDistanceKm, {int? limit}) {
    return _offersRef
        .where('status', isEqualTo: JobOfferStatus.open.toString().split('.').last)
        .snapshots()
        .map((snapshot) {
      final matches = <({JobOffer offer, double distance})>[];
      for (final doc in snapshot.docs) {
        try {
          final offer = JobOffer.fromFirestore(doc);
          if (offer.isExpired) continue;
          final dist = calculateDistance(lat, lng, offer.clientLatitude, offer.clientLongitude);
          if (dist <= maxDistanceKm) {
            matches.add((offer: offer, distance: dist));
          }
        } catch (e) {
          debugPrint('Skipping malformed nearby offer ${doc.id}: $e');
        }
      }

      matches.sort((a, b) {
        final aUrgent = a.offer.effectiveUrgency();
        final bUrgent = b.offer.effectiveUrgency();
        if (aUrgent != bUrgent) {
          return aUrgent ? -1 : 1;
        }
        final dateCmp = a.offer.effectiveStartDateTime.compareTo(b.offer.effectiveStartDateTime);
        if (dateCmp != 0) return dateCmp;
        return a.distance.compareTo(b.distance);
      });

      final ordered = matches.map((m) => m.offer);
      return limit != null ? ordered.take(limit).toList() : ordered.toList();
    });
  }

  @override
  Future<void> updateOfferStatus(String offerId, JobOfferStatus status, {String? acceptedCaregiverId, String? acceptedApplicationId}) async {
    try {
      final data = <String, dynamic>{'status': status.toString().split('.').last};
      if (acceptedCaregiverId != null) data['acceptedCaregiverId'] = acceptedCaregiverId;
      if (acceptedApplicationId != null) data['acceptedApplicationId'] = acceptedApplicationId;
      await _offersRef.doc(offerId).update(data);
    } catch (e) {
      debugPrint('Error updating offer: $e');
      rethrow;
    }
  }

  @override
  Future<void> promoteOfferToUrgent(String offerId, {double bonusRate = 0.10}) async {
    try {
      await _offersRef.doc(offerId).update({
        'isUrgent': true,
        'urgencyBonusRate': bonusRate,
      });
    } catch (e) {
      debugPrint('Error promoting offer to urgent: $e');
    }
  }

  @override
  Future<void> applyToOffer(JobApplication application) async {
    try {
      final appsRef = _offersRef.doc(application.offerId).collection('applications');
      final existing = await appsRef
          .where('caregiverId', isEqualTo: application.caregiverId)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        final current = JobApplication.fromFirestore(existing.docs.first);
        if (current.status != JobApplicationStatus.pending) {
          throw Exception('Ya existe una resolución para esta oferta.');
        }
        await existing.docs.first.reference.update({
          'message': application.message,
          'proposedPrice': application.proposedPrice,
          'caregiverName': application.caregiverName,
          'caregiverImageUrl': application.caregiverImageUrl,
          'caregiverRating': application.caregiverRating,
          'caregiverReviewsCount': application.caregiverReviewsCount,
          'appliedAt': Timestamp.fromDate(application.appliedAt),
        });
      } else {
        await appsRef.doc(application.caregiverId).set(application.toFirestore());
      }

      // Registro ligero para recuperar historial de postulaciones sin índices compuestos en subcolecciones
      try {
        await _usersRef.doc(application.caregiverId).set({
          'appliedOfferIds': FieldValue.arrayUnion([application.offerId]),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Warning syncing appliedOfferIds: $e');
      }
    } catch (e) {
      debugPrint('Error applying to offer: $e');
      rethrow;
    }
  }

  List<JobApplication> _mapAndSortApplications(QuerySnapshot snapshot, {int? limit}) {
    final list = <JobApplication>[];
    for (final doc in snapshot.docs) {
      try {
        list.add(JobApplication.fromFirestore(doc));
      } catch (e) {
        debugPrint('Skipping malformed job application ${doc.id}: $e');
      }
    }
    list.sort((a, b) => b.appliedAt.compareTo(a.appliedAt));
    if (limit != null && list.length > limit) {
      return list.take(limit).toList();
    }
    return list;
  }

  @override
  Stream<List<JobApplication>> streamOfferApplications(String offerId, {int limit = 20}) async* {
    final appsRef = _offersRef.doc(offerId).collection('applications');
    final indexedQuery = appsRef.orderBy('appliedAt', descending: true).limit(limit);
    try {
      await for (final snapshot in indexedQuery.snapshots()) {
        yield _mapAndSortApplications(snapshot);
      }
    } catch (e) {
      if (!_isMissingIndexError(e)) {
        yield* Stream.error(e);
        return;
      }
      await for (final snapshot in appsRef.snapshots()) {
        yield _mapAndSortApplications(snapshot, limit: limit);
      }
    }
  }

  @override
  Stream<JobApplication?> streamCaregiverApplicationForOffer(String offerId, String caregiverId) {
    if (caregiverId.isEmpty) return Stream.value(null);
    return _offersRef
        .doc(offerId)
        .collection('applications')
        .where('caregiverId', isEqualTo: caregiverId)
        .limit(1)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) return null;
          return JobApplication.fromFirestore(snapshot.docs.first);
        });
  }

  @override
  Future<void> updateApplicationStatus(String offerId, String applicationId, JobApplicationStatus status) async {
    try {
      await _offersRef
          .doc(offerId)
          .collection('applications')
          .doc(applicationId)
          .update({'status': status.toString().split('.').last});
    } catch (e) {
      debugPrint('Error updating application: $e');
      rethrow;
    }
  }

  @override
  Future<void> updateApplicationDetails(
    String offerId,
    String applicationId, {
    required String message,
    required double proposedPrice,
  }) async {
    try {
      await _offersRef
          .doc(offerId)
          .collection('applications')
          .doc(applicationId)
          .update({
            'message': message,
            'proposedPrice': proposedPrice,
            'appliedAt': Timestamp.fromDate(DateTime.now()),
          });
    } catch (e) {
      debugPrint('Error updating application details: $e');
      rethrow;
    }
  }

  @override
  Future<void> withdrawApplication(String offerId, String applicationId, String caregiverId) async {
    try {
      final appsRef = _offersRef.doc(offerId).collection('applications');
      final docId = applicationId.isNotEmpty ? applicationId : caregiverId;
      await appsRef.doc(docId).delete();
      try {
        await _usersRef.doc(caregiverId).set({
          'appliedOfferIds': FieldValue.arrayRemove([offerId]),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Warning removing appliedOfferIds: $e');
      }
    } catch (e) {
      debugPrint('Error withdrawing application: $e');
      rethrow;
    }
  }

  @override
  Future<List<MapEntry<JobOffer, JobApplication>>> fetchCaregiverApplications(
    String caregiverId, {
    List<String> candidateOfferIds = const [],
  }) async {
    if (caregiverId.isEmpty) return [];
    try {
      final offerIds = <String>{...candidateOfferIds.where((id) => id.isNotEmpty)};
      final offerById = <String, JobOffer>{};

      final metaResults = await Future.wait<dynamic>([
        _usersRef.doc(caregiverId).get().then<DocumentSnapshot?>((v) => v, onError: (_) => null),
        _offersRef
            .where('acceptedCaregiverId', isEqualTo: caregiverId)
            .get()
            .then<QuerySnapshot?>((v) => v, onError: (_) => null),
      ]);

      final userDoc = metaResults[0] as DocumentSnapshot?;
      if (userDoc != null && userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>?;
        final savedIds = List<String>.from(data?['appliedOfferIds'] ?? []);
        offerIds.addAll(savedIds.where((id) => id.isNotEmpty));
      }

      final acceptedSnap = metaResults[1] as QuerySnapshot?;
      if (acceptedSnap != null) {
        for (final doc in acceptedSnap.docs) {
          try {
            final offer = JobOffer.fromFirestore(doc);
            offerById[offer.id] = offer;
            offerIds.add(offer.id);
          } catch (e) {
            debugPrint('Skipping malformed accepted offer ${doc.id}: $e');
          }
        }
      }

      if (offerIds.isEmpty) return [];

      final missingIds = offerIds.where((id) => !offerById.containsKey(id)).toList();
      if (missingIds.isNotEmpty) {
        final fetchedOffers = await Future.wait(missingIds.map(getOffer));
        for (final offer in fetchedOffers) {
          if (offer != null) offerById[offer.id] = offer;
        }
      }

      final validOffers = offerById.values.toList();
      final appSnaps = await Future.wait<QuerySnapshot?>(
        validOffers.map(
          (offer) => _offersRef
              .doc(offer.id)
              .collection('applications')
              .where('caregiverId', isEqualTo: caregiverId)
              .limit(1)
              .get()
              .then<QuerySnapshot?>((v) => v, onError: (_) => null),
        ),
      );

      final entries = <MapEntry<JobOffer, JobApplication>>[];
      for (int i = 0; i < validOffers.length; i++) {
        final snap = appSnaps[i];
        if (snap != null && snap.docs.isNotEmpty) {
          try {
            entries.add(MapEntry(validOffers[i], JobApplication.fromFirestore(snap.docs.first)));
          } catch (e) {
            debugPrint('Skipping malformed application ${snap.docs.first.id}: $e');
          }
        }
      }
      return entries;
    } catch (e) {
      debugPrint('Error fetching caregiver applications: $e');
      return [];
    }
  }

  @override
  Stream<JobOffer?> streamOffer(String offerId) {
    return _offersRef.doc(offerId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return JobOffer.fromFirestore(doc);
    });
  }

  @override
  Future<JobOffer?> getOffer(String offerId) async {
    try {
      final doc = await _offersRef.doc(offerId).get();
      if (doc.exists) return JobOffer.fromFirestore(doc);
      return null;
    } catch (e) {
      debugPrint('Error getting offer: $e');
      return null;
    }
  }
}

