import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class LocationNotifier extends ChangeNotifier {
  double? latitude;
  double? longitude;
  Position? currentLocation;

  LocationNotifier() {
    _fetchClientLocation();
  }

  Future<void> initLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _setFallback();
        return;
      }
      
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _setFallback();
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _setFallback();
        return;
      }
      
      currentLocation = await Geolocator.getCurrentPosition();
      latitude = currentLocation!.latitude;
      longitude = currentLocation!.longitude;
      notifyListeners();
    } catch (e) {
      debugPrint('Error getting location: $e');
      _setFallback();
    }
  }

  void _fetchClientLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _setFallback();
        return;
      }
      
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _setFallback();
          return;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        _setFallback();
        return;
      }
      
      Position position = await Geolocator.getCurrentPosition();
      latitude = position.latitude;
      longitude = position.longitude;
      notifyListeners();
    } catch (e) {
      debugPrint('Error getting location: $e');
      _setFallback();
    }
  }

  void _setFallback() {
    latitude = 41.3851;
    longitude = 2.1734;
    notifyListeners();
  }
}
