import 'package:flutter/material.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/core/core.dart';

enum CaregiverSortOption {
  recommended,
  ratingDesc,
  priceAsc,
  priceDesc,
  distanceAsc,
}

class CaregiverNotifier extends ChangeNotifier {
  static const List<String> _specialtyCatalog = [
    'Todos',
    'Compañía',
    'Movilidad',
    'Cocina Médica',
    'Soporte Digital',
    'Alzheimer',
    'Demencia',
    'Post-operatorio',
  ];

  List<CaregiverProfile> caregivers = [];
  bool isFetchingCaregivers = false;
  bool hasMoreCaregivers = true;
  String? errorMessage;

  String selectedSpecialty = 'Todos';
  String searchQuery = '';

  // Sorting and filtering states
  CaregiverSortOption sortOption = CaregiverSortOption.recommended;
  double maxPriceFilter = 50.0;
  double minRatingFilter = 0.0;
  bool ignoreDistanceLimit = false;

  double? _clientLatitude;
  double? _clientLongitude;
  int _fetchGeneration = 0;

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

  double? get clientLatitude => _clientLatitude;
  double? get clientLongitude => _clientLongitude;

  bool get hasCustomFilters =>
      selectedSpecialty != 'Todos' ||
      searchQuery.trim().isNotEmpty ||
      sortOption != CaregiverSortOption.recommended ||
      maxPriceFilter < 50.0 ||
      minRatingFilter > 0.0 ||
      ignoreDistanceLimit;

  int get activeFilterSheetCount {
    int count = 0;
    if (sortOption != CaregiverSortOption.recommended) count++;
    if (maxPriceFilter < 50.0) count++;
    if (minRatingFilter > 0.0) count++;
    if (ignoreDistanceLimit) count++;
    return count;
  }

  void setSortOption(CaregiverSortOption option) {
    sortOption = option;
    notifyListeners();
  }

  void setMaxPriceFilter(double price) {
    maxPriceFilter = price.clamp(6.0, 50.0);
    notifyListeners();
  }

  void setMinRatingFilter(double rating) {
    minRatingFilter = rating.clamp(0.0, 5.0);
    notifyListeners();
  }

  void setIgnoreDistanceLimit(bool value) {
    if (ignoreDistanceLimit != value) {
      ignoreDistanceLimit = value;
      notifyListeners();
    }
  }

  void resetFilters() {
    sortOption = CaregiverSortOption.recommended;
    maxPriceFilter = 50.0;
    minRatingFilter = 0.0;
    ignoreDistanceLimit = false;
    notifyListeners();
  }

  void resetAllFilters() {
    final needsRefetch = selectedSpecialty != 'Todos' || searchQuery.isNotEmpty;
    selectedSpecialty = 'Todos';
    searchQuery = '';
    sortOption = CaregiverSortOption.recommended;
    maxPriceFilter = 50.0;
    minRatingFilter = 0.0;
    ignoreDistanceLimit = false;
    if (needsRefetch) {
      _fetchInitialCaregivers();
    } else {
      notifyListeners();
    }
  }

  List<String> get availableSpecialties => _specialtyCatalog;

