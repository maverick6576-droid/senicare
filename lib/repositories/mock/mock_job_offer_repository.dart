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
    List<JobOffer> filter(List<JobOffer> source) {
      final list = source.where((o) => o.clientId == clientId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list.take(limit).toList();
    }

    yield filter(_offers);
    yield* _offersController.stream.map(filter);
  }

  @override
  Stream<List<JobOffer>> streamNearbyOffers(double lat, double lng, double maxDistanceKm, {int? limit}) async* {
    List<JobOffer> filter(List<JobOffer> list) {
      final matches = <({JobOffer offer, double distance})>[];
      for (final o in list) {
        if (o.status != JobOfferStatus.open || o.isExpired) continue;
        final dist = calculateDistance(lat, lng, o.clientLatitude, o.clientLongitude);
        if (dist <= maxDistanceKm) {
          matches.add((offer: o, distance: dist));
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

    final existingIdx = _applications[offerId]!.indexWhere((a) => a.caregiverId == application.caregiverId);
    if (existingIdx != -1) {
      final existing = _applications[offerId]![existingIdx];
      if (existing.status != JobApplicationStatus.pending) {
        throw Exception('Ya existe una resolución para esta oferta.');
      }
      _applications[offerId]![existingIdx] = JobApplication(
        id: existing.id,
        offerId: existing.offerId,
        caregiverId: existing.caregiverId,
        caregiverName: application.caregiverName,
        caregiverImageUrl: application.caregiverImageUrl,
        caregiverRating: application.caregiverRating,
        caregiverReviewsCount: application.caregiverReviewsCount,
        message: application.message,
        proposedPrice: application.proposedPrice,
        status: existing.status,
        appliedAt: application.appliedAt,
      );
      _notifyApps(offerId);
      return;
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
  Stream<JobApplication?> streamCaregiverApplicationForOffer(String offerId, String caregiverId) async* {
    if (caregiverId.isEmpty) {
      yield null;
      return;
    }
    if (!_applications.containsKey(offerId)) {
      _applications[offerId] = [];
      _appsControllers[offerId] = StreamController<List<JobApplication>>.broadcast();
    }
    JobApplication? findApp(List<JobApplication> list) {
      for (final a in list) {
        if (a.caregiverId == caregiverId) return a;
      }
      return null;
    }

    yield findApp(_applications[offerId]!);
    yield* _appsControllers[offerId]!.stream.map(findApp);
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
  Future<void> updateApplicationDetails(
    String offerId,
    String applicationId, {
    required String message,
    required double proposedPrice,
  }) async {
    if (_applications.containsKey(offerId)) {
      final apps = _applications[offerId]!;
      final idx = apps.indexWhere((a) => a.id == applicationId);
      if (idx != -1) {
        final old = apps[idx];
        apps[idx] = JobApplication(
          id: old.id,
          offerId: old.offerId,
          caregiverId: old.caregiverId,
          caregiverName: old.caregiverName,
          caregiverImageUrl: old.caregiverImageUrl,
          caregiverRating: old.caregiverRating,
          caregiverReviewsCount: old.caregiverReviewsCount,
          message: message,
          proposedPrice: proposedPrice,
          status: old.status,
          appliedAt: DateTime.now(),
        );
        _notifyApps(offerId);
      }
    }
  }

  @override
  Future<void> withdrawApplication(String offerId, String applicationId, String caregiverId) async {
    if (_applications.containsKey(offerId)) {
      _applications[offerId]!.removeWhere((a) => a.id == applicationId || a.caregiverId == caregiverId);
      _notifyApps(offerId);
    }
  }

  @override
  Future<List<MapEntry<JobOffer, JobApplication>>> fetchCaregiverApplications(
    String caregiverId, {
    List<String> candidateOfferIds = const [],
  }) async {
    final result = <MapEntry<JobOffer, JobApplication>>[];
    for (final offer in _offers) {
      final apps = _applications[offer.id] ?? [];
      for (final app in apps) {
        if (app.caregiverId == caregiverId) {
          result.add(MapEntry(offer, app));
        }
      }
    }
    return result;
  }

  @override
  Stream<JobOffer?> streamOffer(String offerId) async* {
    JobOffer? find() {
      for (final o in _offers) {
        if (o.id == offerId) return o;
      }
      return null;
    }

    yield find();
    yield* _offersController.stream.map((_) => find());
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

