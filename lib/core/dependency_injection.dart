import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:senicare/repositories/repositories.dart';

class DependencyInjection {
  static late AuthRepository auth;
  static late CaregiverRepository caregivers;
  static late BookingRepository bookings;
  static late ChatRepository chats;
  static late FirestoreStatsRepository stats;
  static late ReviewRepository reviews;
  static late ReportRepository reports;
  static late ClientRepository clients;
  static late JobOfferRepository jobOffers;

  static void initialize() {
    bool hasFirebase = false;
    try {
      if (Firebase.apps.isNotEmpty) hasFirebase = true;
    } catch (_) {}

    if (!hasFirebase) {
      debugPrint("CRITICAL: Firebase failed to initialize. The app will likely crash.");
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
  }
}
