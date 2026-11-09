import 'package:senicare/models/models.dart';

abstract class JobOfferRepository {
  Future<String> createOffer(JobOffer offer);
  Stream<List<JobOffer>> streamClientOffers(String clientId, {int limit = 10});
  Stream<List<JobOffer>> streamNearbyOffers(double lat, double lng, double maxDistanceKm, {int? limit});
  Future<void> updateOfferStatus(String offerId, JobOfferStatus status, {String? acceptedCaregiverId, String? acceptedApplicationId});
  
  Future<void> applyToOffer(JobApplication application);
  Stream<List<JobApplication>> streamOfferApplications(String offerId, {int limit = 20});
  Future<void> updateApplicationStatus(String offerId, String applicationId, JobApplicationStatus status);
  
  Future<JobOffer?> getOffer(String offerId);
}

