import 'package:flutter/material.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:senicare/core/globals.dart';

class FirestoreJobOfferRepository implements JobOfferRepository {
  final CollectionReference _offersRef = FirebaseFirestore.instance.collection('job_offers');
  final CollectionReference _usersRef = FirebaseFirestore.instance.collection('users');

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

  @override
  Stream<List<JobOffer>> streamClientOffers(String clientId, {int limit = 10}) {
    return _offersRef
        .where('clientId', isEqualTo: clientId)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs.map((doc) => JobOffer.fromFirestore(doc)).toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  @override
  Stream<List<JobOffer>> streamNearbyOffers(double lat, double lng, double maxDistanceKm, {int? limit}) {
    return _offersRef
        .where('status', isEqualTo: JobOfferStatus.open.toString().split('.').last)
        .snapshots()
        .map((snapshot) {
      final matches = <({JobOffer offer, double distance})>[];
      for (final doc in snapshot.docs) {
        final offer = JobOffer.fromFirestore(doc);
        if (offer.isExpired) continue;
        final dist = calculateDistance(lat, lng, offer.clientLatitude, offer.clientLongitude);
        if (dist <= maxDistanceKm) {
          matches.add((offer: offer, distance: dist));
        }
      }

      matches.sort((a, b) {
        if (a.offer.isUrgent != b.offer.isUrgent) {
          return a.offer.isUrgent ? -1 : 1;
        }
        final dateCmp = a.offer.startDate.compareTo(b.offer.startDate);
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

  @override
  Stream<List<JobApplication>> streamOfferApplications(String offerId, {int limit = 20}) {
    return _offersRef
        .doc(offerId)
        .collection('applications')
        .orderBy('appliedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => JobApplication.fromFirestore(doc)).toList());
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
          final offer = JobOffer.fromFirestore(doc);
          offerById[offer.id] = offer;
          offerIds.add(offer.id);
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
          entries.add(MapEntry(validOffers[i], JobApplication.fromFirestore(snap.docs.first)));
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

