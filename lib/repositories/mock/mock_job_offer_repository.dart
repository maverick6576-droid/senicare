import 'dart:async';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';
import 'package:senicare/core/globals.dart';

class MockJobOfferRepository implements JobOfferRepository {
  final List<JobOffer> _offers = [];
  final Map<String, List<JobApplication>> _applications = {};
  
  final _offersController = StreamController<List<JobOffer>>.broadcast();
  final Map<String, StreamController<List<JobApplication>>> _appsControllers = {};

  void _notifyOffers() {
    _offersController.add(List.from(_offers));
  }

  void _notifyApps(String offerId) {
    if (_appsControllers.containsKey(offerId)) {
      _appsControllers[offerId]!.add(List.from(_applications[offerId] ?? []));
    }
  }

  @override
  Future<String> createOffer(JobOffer offer) async {
    final newOffer = JobOffer(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      clientId: offer.clientId,
      clientName: offer.clientName,
      clientLatitude: offer.clientLatitude,
      clientLongitude: offer.clientLongitude,
      title: offer.title,
      description: offer.description,
      pricePerHour: offer.pricePerHour,
      totalHours: offer.totalHours,
      isRecurring: offer.isRecurring,
      recurringDaysOfWeek: offer.recurringDaysOfWeek,
      recurringHoursPerDay: offer.recurringHoursPerDay,
      recurringWeeks: offer.recurringWeeks,
      recurringStartTime: offer.recurringStartTime,
      startDate: offer.startDate,
      endDate: offer.endDate,
      status: offer.status,
      isUrgent: offer.isUrgent,
      urgencyBonusRate: offer.urgencyBonusRate,
      clientFeeRate: offer.clientFeeRate,
      createdAt: offer.createdAt,
    );
    _offers.add(newOffer);
    _notifyOffers();
    return newOffer.id;
  }

  @override
  Stream<List<JobOffer>> streamClientOffers(String clientId, {int limit = 10}) async* {
    yield _offers.where((o) => o.clientId == clientId).toList();
    yield* _offersController.stream.map((list) => list.where((o) => o.clientId == clientId).toList());
  }

  @override
  Stream<List<JobOffer>> streamNearbyOffers(double lat, double lng, double maxDistanceKm, {int? limit}) async* {
    List<JobOffer> filter(List<JobOffer> list) {
      var filtered = list.where((o) {
        if (o.status != JobOfferStatus.open) return false;
        final dist = calculateDistance(lat, lng, o.clientLatitude, o.clientLongitude);
        return dist <= maxDistanceKm;
      }).toList();
      return limit != null ? filtered.take(limit).toList() : filtered;
    }
    yield filter(_offers);
    yield* _offersController.stream.map((list) => filter(list));
  }

  @override
  Future<void> updateOfferStatus(String offerId, JobOfferStatus status, {String? acceptedCaregiverId, String? acceptedApplicationId}) async {
    final idx = _offers.indexWhere((o) => o.id == offerId);
    if (idx != -1) {
      _offers[idx].status = status;
      if (acceptedCaregiverId != null) _offers[idx].acceptedCaregiverId = acceptedCaregiverId;
      if (acceptedApplicationId != null) _offers[idx].acceptedApplicationId = acceptedApplicationId;
      _notifyOffers();
    }
  }

  @override
  Future<void> applyToOffer(JobApplication application) async {
    final offerId = application.offerId;
    if (!_applications.containsKey(offerId)) {
      _applications[offerId] = [];
      _appsControllers[offerId] = StreamController<List<JobApplication>>.broadcast();
    }
    
    final newApp = JobApplication(
      id: application.id.isNotEmpty ? application.id : '${DateTime.now().microsecondsSinceEpoch}_${application.caregiverId}',
      offerId: application.offerId,
      caregiverId: application.caregiverId,
      caregiverName: application.caregiverName,
      caregiverImageUrl: application.caregiverImageUrl,
      caregiverRating: application.caregiverRating,
      caregiverReviewsCount: application.caregiverReviewsCount,
      message: application.message,
      proposedPrice: application.proposedPrice,
      status: application.status,
      appliedAt: application.appliedAt,
    );
    
    _applications[offerId]!.add(newApp);
    _notifyApps(offerId);
  }

  @override
  Stream<List<JobApplication>> streamOfferApplications(String offerId, {int limit = 20}) async* {
    if (!_applications.containsKey(offerId)) {
      _applications[offerId] = [];
      _appsControllers[offerId] = StreamController<List<JobApplication>>.broadcast();
    }
    yield List.from(_applications[offerId]!);
    yield* _appsControllers[offerId]!.stream;
  }

  @override
  Future<void> updateApplicationStatus(String offerId, String applicationId, JobApplicationStatus status) async {
    if (_applications.containsKey(offerId)) {
      final apps = _applications[offerId]!;
      final idx = apps.indexWhere((a) => a.id == applicationId);
      if (idx != -1) {
        apps[idx].status = status;
        _notifyApps(offerId);
      }
    }
  }

  @override
  Future<JobOffer?> getOffer(String offerId) async {
    try {
      return _offers.firstWhere((o) => o.id == offerId);
    } catch (e) {
      return null;
    }
  }

  void clear() {
    _offers.clear();
    _applications.clear();
  }
}

