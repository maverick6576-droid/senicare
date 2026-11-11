import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreStatsRepository {
  final CollectionReference _collection = FirebaseFirestore.instance.collection('client_caregiver_stats');

  String _getDocId(String clientId, String caregiverId) {
    return '${clientId}_$caregiverId';
  }

  Future<int> getAccumulatedHours(String clientId, String caregiverId) async {
    try {
      final docId = _getDocId(clientId, caregiverId);
      final doc = await _collection.doc(docId).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>?;
        return data?['accumulatedHours'] as int? ?? 0;
      }
      return 0;
    } catch (e) {
      debugPrint('Error getting accumulated hours: $e');
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> getCaregiverClientStats(String caregiverId) async {
    try {
      final query = await _collection.where('caregiverId', isEqualTo: caregiverId).get();
      return query.docs.map((d) => d.data() as Map<String, dynamic>).toList();
    } catch (e) {
      debugPrint('Error getting caregiver stats: $e');
      return [];
    }
  }

  Future<void> addCompletedHours(String clientId, String caregiverId, int hoursToAdd) async {
    try {
      final docId = _getDocId(clientId, caregiverId);
      await _collection.doc(docId).set({
        'clientId': clientId,
        'caregiverId': caregiverId,
        'accumulatedHours': FieldValue.increment(hoursToAdd),
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error updating accumulated hours: $e');
    }
  }

  /// Calculates the commission rate based on accumulated hours with a specific client.
  /// Tier 1 (1-20 hrs): 18%
  /// Tier 2 (21-80 hrs): 12%
  /// Tier 3 (>80 hrs): 6%
  static double calculateCommissionRate(int accumulatedHours) {
    if (accumulatedHours <= 20) return 0.18;
    if (accumulatedHours <= 80) return 0.12;
    return 0.06;
  }

  static double calculateEffectiveOfferCommissionRate(int accumulatedHours, double urgencyBonusRate) {
    final baseTier = calculateCommissionRate(accumulatedHours);
    return (baseTier - urgencyBonusRate).clamp(0.05, 0.18);
  }

  static double estimateOfferNetTotal({
    required int totalHours,
    required double hourlyRate,
    required double urgencyBonusRate,
    int accumulatedHours = 0,
  }) {
    final effectiveRate = calculateEffectiveOfferCommissionRate(accumulatedHours, urgencyBonusRate);
    return (totalHours * hourlyRate) * (1.0 - effectiveRate);
  }
}
