import 'package:flutter/material.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/core/core.dart';

enum CaregiverSortOption { recommended, ratingDesc, priceAsc, priceDesc, distanceAsc }

class CaregiverNotifier extends ChangeNotifier {
  List<CaregiverProfile> caregivers = [];
  bool isFetchingCaregivers = false;
  String selectedSpecialty = 'Todos';
  String searchQuery = '';
  
  // New sorting and filtering states
  CaregiverSortOption sortOption = CaregiverSortOption.recommended;
  double maxPriceFilter = 50.0;
  double minRatingFilter = 0.0;
  
  double? _clientLatitude;
  double? _clientLongitude;

  CaregiverNotifier() {
    _fetchInitialCaregivers();
  }

  Future<void> refreshCaregivers() async {
    await _fetchInitialCaregivers();
  }

  void updateLocation(double? lat, double? lng) {
    if (_clientLatitude != lat || _clientLongitude != lng) {
      _clientLatitude = lat;
      _clientLongitude = lng;
      notifyListeners();
    }
  }

  void setSortOption(CaregiverSortOption option) {
    sortOption = option;
    notifyListeners();
  }

  void setMaxPriceFilter(double price) {
    maxPriceFilter = price;
    notifyListeners();
  }

  void setMinRatingFilter(double rating) {
    minRatingFilter = rating;
    notifyListeners();
  }

  void resetFilters() {
    sortOption = CaregiverSortOption.recommended;
    maxPriceFilter = 50.0;
    minRatingFilter = 0.0;
    notifyListeners();
  }

  List<String> get availableSpecialties => ['Todos', 'Compañía', 'Movilidad', 'Cocina Médica', 'Soporte Digital'];

  List<CaregiverProfile> get filteredCaregivers {
    // 1. Filtrar la lista
    final filtered = caregivers.where((c) {
      if (c.verificationStatus != 'approved') return false;

      final matchesSpecialty = selectedSpecialty == 'Todos' || c.specialties.contains(selectedSpecialty);
      final matchesSearch = c.name.toLowerCase().contains(searchQuery.toLowerCase()) || 
                            c.title.toLowerCase().contains(searchQuery.toLowerCase());
                            
      // Filtros de precio y valoración
      final matchesPrice = c.pricePerHour <= maxPriceFilter;
      final matchesRating = c.rating >= minRatingFilter;

      bool matchesDistance = true;
      if (_clientLatitude != null && _clientLongitude != null && c.latitude != null && c.longitude != null) {
        final dist = calculateDistance(_clientLatitude!, _clientLongitude!, c.latitude!, c.longitude!);
        if (dist > c.maxDistanceRadius) {
          matchesDistance = false;
        }
      }
      
      final isVerified = c.verificationStatus == 'approved';
      
      return matchesSpecialty && matchesSearch && matchesDistance && isVerified && matchesPrice && matchesRating;
    }).toList();

    // 2. Ordenar la lista filtrada
    switch (sortOption) {
      case CaregiverSortOption.ratingDesc:
        filtered.sort((a, b) => b.rating.compareTo(a.rating));
        break;
      case CaregiverSortOption.priceAsc:
        filtered.sort((a, b) => a.pricePerHour.compareTo(b.pricePerHour));
        break;
      case CaregiverSortOption.priceDesc:
        filtered.sort((a, b) => b.pricePerHour.compareTo(a.pricePerHour));
        break;
      case CaregiverSortOption.distanceAsc:
        if (_clientLatitude != null && _clientLongitude != null) {
          filtered.sort((a, b) {
            final distA = (a.latitude != null && a.longitude != null) 
                ? calculateDistance(_clientLatitude!, _clientLongitude!, a.latitude!, a.longitude!)
                : 999.0;
            final distB = (b.latitude != null && b.longitude != null)
                ? calculateDistance(_clientLatitude!, _clientLongitude!, b.latitude!, b.longitude!)
                : 999.0;
            return distA.compareTo(distB);
          });
        }
        break;
      case CaregiverSortOption.recommended:
        // Recomendados ordena primero por verificación de Stripe KYC, luego por puntuación
        filtered.sort((a, b) {
          if (a.isKycVerified && !b.isKycVerified) return -1;
          if (!a.isKycVerified && b.isKycVerified) return 1;
          return b.rating.compareTo(a.rating);
        });
        break;
    }

    return filtered;
  }

  void setSpecialty(String specialty) {
    selectedSpecialty = specialty;
    _fetchInitialCaregivers();
  }

  void setSearchQuery(String query) {
    searchQuery = query;
    _fetchInitialCaregivers();
  }

  Future<void> _fetchInitialCaregivers({double? mapLat, double? mapLng}) async {
    isFetchingCaregivers = true;
    notifyListeners();
    
    caregivers = await DependencyInjection.caregivers.fetchCaregivers(
      specialty: selectedSpecialty, 
      query: searchQuery, 
      refresh: true,
      mapLat: mapLat,
      mapLng: mapLng
    );
    
    isFetchingCaregivers = false;
    notifyListeners();
  }

  Future<void> loadMoreCaregivers({double? mapLat, double? mapLng}) async {
    if (isFetchingCaregivers) return;
    isFetchingCaregivers = true;
    notifyListeners();
    
    final newCaregivers = await DependencyInjection.caregivers.fetchCaregivers(
      specialty: selectedSpecialty, 
      query: searchQuery, 
      refresh: false,
      mapLat: mapLat,
      mapLng: mapLng
    );
    
    if (newCaregivers.isNotEmpty) {
      caregivers.addAll(newCaregivers);
    }
    
    isFetchingCaregivers = false;
    notifyListeners();
  }

  void updateCaregiverProfileLocal(CaregiverProfile updatedProfile) {
    final index = caregivers.indexWhere((c) => c.id == updatedProfile.id);
    if (index != -1) {
      caregivers[index] = updatedProfile;
      notifyListeners();
    }
  }
}