  List<CaregiverProfile> _filterAndSort({required bool applyDistanceRadius}) {
    final normalizedQuery = searchQuery.trim().toLowerCase();

    final filtered = caregivers.where((c) {
      if (c.verificationStatus != 'approved') return false;

      final matchesSpecialty =
          selectedSpecialty == 'Todos' || c.specialties.contains(selectedSpecialty);

      final matchesSearch = normalizedQuery.isEmpty ||
          c.name.toLowerCase().contains(normalizedQuery) ||
          c.title.toLowerCase().contains(normalizedQuery) ||
          c.bio.toLowerCase().contains(normalizedQuery) ||
          c.homeAddress.toLowerCase().contains(normalizedQuery) ||
          c.specialties.any((s) => s.toLowerCase().contains(normalizedQuery));

      // Treating 50.0 as "Sin límite" ensures higher-rate specialists stay visible by default.
      final matchesPrice = maxPriceFilter >= 50.0 || c.pricePerHour <= maxPriceFilter;
      final matchesRating = c.rating >= minRatingFilter;

      bool matchesDistance = true;
      if (applyDistanceRadius &&
          !ignoreDistanceLimit &&
          _clientLatitude != null &&
          _clientLongitude != null &&
          c.latitude != null &&
          c.longitude != null) {
        final dist = calculateDistance(
          _clientLatitude!,
          _clientLongitude!,
          c.latitude!,
          c.longitude!,
        );
        if (dist > c.maxDistanceRadius) {
          matchesDistance = false;
        }
      }

      return matchesSpecialty &&
          matchesSearch &&
          matchesDistance &&
          matchesPrice &&
          matchesRating;
    }).toList();

    switch (sortOption) {
      case CaregiverSortOption.ratingDesc:
        filtered.sort((a, b) {
          final cmp = b.rating.compareTo(a.rating);
          return cmp != 0 ? cmp : b.reviewsCount.compareTo(a.reviewsCount);
        });
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
                : 9999.0;
            final distB = (b.latitude != null && b.longitude != null)
                ? calculateDistance(_clientLatitude!, _clientLongitude!, b.latitude!, b.longitude!)
                : 9999.0;
            return distA.compareTo(distB);
          });
        }
        break;
      case CaregiverSortOption.recommended:
        filtered.sort((a, b) {
          if (a.isKycVerified != b.isKycVerified) {
            return a.isKycVerified ? -1 : 1;
          }
          if (a.isSuperCaregiver != b.isSuperCaregiver) {
            return a.isSuperCaregiver ? -1 : 1;
          }
          final ratingCmp = b.rating.compareTo(a.rating);
          return ratingCmp != 0 ? ratingCmp : b.reviewsCount.compareTo(a.reviewsCount);
        });
        break;
    }

    return filtered;
  }

  List<CaregiverProfile> get filteredCaregivers =>
      _filterAndSort(applyDistanceRadius: true);

  /// Caregivers visible on the interactive map: keeps search/specialty/price/rating
  /// filters without hiding caregivers in another city outside home radius.
  List<CaregiverProfile> get caregiversForMap =>
      _filterAndSort(applyDistanceRadius: false);

  void toggleSpecialty(String specialty) {
    final next = (selectedSpecialty == specialty && specialty != 'Todos')
        ? 'Todos'
        : specialty;
    setSpecialty(next);
  }

  void setSpecialty(String specialty) {
    final normalized =
        _specialtyCatalog.contains(specialty) ? specialty : 'Todos';
    if (selectedSpecialty == normalized && caregivers.isNotEmpty) return;
    selectedSpecialty = normalized;
    _fetchInitialCaregivers();
  }

  void setSearchQuery(String query) {
    searchQuery = query;
    _fetchInitialCaregivers();
  }

  Future<void> fetchNearMapLocation(double mapLat, double mapLng) async {
    await _fetchInitialCaregivers(mapLat: mapLat, mapLng: mapLng);
  }

  Future<void> _fetchInitialCaregivers({double? mapLat, double? mapLng}) async {
    final gen = ++_fetchGeneration;
    isFetchingCaregivers = true;
    errorMessage = null;
    hasMoreCaregivers = true;
    notifyListeners();

    try {
      final results = await DependencyInjection.caregivers.fetchCaregivers(
        specialty: selectedSpecialty,
        query: searchQuery.trim(),
        refresh: true,
        mapLat: mapLat,
        mapLng: mapLng,
      );
      if (gen != _fetchGeneration) return;

      final seenIds = <String>{};
      final deduped = <CaregiverProfile>[];
      for (final c in results) {
        if (seenIds.add(c.id)) {
          deduped.add(c);
        }
      }
      caregivers = deduped;
      hasMoreCaregivers = results.length >= 20;
    } catch (e) {
      if (gen != _fetchGeneration) return;
      errorMessage = 'No se pudieron cargar los cuidadores. Revisa tu conexión e inténtalo de nuevo.';
      debugPrint('Error fetching caregivers: $e');
    } finally {
      if (gen == _fetchGeneration) {
        isFetchingCaregivers = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMoreCaregivers({double? mapLat, double? mapLng}) async {
    if (isFetchingCaregivers || !hasMoreCaregivers) return;
    final gen = _fetchGeneration;
    isFetchingCaregivers = true;
    notifyListeners();

    try {
      final newCaregivers = await DependencyInjection.caregivers.fetchCaregivers(
        specialty: selectedSpecialty,
        query: searchQuery.trim(),
        refresh: false,
        mapLat: mapLat,
        mapLng: mapLng,
      );
      if (gen != _fetchGeneration) return;

      final existingIds = caregivers.map((c) => c.id).toSet();
      int added = 0;
      for (final c in newCaregivers) {
        if (existingIds.add(c.id)) {
          caregivers.add(c);
          added++;
        }
      }
      if (added == 0 || newCaregivers.length < 20) {
        hasMoreCaregivers = false;
      }
    } catch (e) {
      if (gen != _fetchGeneration) return;
      debugPrint('Error loading more caregivers: $e');
    } finally {
      if (gen == _fetchGeneration) {
        isFetchingCaregivers = false;
        notifyListeners();
      }
    }
  }

  void updateCaregiverProfileLocal(CaregiverProfile updatedProfile) {
    final index = caregivers.indexWhere((c) => c.id == updatedProfile.id);
    if (index != -1) {
      caregivers[index] = updatedProfile;
      notifyListeners();
    }
  }
}

