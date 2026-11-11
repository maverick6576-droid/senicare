import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class NominatimService {
  static const String _baseUrl = 'https://nominatim.openstreetmap.org';
  static const Duration _timeout = Duration(seconds: 8);

  /// Convierte una dirección de texto en coordenadas GPS (Latitud, Longitud)
  static Future<LatLng?> geocodeAddress(String address) async {
    try {
      final uri = Uri.parse('$_baseUrl/search?q=${Uri.encodeComponent(address)}&format=json&limit=1');
      // Nominatim requires a User-Agent header to avoid being blocked
      final response = await http
          .get(uri, headers: {'User-Agent': 'SeniCareApp/1.0 (senicare@flutter.dev)'})
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (data.isNotEmpty) {
          final lat = double.tryParse(data[0]['lat'].toString());
          final lon = double.tryParse(data[0]['lon'].toString());
          if (lat != null && lon != null) {
            return LatLng(lat, lon);
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error geocoding: $e');
      return null;
    }
  }

  /// Busca direcciones y devuelve una lista de sugerencias (Autocomplete)
  static Future<List<String>> searchAddress(String query) async {
    if (query.isEmpty) return [];
    try {
      final uri = Uri.parse('$_baseUrl/search?q=${Uri.encodeComponent(query)}&format=json&limit=5&countrycodes=es');
      final response = await http
          .get(uri, headers: {'User-Agent': 'SeniCareApp/1.0 (senicare@flutter.dev)'})
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((item) => item['display_name'].toString()).toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error searching address: $e');
      return [];
    }
  }

  /// Convierte unas coordenadas GPS en una dirección legible
  static Future<String?> reverseGeocode(double lat, double lon) async {
    try {
      final uri = Uri.parse('$_baseUrl/reverse?lat=$lat&lon=$lon&format=json');
      final response = await http
          .get(uri, headers: {'User-Agent': 'SeniCareApp/1.0 (senicare@flutter.dev)'})
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['display_name'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint('Error reverse geocoding: $e');
      return null;
    }
  }
}
