import 'dart:async';
import 'package:flutter/material.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';

class CaregiverOfferApplication {
  final JobOffer offer;
  final JobApplication application;

  const CaregiverOfferApplication({
    required this.offer,
    required this.application,
  });
}

class JobOfferNotifier extends ChangeNotifier {
  List<JobOffer> clientOffers = [];
  List<JobOffer> nearbyOffers = [];
  List<CaregiverOfferApplication> myApplications = [];
  final Map<String, JobApplication> myApplicationsByOfferId = {};

  StreamSubscription? _clientSub;
  StreamSubscription? _nearbySub;

  final Map<String, List<JobApplication>> applicationsByOffer = {};
  final Map<String, StreamSubscription> _appSubs = {};

  bool isCreating = false;
  bool isLoadingNearby = false;
  bool isLoadingMyApplications = false;
  String? nearbyError;

  int _clientLimit = 10;
  String? _lastClientId;

  int _nearbyLimit = 15;
  double? _lastLat;
  double? _lastLng;
  double? _lastMaxDistanceKm;
  String? _caregiverId;

  bool get hasMoreNearby => nearbyOffers.length >= _nearbyLimit;

  void initForClient(String clientId, {bool forceRefresh = false}) {
    if (clientId.isEmpty) return;
    if (!forceRefresh && _lastClientId == clientId && _clientSub != null) return;
    _clientLimit = 10;
    _lastClientId = clientId;
    _subscribeClientOffers();
  }

  void loadMoreClientOffers() {
    if (_lastClientId != null) {
      _clientLimit += 10;
      _subscribeClientOffers();
    }
  }

  void _subscribeClientOffers() {
    _clientSub?.cancel();
    _clientSub = DependencyInjection.jobOffers
        .streamClientOffers(_lastClientId!, limit: _clientLimit)
        .listen((offers) {
      clientOffers = offers;
      notifyListeners();

      for (final offer in offers) {
        if (offer.status == JobOfferStatus.open || offer.status == JobOfferStatus.inProgress) {
          _subscribeToApplications(offer.id);
        } else {
          _unsubscribeFromApplications(offer.id);
        }
      }
    });
  }

  void initForCaregiver(
    double lat,
    double lng,
    double maxDistanceKm, {
    String? caregiverId,
    bool forceRefresh = false,
  }) {
    final normalizedCaregiverId = (caregiverId != null && caregiverId.isNotEmpty) ? caregiverId : _caregiverId;
    final caregiverChanged = normalizedCaregiverId != _caregiverId;
    _caregiverId = normalizedCaregiverId;

    final sameLocation = _lastLat == lat && _lastLng == lng && _lastMaxDistanceKm == maxDistanceKm;
    if (!forceRefresh && sameLocation && _nearbySub != null) {
      if (caregiverChanged && _caregiverId != null) {
        Future.microtask(() => refreshMyApplications(_caregiverId));
      }
      return;
    }

    _nearbyLimit = 15;
    _lastLat = lat;
    _lastLng = lng;
    _lastMaxDistanceKm = maxDistanceKm;
    _subscribeNearbyOffers(notifyStart: forceRefresh);
  }

  Future<void> refreshNearbyOffers(
    double lat,
    double lng,
    double maxDistanceKm, {
    String? caregiverId,
  }) async {
    initForCaregiver(
      lat,
      lng,
      maxDistanceKm,
      caregiverId: caregiverId,
      forceRefresh: true,
    );
    await refreshMyApplications(caregiverId ?? _caregiverId);
  }

  void loadMoreNearbyOffers() {
    if (isLoadingNearby || !hasMoreNearby) return;
    if (_lastLat != null && _lastLng != null && _lastMaxDistanceKm != null) {
      _nearbyLimit += 15;
      _subscribeNearbyOffers(notifyStart: true);
    }
  }

  void _subscribeNearbyOffers({bool notifyStart = false}) {
    _nearbySub?.cancel();
    isLoadingNearby = true;
    nearbyError = null;
    if (notifyStart) notifyListeners();

    _nearbySub = DependencyInjection.jobOffers
        .streamNearbyOffers(_lastLat!, _lastLng!, _lastMaxDistanceKm!, limit: _nearbyLimit)
        .listen(
      (offers) {
        nearbyOffers = offers;
        isLoadingNearby = false;
        nearbyError = null;
        notifyListeners();
        if (_caregiverId != null && _caregiverId!.isNotEmpty) {
          refreshMyApplications(_caregiverId);
        }
      },
      onError: (e) {
        isLoadingNearby = false;
        nearbyError = 'No se pudieron cargar las ofertas cercanas. Inténtalo de nuevo.';
        debugPrint('Error streaming nearby offers: $e');
        notifyListeners();
      },
    );
  }

