import 'package:flutter/material.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:senicare/core/globals.dart';

class FirestoreJobOfferRepository implements JobOfferRepository {
  final CollectionReference _offersRef = FirebaseFirestore.instance.collection('job_offers');

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
      final offers = snapshot.docs.map((doc) => JobOffer.fromFirestore(doc)).toList();
      var filtered = offers.where((offer) {
        final dist = calculateDistance(lat, lng, offer.clientLatitude, offer.clientLongitude);
        return dist <= maxDistanceKm;
      }).toList();
      return limit != null ? filtered.take(limit).toList() : filtered;
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
      await _offersRef
          .doc(application.offerId)
          .collection('applications')
          .add(application.toFirestore());
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

