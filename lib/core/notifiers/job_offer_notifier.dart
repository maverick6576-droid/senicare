import 'package:flutter/material.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/core/core.dart';
import 'dart:async';

class JobOfferNotifier extends ChangeNotifier {
  List<JobOffer> clientOffers = [];
  List<JobOffer> nearbyOffers = [];
  
  StreamSubscription? _clientSub;
  StreamSubscription? _nearbySub;

  final Map<String, List<JobApplication>> applicationsByOffer = {};
  final Map<String, StreamSubscription> _appSubs = {};

  bool isCreating = false;

  int _clientLimit = 10;
  String? _lastClientId;

  int _nearbyLimit = 15;
  double? _lastLat;
  double? _lastLng;
  double? _lastMaxDistanceKm;

  void initForClient(String clientId) {
    if (_lastClientId == clientId) return;
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
    _clientSub = DependencyInjection.jobOffers.streamClientOffers(_lastClientId!, limit: _clientLimit).listen((offers) {
      clientOffers = offers;
      notifyListeners();
      
      for (var offer in offers) {
        if (offer.status == JobOfferStatus.open || offer.status == JobOfferStatus.inProgress) {
          _subscribeToApplications(offer.id);
        } else {
          _unsubscribeFromApplications(offer.id);
        }
      }
    });
  }

  void initForCaregiver(double lat, double lng, double maxDistanceKm) {
    if (_lastLat == lat && _lastLng == lng && _lastMaxDistanceKm == maxDistanceKm) return;
    _nearbyLimit = 15;
    _lastLat = lat;
    _lastLng = lng;
    _lastMaxDistanceKm = maxDistanceKm;
    _subscribeNearbyOffers();
  }

  void loadMoreNearbyOffers() {
    if (_lastLat != null && _lastLng != null && _lastMaxDistanceKm != null) {
      _nearbyLimit += 15;
      _subscribeNearbyOffers();
    }
  }

  void _subscribeNearbyOffers() {
    _nearbySub?.cancel();
    _nearbySub = DependencyInjection.jobOffers.streamNearbyOffers(_lastLat!, _lastLng!, _lastMaxDistanceKm!, limit: _nearbyLimit).listen((offers) {
      nearbyOffers = offers;
      notifyListeners();
    });
  }

  void _subscribeToApplications(String offerId) {
    if (_appSubs.containsKey(offerId)) return;
    // Límite de 20 solicitudes
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

  Future<void> applyToOffer(JobApplication application) async {
    await DependencyInjection.jobOffers.applyToOffer(application);
  }

  Future<void> acceptApplication(String offerId, String applicationId, String caregiverId) async {
    await DependencyInjection.jobOffers.updateApplicationStatus(offerId, applicationId, JobApplicationStatus.accepted);
    await DependencyInjection.jobOffers.updateOfferStatus(offerId, JobOfferStatus.inProgress, acceptedCaregiverId: caregiverId, acceptedApplicationId: applicationId);
    
    final apps = applicationsByOffer[offerId] ?? [];
    for (var app in apps) {
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

  @override
  void dispose() {
    _clientSub?.cancel();
    _nearbySub?.cancel();
    for (var sub in _appSubs.values) {
      sub.cancel();
    }
    super.dispose();
  }
}