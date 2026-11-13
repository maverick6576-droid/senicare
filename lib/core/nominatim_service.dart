import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:senicare/core/map_config.dart';

/// Servicio de geocodificación y autocompletado con caché en memoria, throttling
/// y soporte prioritario para proveedores comerciales (Geoapify, LocationIQ,
/// MapTiler o instancia privada Nominatim).
class NominatimService {
  static const String _fallbackBaseUrl = 'https://nominatim.openstreetmap.org';
  static const Duration _timeout = Duration(seconds: 8);
  static const Duration _minFallbackInterval = Duration(milliseconds: 350);
  static const int _maxCacheEntries = 100;

  static final Map<String, LatLng> _geocodeCache = {};
  static final Map<String, List<String>> _searchCache = {};
  static final Map<String, String> _reverseCache = {};
  static DateTime _lastFallbackRequestAt = DateTime.fromMillisecondsSinceEpoch(0);

  @visibleForTesting
  static http.Client? testHttpClient;

  @visibleForTesting
  static void clearCacheForTesting() {
    _geocodeCache.clear();
    _searchCache.clear();
    _reverseCache.clear();
    _lastFallbackRequestAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  static void _putBounded<K, V>(Map<K, V> cache, K key, V value) {
    if (cache.length >= _maxCacheEntries && !cache.containsKey(key)) {
      cache.remove(cache.keys.first);
    }
    cache[key] = value;
  }

  static Future<http.Response> _get(Uri uri, {bool isOsmFallback = false}) async {
    if (testHttpClient != null) {
      return testHttpClient!
          .get(uri, headers: {'User-Agent': 'SeniCareApp/1.0 (soporte@senicare.es)'})
          .timeout(_timeout);
    }
    if (isOsmFallback) {
      final elapsed = DateTime.now().difference(_lastFallbackRequestAt);
      if (elapsed < _minFallbackInterval) {
        await Future.delayed(_minFallbackInterval - elapsed);
      }
      _lastFallbackRequestAt = DateTime.now();
    }
    return http
        .get(uri, headers: {'User-Agent': 'SeniCareApp/1.0 (soporte@senicare.es)'})
        .timeout(_timeout);
  }

  /// Convierte una dirección de texto en coordenadas GPS (Latitud, Longitud).
  static Future<LatLng?> geocodeAddress(String address) async {
    final clean = address.trim();
    if (clean.isEmpty) return null;

    final cacheKey = '${MapConfig.geocodingProvider}:${clean.toLowerCase()}';
    if (_geocodeCache.containsKey(cacheKey)) {
      return _geocodeCache[cacheKey];
    }

    try {
      final geoapifyKey = MapConfig.geoapifyApiKey;
      final locationIqKey = MapConfig.locationIqApiKey;
      final mapTilerKey = MapConfig.mapTilerApiKey;
      final customBase = MapConfig.customNominatimBaseUrl;

      LatLng? resolved;
      if (geoapifyKey.isNotEmpty) {
        final uri = Uri.parse(
          'https://api.geoapify.com/v1/geocode/search?text=${Uri.encodeComponent(clean)}&limit=1&lang=es&format=json&apiKey=$geoapifyKey',
        );
        final res = await _get(uri);
        if (res.statusCode == 200) {
          final body = json.decode(res.body) as Map<String, dynamic>;
          final results = (body['results'] as List?) ?? const [];
          if (results.isNotEmpty) {
            final first = results.first as Map<String, dynamic>;
            final lat = (first['lat'] as num?)?.toDouble();
            final lon = (first['lon'] as num?)?.toDouble();
            if (lat != null && lon != null) resolved = LatLng(lat, lon);
          }
        }
      } else if (locationIqKey.isNotEmpty) {
        final uri = Uri.parse(
          'https://eu1.locationiq.com/v1/search?q=${Uri.encodeComponent(clean)}&format=json&limit=1&key=$locationIqKey',
        );
        final res = await _get(uri);
        if (res.statusCode == 200) {
          final data = json.decode(res.body) as List<dynamic>;
          if (data.isNotEmpty) {
            final lat = double.tryParse(data[0]['lat'].toString());
            final lon = double.tryParse(data[0]['lon'].toString());
            if (lat != null && lon != null) resolved = LatLng(lat, lon);
          }
        }
      } else if (mapTilerKey.isNotEmpty) {
        final uri = Uri.parse(
          'https://api.maptiler.com/geocoding/${Uri.encodeComponent(clean)}.json?limit=1&language=es&key=$mapTilerKey',
        );
        final res = await _get(uri);
        if (res.statusCode == 200) {
          final body = json.decode(res.body) as Map<String, dynamic>;
          final features = (body['features'] as List?) ?? const [];
          if (features.isNotEmpty) {
            final center = (features.first as Map<String, dynamic>)['center'] as List?;
            if (center != null && center.length >= 2) {
              final lon = (center[0] as num?)?.toDouble();
              final lat = (center[1] as num?)?.toDouble();
              if (lat != null && lon != null) resolved = LatLng(lat, lon);
            }
          }
        }
      } else {
        final baseUrl = customBase.isNotEmpty ? customBase : _fallbackBaseUrl;
        final uri = Uri.parse(
          '$baseUrl/search?q=${Uri.encodeComponent(clean)}&format=json&limit=1',
        );
        final res = await _get(uri, isOsmFallback: customBase.isEmpty);
        if (res.statusCode == 200) {
          final data = json.decode(res.body) as List<dynamic>;
          if (data.isNotEmpty) {
            final lat = double.tryParse(data[0]['lat'].toString());
            final lon = double.tryParse(data[0]['lon'].toString());
            if (lat != null && lon != null) resolved = LatLng(lat, lon);
          }
        }
      }

      if (resolved != null) {
        _putBounded(_geocodeCache, cacheKey, resolved);
      }
      return resolved;
    } catch (e) {
      debugPrint('Error geocoding: $e');
      return null;
    }
  }

  /// Busca direcciones y devuelve sugerencias (Autocomplete).
  static Future<List<String>> searchAddress(String query) async {
    final clean = query.trim();
    if (clean.length < 3) return [];

    final cacheKey = 'addr:${MapConfig.geocodingProvider}:${clean.toLowerCase()}';
    if (_searchCache.containsKey(cacheKey)) {
      return _searchCache[cacheKey]!;
    }

    try {
      final geoapifyKey = MapConfig.geoapifyApiKey;
      final locationIqKey = MapConfig.locationIqApiKey;
      final mapTilerKey = MapConfig.mapTilerApiKey;
      final customBase = MapConfig.customNominatimBaseUrl;

      List<String> suggestions = [];
      if (geoapifyKey.isNotEmpty) {
        final uri = Uri.parse(
          'https://api.geoapify.com/v1/geocode/autocomplete?text=${Uri.encodeComponent(clean)}&limit=5&filter=countrycode:es&lang=es&format=json&apiKey=$geoapifyKey',
        );
        final res = await _get(uri);
        if (res.statusCode == 200) {
          final body = json.decode(res.body) as Map<String, dynamic>;
          final results = (body['results'] as List?) ?? const [];
          suggestions = results
              .map((r) => (r['formatted'] ?? '').toString())
              .where((s) => s.isNotEmpty)
              .toList();
        }
      } else if (locationIqKey.isNotEmpty) {
        final uri = Uri.parse(
          'https://eu1.locationiq.com/v1/autocomplete?q=${Uri.encodeComponent(clean)}&countrycodes=es&limit=5&format=json&key=$locationIqKey',
        );
        final res = await _get(uri);
        if (res.statusCode == 200) {
          final data = json.decode(res.body) as List<dynamic>;
          suggestions = data
              .map((item) => (item['display_name'] ?? '').toString())
              .where((s) => s.isNotEmpty)
              .toList();
        }
      } else if (mapTilerKey.isNotEmpty) {
        final uri = Uri.parse(
          'https://api.maptiler.com/geocoding/${Uri.encodeComponent(clean)}.json?country=es&limit=5&language=es&key=$mapTilerKey',
        );
        final res = await _get(uri);
        if (res.statusCode == 200) {
          final body = json.decode(res.body) as Map<String, dynamic>;
          final features = (body['features'] as List?) ?? const [];
          suggestions = features
              .map((f) => (f['place_name'] ?? '').toString())
              .where((s) => s.isNotEmpty)
              .toList();
        }
      } else {
        final baseUrl = customBase.isNotEmpty ? customBase : _fallbackBaseUrl;
        final uri = Uri.parse(
          '$baseUrl/search?q=${Uri.encodeComponent(clean)}&format=json&limit=5&countrycodes=es',
        );
        final res = await _get(uri, isOsmFallback: customBase.isEmpty);
        if (res.statusCode == 200) {
          final data = json.decode(res.body) as List<dynamic>;
          suggestions = data
              .map((item) => (item['display_name'] ?? '').toString())
              .where((s) => s.isNotEmpty)
              .toList();
        }
      }

      if (suggestions.isNotEmpty) {
        _putBounded(_searchCache, cacheKey, suggestions);
      }
      return suggestions;
    } catch (e) {
      debugPrint('Error searching address: $e');
      return [];
    }
  }

  /// Autocompletado de ciudades/localidades para formularios de dirección.
  static Future<List<String>> searchCities(
    String query, {
    String? province,
  }) =>
      _searchPlaceTag(
        query: query,
        contextSuffix: province,
        photonTag: 'place',
        geoapifyType: 'city',
        cachePrefix: 'city',
        minLength: 2,
      );

  /// Autocompletado de calles/vías dentro de una localidad o provincia.
  static Future<List<String>> searchStreets(
    String query, {
    String? city,
    String? province,
  }) =>
      _searchPlaceTag(
        query: query,
        contextSuffix: (city != null && city.trim().isNotEmpty) ? city.trim() : province,
        photonTag: 'highway',
        geoapifyType: 'street',
        cachePrefix: 'street',
        minLength: 3,
      );

  static Future<List<String>> _searchPlaceTag({
    required String query,
    required String? contextSuffix,
    required String photonTag,
    required String geoapifyType,
    required String cachePrefix,
    required int minLength,
  }) async {
    final clean = query.trim();
    if (clean.length < minLength) return [];

    final fullQuery = (contextSuffix != null && contextSuffix.trim().isNotEmpty)
        ? '$clean, ${contextSuffix.trim()}'
        : clean;
    final cacheKey = '$cachePrefix:${MapConfig.geocodingProvider}:${fullQuery.toLowerCase()}';
    if (_searchCache.containsKey(cacheKey)) {
      return _searchCache[cacheKey]!;
    }

    try {
      final geoapifyKey = MapConfig.geoapifyApiKey;
      if (geoapifyKey.isNotEmpty) {
        final uri = Uri.parse(
          'https://api.geoapify.com/v1/geocode/autocomplete?text=${Uri.encodeComponent(fullQuery)}&type=$geoapifyType&limit=7&filter=countrycode:es&lang=es&format=json&apiKey=$geoapifyKey',
        );
        final res = await _get(uri);
        if (res.statusCode == 200) {
          final body = json.decode(res.body) as Map<String, dynamic>;
          final results = (body['results'] as List?) ?? const [];
          final names = <String>{
            for (final item in results)
              if ((item[geoapifyType] ?? item['street'] ?? item['city'] ?? item['name'] ?? '')
                  .toString()
                  .isNotEmpty)
                (item[geoapifyType] ?? item['street'] ?? item['city'] ?? item['name']).toString(),
          }.toList();
          if (names.isNotEmpty) _putBounded(_searchCache, cacheKey, names);
          return names;
        }
      }

      if (MapConfig.isCommercialGeocodingConfigured) {
        final raw = await searchAddress(fullQuery);
        final names = raw
            .map((line) => line.split(',').first.trim())
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList();
        if (names.isNotEmpty) _putBounded(_searchCache, cacheKey, names);
        return names;
      }

      final uri = Uri.parse(
        'https://photon.komoot.io/api/?q=${Uri.encodeComponent(fullQuery)}&limit=7&osm_tag=$photonTag',
      );
      final response = await _get(uri, isOsmFallback: true);
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final features = (data['features'] as List?) ?? const [];
        final results = <String>{};
        for (final feature in features) {
          final props = (feature as Map<String, dynamic>)['properties'] as Map<String, dynamic>?;
          final name = props?['name']?.toString();
          if (name != null && name.isNotEmpty) {
            results.add(name);
          }
        }
        final list = results.toList();
        if (list.isNotEmpty) _putBounded(_searchCache, cacheKey, list);
        return list;
      }
      return [];
    } catch (e) {
      debugPrint('Error searching $cachePrefix: $e');
      return [];
    }
  }

