import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:senicare/repositories/interfaces/stats_repository.dart';

class FirestoreStatsRepository implements StatsRepository {
  final FirebaseFirestore _firestore;
  FirestoreStatsRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference get _collection => _firestore.collection('client_caregiver_stats');

  String _getDocId(String clientId, String caregiverId) {
    return '${clientId}_$caregiverId';
  }

  @override
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

  @override
  Future<List<Map<String, dynamic>>> getCaregiverClientStats(String caregiverId) async {
    try {
      final query = await _collection.where('caregiverId', isEqualTo: caregiverId).get();
      return query.docs.map((d) => d.data() as Map<String, dynamic>).toList();
    } catch (e) {
      debugPrint('Error getting caregiver stats: $e');
      return [];
    }
  }

  @override
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

  /// Calcula la comisión del cuidador según las horas acumuladas con una misma familia
  /// (Modelo Opción 1 — Fidelidad Compartida):
  /// - Tramo 1 (0–30 h): 18% (el cuidador recibe el 82% íntegro de su tarifa)
  /// - Tramo 2 (31–100 h): 14% (el cuidador recibe el 86% íntegro)
  /// - Tramo 3 (>100 h): 10% (el cuidador recibe el 90% íntegro)
  static double calculateCommissionRate(int accumulatedHours) {
    if (accumulatedHours <= 30) return 0.18;
    if (accumulatedHours <= 100) return 0.14;
    return 0.10;
  }

  /// Calcula la comisión efectiva en ofertas de empleo aplicando el bono de urgencia
  /// con un suelo de sostenibilidad del 8% (0.08).
  static double calculateEffectiveOfferCommissionRate(
    int accumulatedHours,
    double urgencyBonusRate,
  ) {
    final baseTier = calculateCommissionRate(accumulatedHours);
    return (baseTier - urgencyBonusRate).clamp(0.08, 0.18);
  }

  /// Calcula el porcentaje base del "Escudo de Protección Familiar" para la familia
  /// según sus horas acumuladas con el cuidador:
  /// - Nivel 1 (0–30 h): 5.0% (0.05)
  /// - Nivel 2 (31–100 h): 3.5% (0.035)
  /// - Nivel 3 (>100 h): 2.0% (0.02)
  static double calculateBaseClientFeeRate(int accumulatedHours) {
    if (accumulatedHours <= 30) return 0.05;
    if (accumulatedHours <= 100) return 0.035;
    return 0.02;
  }

  /// Si la reserva directa es de 4h o más (Bono Familiar Multi-Sesión), la cuota
  /// del Escudo Familiar se reduce a la mitad (-50%) sin recortar el sueldo del cuidador.
  static double calculateEffectiveClientFeeRate(
    int accumulatedHours, {
    bool isFourHourPack = false,
  }) {
    final base = calculateBaseClientFeeRate(accumulatedHours);
    return isFourHourPack ? (base * 0.5) : base;
  }

  /// Importe mínimo de la cuota del Escudo Familiar para cubrir costes fijos de
  /// pasarela Stripe en turnos cortos de 1 hora.
  static double minimumClientFeeEur(
    int accumulatedHours, {
    bool isFourHourPack = false,
  }) {
    final double baseMin = accumulatedHours <= 30
        ? 1.50
        : (accumulatedHours <= 100 ? 1.25 : 1.00);
    return isFourHourPack ? (baseMin * 0.5) : baseMin;
  }

  /// Calcula la cuota exacta del Escudo Familiar en euros (redondeada a céntimos).
  static double calculateClientFeeAmount({
    required double baseCost,
    required int accumulatedHours,
    bool isFourHourPack = false,
  }) {
    if (baseCost <= 0) return 0.0;
    final rate = calculateEffectiveClientFeeRate(
      accumulatedHours,
      isFourHourPack: isFourHourPack,
    );
    final minFee = minimumClientFeeEur(
      accumulatedHours,
      isFourHourPack: isFourHourPack,
    );
    final rawFee = baseCost * rate;
    final effectiveFee = rawFee < minFee ? minFee : rawFee;
    return (effectiveFee * 100).roundToDouble() / 100.0;
  }

  static String familyLoyaltyTierTitle(int accumulatedHours) {
    if (accumulatedHours <= 30) {
      return 'Nivel 1 · Escudo Estándar (5%)';
    }
    if (accumulatedHours <= 100) {
      return 'Nivel 2 · Familia Fiel (3,5% · ahorras 30%)';
    }
    return 'Nivel 3 · Familia Fidelidad VIP (2% · ahorras 60%)';
  }

  static double estimateOfferNetTotal({
    required int totalHours,
    required double hourlyRate,
    required double urgencyBonusRate,
    int accumulatedHours = 0,
  }) {
    final effectiveRate = calculateEffectiveOfferCommissionRate(
      accumulatedHours,
      urgencyBonusRate,
    );
    return (totalHours * hourlyRate) * (1.0 - effectiveRate);
  }
}
