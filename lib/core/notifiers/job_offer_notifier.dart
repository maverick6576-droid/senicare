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
  bool isLoadingClientOffers = false;
  bool _isLoadingMoreClient = false;
  bool _hasMoreClientOffers = false;
  String? clientError;
  Completer<void>? _clientRefreshCompleter;

  bool get hasMoreClientOffers => _hasMoreClientOffers;

  int _nearbyLimit = 15;
  double? _lastLat;
  double? _lastLng;
  double? _lastMaxDistanceKm;
  String? _caregiverId;

  bool get hasMoreNearby => nearbyOffers.length >= _nearbyLimit;

  void initForClient(String clientId, {bool forceRefresh = false}) {
    if (clientId.isEmpty) return;
    if (!forceRefresh && _lastClientId == clientId && _clientSub != null && clientError == null) return;
    _clientLimit = 10;
    _lastClientId = clientId;
    _hasMoreClientOffers = false;
    _isLoadingMoreClient = false;
    isLoadingClientOffers = true;
    clientError = null;
    _subscribeClientOffers();
  }

  Future<void> refreshClientOffers() async {
    if (_lastClientId == null || _lastClientId!.isEmpty) return;
    _clientRefreshCompleter?.complete();
    final completer = Completer<void>();
    _clientRefreshCompleter = completer;

    isLoadingClientOffers = true;
    clientError = null;
    _clientLimit = 10;
    notifyListeners();
    _subscribeClientOffers();

    await completer.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        if (!completer.isCompleted) {
          completer.complete();
        }
        isLoadingClientOffers = false;
        notifyListeners();
      },
    );
  }

  void loadMoreClientOffers() {
    if (_lastClientId == null || !_hasMoreClientOffers || _isLoadingMoreClient) {
      return;
    }
    _isLoadingMoreClient = true;
    _clientLimit += 10;
    notifyListeners();
    _subscribeClientOffers();
  }

  void _subscribeClientOffers() {
    _clientSub?.cancel();
    _clientSub = DependencyInjection.jobOffers
        .streamClientOffers(_lastClientId!, limit: _clientLimit)
        .listen(
      (offers) {
        clientOffers = offers;
        isLoadingClientOffers = false;
        _isLoadingMoreClient = false;
        clientError = null;
        _hasMoreClientOffers = offers.length >= _clientLimit;
        _clientRefreshCompleter?.complete();
        _clientRefreshCompleter = null;

        final activeOfferIds = offers.map((o) => o.id).toSet();
        final staleSubIds = _appSubs.keys.where((id) => !activeOfferIds.contains(id)).toList();
        for (final staleId in staleSubIds) {
          _unsubscribeFromApplications(staleId, notify: false);
        }

        for (final offer in offers) {
          if (offer.status == JobOfferStatus.open || offer.status == JobOfferStatus.inProgress) {
            _subscribeToApplications(offer.id);
          } else {
            _unsubscribeFromApplications(offer.id, notify: false);
          }
        }
        notifyListeners();
      },
      onError: (Object error) {
        isLoadingClientOffers = false;
        _isLoadingMoreClient = false;
        clientError = 'No pudimos cargar tus ofertas. Revisa tu conexión e inténtalo de nuevo.';
        _clientRefreshCompleter?.complete();
        _clientRefreshCompleter = null;
        notifyListeners();
      },
    );
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
    _appSubs[offerId] = DependencyInjection.jobOffers.streamOfferApplications(offerId, limit: 20).listen(
      (apps) {
        applicationsByOffer[offerId] = apps;
        notifyListeners();
      },
      onError: (_) {},
    );
  }

  void _unsubscribeFromApplications(String offerId, {bool notify = true}) {
    final hadSub = _appSubs.containsKey(offerId);
    final hadApps = applicationsByOffer.containsKey(offerId);
    _appSubs[offerId]?.cancel();
    _appSubs.remove(offerId);
    applicationsByOffer.remove(offerId);
    if (notify && (hadSub || hadApps)) {
      notifyListeners();
    }
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
    var appsSnapshot = List<JobApplication>.from(applicationsByOffer[offerId] ?? const []);
    if (appsSnapshot.isEmpty) {
      try {
        appsSnapshot = await DependencyInjection.jobOffers.streamOfferApplications(offerId, limit: 50).first;
      } catch (_) {}
    }

    await DependencyInjection.jobOffers.updateApplicationStatus(offerId, applicationId, JobApplicationStatus.accepted);
    await DependencyInjection.jobOffers.updateOfferStatus(
      offerId,
      JobOfferStatus.inProgress,
      acceptedCaregiverId: caregiverId,
      acceptedApplicationId: applicationId,
    );

    final offerIdx = clientOffers.indexWhere((o) => o.id == offerId);
    if (offerIdx != -1) {
      clientOffers[offerIdx].status = JobOfferStatus.inProgress;
      clientOffers[offerIdx].acceptedCaregiverId = caregiverId;
      clientOffers[offerIdx].acceptedApplicationId = applicationId;
    }

    for (final app in appsSnapshot) {
      if (app.id == applicationId) {
        app.status = JobApplicationStatus.accepted;
      } else if (app.status == JobApplicationStatus.pending) {
        await DependencyInjection.jobOffers.updateApplicationStatus(offerId, app.id, JobApplicationStatus.rejected);
        app.status = JobApplicationStatus.rejected;
      }
    }
    notifyListeners();
  }

  Future<void> rejectApplication(String offerId, String applicationId) async {
    await DependencyInjection.jobOffers.updateApplicationStatus(
      offerId,
      applicationId,
      JobApplicationStatus.rejected,
    );
    final apps = applicationsByOffer[offerId];
    if (apps != null) {
      final idx = apps.indexWhere((a) => a.id == applicationId);
      if (idx != -1) {
        apps[idx].status = JobApplicationStatus.rejected;
        notifyListeners();
      }
    }
  }

  Future<void> cancelOffer(String offerId) async {
    var appsSnapshot = List<JobApplication>.from(applicationsByOffer[offerId] ?? const []);
    if (appsSnapshot.isEmpty) {
      try {
        appsSnapshot = await DependencyInjection.jobOffers.streamOfferApplications(offerId, limit: 50).first;
      } catch (_) {}
    }

    await DependencyInjection.jobOffers.updateOfferStatus(offerId, JobOfferStatus.cancelled);
    final offer = clientOffers.where((o) => o.id == offerId).firstOrNull;
    if (offer != null) {
      offer.status = JobOfferStatus.cancelled;
    }

    for (final app in appsSnapshot) {
      if (app.status == JobApplicationStatus.pending) {
        try {
          await DependencyInjection.jobOffers.updateApplicationStatus(
            offerId,
            app.id,
            JobApplicationStatus.rejected,
          );
          app.status = JobApplicationStatus.rejected;
        } catch (_) {}
      }
    }
    notifyListeners();
  }

  void clear({bool notify = true}) {
    final hadData = clientOffers.isNotEmpty ||
        nearbyOffers.isNotEmpty ||
        myApplications.isNotEmpty ||
        _lastClientId != null ||
        _lastLat != null ||
        clientError != null;
    _clientSub?.cancel();
    _clientSub = null;
    _nearbySub?.cancel();
    _nearbySub = null;
    for (final sub in _appSubs.values) {
      sub.cancel();
    }
    _appSubs.clear();
    _clientRefreshCompleter?.complete();
    _clientRefreshCompleter = null;
    clientOffers = [];
    nearbyOffers = [];
    myApplications = [];
    myApplicationsByOfferId.clear();
    applicationsByOffer.clear();
    _lastClientId = null;
    _clientLimit = 10;
    _lastLat = null;
    _lastLng = null;
    _lastMaxDistanceKm = null;
    _caregiverId = null;
    isLoadingClientOffers = false;
    _isLoadingMoreClient = false;
    _hasMoreClientOffers = false;
    clientError = null;
    isLoadingNearby = false;
    isLoadingMyApplications = false;
    nearbyError = null;
    if (notify && hadData) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _clientRefreshCompleter?.complete();
    _clientRefreshCompleter = null;
    _clientSub?.cancel();
    _nearbySub?.cancel();
    for (final sub in _appSubs.values) {
      sub.cancel();
    }
    super.dispose();
  }
}
