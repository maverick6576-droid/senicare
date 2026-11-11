import 'package:senicare/models/models.dart';

abstract class JobOfferRepository {
  Future<String> createOffer(JobOffer offer);
  Stream<List<JobOffer>> streamClientOffers(String clientId, {int limit = 10});
  Stream<List<JobOffer>> streamNearbyOffers(double lat, double lng, double maxDistanceKm, {int? limit});
  Future<void> updateOfferStatus(String offerId, JobOfferStatus status, {String? acceptedCaregiverId, String? acceptedApplicationId});
  
  Future<void> applyToOffer(JobApplication application);
  Stream<List<JobApplication>> streamOfferApplications(String offerId, {int limit = 20});
  Stream<JobApplication?> streamCaregiverApplicationForOffer(String offerId, String caregiverId);
  Future<void> updateApplicationStatus(String offerId, String applicationId, JobApplicationStatus status);
  Future<void> updateApplicationDetails(
    String offerId,
    String applicationId, {
    required String message,
    required double proposedPrice,
  });
  Future<void> withdrawApplication(String offerId, String applicationId, String caregiverId);
  Future<List<MapEntry<JobOffer, JobApplication>>> fetchCaregiverApplications(
    String caregiverId, {
    List<String> candidateOfferIds = const [],
  });

  Stream<JobOffer?> streamOffer(String offerId);
  Future<JobOffer?> getOffer(String offerId);
}