  Future<void> refreshMyApplications([String? caregiverId]) async {
    final cid = (caregiverId != null && caregiverId.isNotEmpty) ? caregiverId : _caregiverId;
    if (cid == null || cid.isEmpty) return;
    _caregiverId = cid;

    await Future.microtask(() {});
    isLoadingMyApplications = true;
    notifyListeners();

    try {
      final candidateIds = {
        ...nearbyOffers.map((o) => o.id),
        ...myApplicationsByOfferId.keys,
      }.toList();

      final rawEntries = await DependencyInjection.jobOffers.fetchCaregiverApplications(
        cid,
        candidateOfferIds: candidateIds,
      );

      final mapped = rawEntries
          .map((e) => CaregiverOfferApplication(offer: e.key, application: e.value))
          .toList();

      mapped.sort((a, b) {
        int rank(CaregiverOfferApplication item) {
          if (item.application.status == JobApplicationStatus.accepted) return 0;
          if (item.application.status == JobApplicationStatus.pending &&
              item.offer.status == JobOfferStatus.open &&
              !item.offer.isExpired) {
            return 1;
          }
          return 2;
        }

        final rA = rank(a);
        final rB = rank(b);
        if (rA != rB) return rA.compareTo(rB);
        if (rA == 1) return a.offer.startDate.compareTo(b.offer.startDate);
        return b.application.appliedAt.compareTo(a.application.appliedAt);
      });

      myApplications = mapped;
      myApplicationsByOfferId
        ..clear()
        ..addEntries(mapped.map((e) => MapEntry(e.offer.id, e.application)));
    } finally {
      isLoadingMyApplications = false;
      notifyListeners();
    }
  }

  void _subscribeToApplications(String offerId) {
    if (_appSubs.containsKey(offerId)) return;
    _appSubs[offerId] = DependencyInjection.jobOffers.streamOfferApplications(offerId, limit: 20).listen((apps) {
      applicationsByOffer[offerId] = apps;
      notifyListeners();
    });
  }

  void _unsubscribeFromApplications(String offerId) {
    _appSubs[offerId]?.cancel();
    _appSubs.remove(offerId);
    applicationsByOffer.remove(offerId);
    notifyListeners();
  }

  Future<void> createOffer(JobOffer offer) async {
    isCreating = true;
    notifyListeners();
    try {
      await DependencyInjection.jobOffers.createOffer(offer);
    } finally {
      isCreating = false;
      notifyListeners();
    }
  }

  Future<void> applyToOffer(JobApplication application, {JobOffer? offer}) async {
    await DependencyInjection.jobOffers.applyToOffer(application);
    myApplicationsByOfferId[application.offerId] = application;

    final existingIdx = myApplications.indexWhere((e) => e.offer.id == application.offerId);
    final resolvedOffer = offer ??
        nearbyOffers.where((o) => o.id == application.offerId).firstOrNull;
    if (resolvedOffer != null) {
      final entry = CaregiverOfferApplication(offer: resolvedOffer, application: application);
      if (existingIdx != -1) {
        myApplications[existingIdx] = entry;
      } else {
        myApplications.insert(0, entry);
      }
    }
    notifyListeners();
    unawaited(refreshMyApplications(application.caregiverId));
  }

  Future<void> updateApplication(
    String offerId,
    String applicationId, {
    required String message,
    required double proposedPrice,
    String? caregiverId,
  }) async {
    await DependencyInjection.jobOffers.updateApplicationDetails(
      offerId,
      applicationId,
      message: message,
      proposedPrice: proposedPrice,
    );
    await refreshMyApplications(caregiverId ?? _caregiverId);
  }

  Future<void> withdrawApplication(
    String offerId,
    String applicationId,
    String caregiverId,
  ) async {
    await DependencyInjection.jobOffers.withdrawApplication(offerId, applicationId, caregiverId);
    myApplicationsByOfferId.remove(offerId);
    myApplications.removeWhere((e) => e.offer.id == offerId);
    notifyListeners();
  }

  Future<void> acceptApplication(String offerId, String applicationId, String caregiverId) async {
    await DependencyInjection.jobOffers.updateApplicationStatus(offerId, applicationId, JobApplicationStatus.accepted);
    await DependencyInjection.jobOffers.updateOfferStatus(
      offerId,
      JobOfferStatus.inProgress,
      acceptedCaregiverId: caregiverId,
      acceptedApplicationId: applicationId,
    );

    final apps = applicationsByOffer[offerId] ?? [];
    for (final app in apps) {
      if (app.id != applicationId && app.status == JobApplicationStatus.pending) {
        await DependencyInjection.jobOffers.updateApplicationStatus(offerId, app.id, JobApplicationStatus.rejected);
      }
    }
  }

  Future<void> cancelOffer(String offerId) async {
    await DependencyInjection.jobOffers.updateOfferStatus(offerId, JobOfferStatus.cancelled);
    final offer = clientOffers.where((o) => o.id == offerId).firstOrNull;
    if (offer != null) {
      offer.status = JobOfferStatus.cancelled;
      notifyListeners();
    }
  }

  void clear({bool notify = true}) {
    final hadData = clientOffers.isNotEmpty ||
        nearbyOffers.isNotEmpty ||
        myApplications.isNotEmpty ||
        _lastClientId != null ||
        _lastLat != null;
    _clientSub?.cancel();
    _clientSub = null;
    _nearbySub?.cancel();
    _nearbySub = null;
    for (final sub in _appSubs.values) {
      sub.cancel();
    }
    _appSubs.clear();
    clientOffers = [];
    nearbyOffers = [];
    myApplications = [];
    myApplicationsByOfferId.clear();
    applicationsByOffer.clear();
    _lastClientId = null;
    _lastLat = null;
    _lastLng = null;
    _lastMaxDistanceKm = null;
    _caregiverId = null;
    isLoadingNearby = false;
    isLoadingMyApplications = false;
    nearbyError = null;
    if (notify && hadData) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _clientSub?.cancel();
    _nearbySub?.cancel();
    for (final sub in _appSubs.values) {
      sub.cancel();
    }
    super.dispose();
  }
}