  /// Convierte unas coordenadas GPS en una dirección legible.
  static Future<String?> reverseGeocode(double lat, double lon) async {
    final cacheKey =
        '${MapConfig.geocodingProvider}:${lat.toStringAsFixed(4)},${lon.toStringAsFixed(4)}';
    if (_reverseCache.containsKey(cacheKey)) {
      return _reverseCache[cacheKey];
    }

    try {
      final geoapifyKey = MapConfig.geoapifyApiKey;
      final locationIqKey = MapConfig.locationIqApiKey;
      final mapTilerKey = MapConfig.mapTilerApiKey;
      final customBase = MapConfig.customNominatimBaseUrl;

      String? address;
      if (geoapifyKey.isNotEmpty) {
        final uri = Uri.parse(
          'https://api.geoapify.com/v1/geocode/reverse?lat=$lat&lon=$lon&lang=es&format=json&apiKey=$geoapifyKey',
        );
        final res = await _get(uri);
        if (res.statusCode == 200) {
          final body = json.decode(res.body) as Map<String, dynamic>;
          final results = (body['results'] as List?) ?? const [];
          if (results.isNotEmpty) {
            address = (results.first as Map<String, dynamic>)['formatted']?.toString();
          }
        }
      } else if (locationIqKey.isNotEmpty) {
        final uri = Uri.parse(
          'https://eu1.locationiq.com/v1/reverse?lat=$lat&lon=$lon&format=json&key=$locationIqKey',
        );
        final res = await _get(uri);
        if (res.statusCode == 200) {
          final data = json.decode(res.body) as Map<String, dynamic>;
          address = data['display_name']?.toString();
        }
      } else if (mapTilerKey.isNotEmpty) {
        final uri = Uri.parse(
          'https://api.maptiler.com/geocoding/$lon,$lat.json?language=es&key=$mapTilerKey',
        );
        final res = await _get(uri);
        if (res.statusCode == 200) {
          final body = json.decode(res.body) as Map<String, dynamic>;
          final features = (body['features'] as List?) ?? const [];
          if (features.isNotEmpty) {
            address = (features.first as Map<String, dynamic>)['place_name']?.toString();
          }
        }
      } else {
        final baseUrl = customBase.isNotEmpty ? customBase : _fallbackBaseUrl;
        final uri = Uri.parse('$baseUrl/reverse?lat=$lat&lon=$lon&format=json');
        final res = await _get(uri, isOsmFallback: customBase.isEmpty);
        if (res.statusCode == 200) {
          final data = json.decode(res.body) as Map<String, dynamic>;
          address = data['display_name']?.toString();
        }
      }

      if (address != null && address.isNotEmpty) {
        _putBounded(_reverseCache, cacheKey, address);
      }
      return address;
    } catch (e) {
      debugPrint('Error reverse geocoding: $e');
      return null;
    }
  }
}
