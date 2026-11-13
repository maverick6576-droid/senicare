import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:senicare/repositories/repositories.dart';

class DependencyInjection {
  static late AuthRepository auth;
  static late CaregiverRepository caregivers;
  static late BookingRepository bookings;
  static late ChatRepository chats;
  static late StatsRepository stats;
  static late ReviewRepository reviews;
  static late ReportRepository reports;
  static late ClientRepository clients;
  static late JobOfferRepository jobOffers;
  static FamilyRepository? _families;

  /// Repositorio familiar con inicialización perezosa segura para tests existentes
  /// que no invocan `DependencyInjection.initialize()`.
  static FamilyRepository get families =>
      _families ??= MockFamilyRepository();
  static set families(FamilyRepository repo) => _families = repo;

  static void initialize() {
    bool hasFirebase = false;
    try {
      if (Firebase.apps.isNotEmpty) hasFirebase = true;
    } catch (_) {}

    if (!hasFirebase) {
      debugPrint(
        "WARNING: Firebase is not initialized. Falling back to Mock repositories.",
      );
      auth = MockAuthRepository();
      caregivers = MockCaregiverRepository();
      bookings = MockBookingRepository();
      chats = MockChatRepository();
      stats = _NoopStatsRepository();
      reviews = MockReviewRepository();
      reports = MockReportRepository();
      clients = MockClientRepository();
      jobOffers = MockJobOfferRepository();
      families = MockFamilyRepository();
      return;
    }
    // Firebase Implementations (using firebase_auth and cloud_firestore)
    auth = FirebaseAuthRepository();
    caregivers = FirestoreCaregiverRepository();
    bookings = FirestoreBookingRepository();
    chats = FirestoreChatRepository();
    stats = FirestoreStatsRepository();
    reviews = FirestoreReviewRepository();
    reports = FirestoreReportRepository();
    clients = FirestoreClientRepository();
    jobOffers = FirestoreJobOfferRepository();
    families = FirestoreFamilyRepository();
  }
}

class _NoopStatsRepository implements StatsRepository {
  @override
  Future<int> getAccumulatedHours(String clientId, String caregiverId) async => 0;

  @override
  Future<List<Map<String, dynamic>>> getCaregiverClientStats(
    String caregiverId,
  ) async =>
      const [];

  @override
  Future<void> addCompletedHours(
    String clientId,
    String caregiverId,
    int hoursToAdd,
  ) async {}
}
