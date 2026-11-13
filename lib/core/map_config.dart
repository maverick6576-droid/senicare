import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Proveedor de configuración comercial para tiles de mapa y geocodificación.
///
/// Evita infringir las políticas de uso gratuito de `tile.openstreetmap.org` y
/// `nominatim.openstreetmap.org` permitiendo configurar MapTiler, Geoapify,
/// LocationIQ o un servidor propio mediante `.env` o `--dart-define`.
class MapConfig {
  static const String _envTileUrl = String.fromEnvironment('MAP_TILE_URL');
  static const String _envMapTilerKey = String.fromEnvironment('MAPTILER_API_KEY');
  static const String _envGeoapifyKey = String.fromEnvironment('GEOAPIFY_API_KEY');
  static const String _envLocationIqKey = String.fromEnvironment('LOCATIONIQ_API_KEY');
  static const String _envNominatimUrl = String.fromEnvironment('NOMINATIM_BASE_URL');

  @visibleForTesting
  static Map<String, String>? testEnvOverrides;

  static String _readConfig(String key, String dartDefineFallback) {
    final testVal = testEnvOverrides?[key];
    if (testVal != null && testVal.trim().isNotEmpty) return testVal.trim();
    if (dartDefineFallback.trim().isNotEmpty) return dartDefineFallback.trim();
    try {
      if (dotenv.isInitialized) {
        final envVal = dotenv.env[key];
        if (envVal != null && envVal.trim().isNotEmpty) return envVal.trim();
      }
    } catch (_) {}
    return '';
  }

  static String get mapTilerApiKey => _readConfig('MAPTILER_API_KEY', _envMapTilerKey);
  static String get geoapifyApiKey => _readConfig('GEOAPIFY_API_KEY', _envGeoapifyKey);
  static String get locationIqApiKey => _readConfig('LOCATIONIQ_API_KEY', _envLocationIqKey);
  static String get customTileUrl => _readConfig('MAP_TILE_URL', _envTileUrl);
  static String get customNominatimBaseUrl => _readConfig('NOMINATIM_BASE_URL', _envNominatimUrl);

  static bool get isCommercialTileConfigured =>
      customTileUrl.isNotEmpty || mapTilerApiKey.isNotEmpty || geoapifyApiKey.isNotEmpty;

  static bool get isCommercialGeocodingConfigured =>
      customNominatimBaseUrl.isNotEmpty ||
      geoapifyApiKey.isNotEmpty ||
      locationIqApiKey.isNotEmpty ||
      mapTilerApiKey.isNotEmpty;

  /// Plantilla de tiles activa. En producción prioriza proveedor comercial.
  static String get tileUrlTemplate {
    if (customTileUrl.isNotEmpty) return customTileUrl;
    if (mapTilerApiKey.isNotEmpty) {
      return 'https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}.png?key=$mapTilerApiKey';
    }
    if (geoapifyApiKey.isNotEmpty) {
      return 'https://maps.geoapify.com/v1/tile/osm-carto/{z}/{x}/{y}.png?apiKey=$geoapifyApiKey';
    }
    if (kReleaseMode) {
      debugPrint(
        'MapConfig WARNING: Sin MAP_TILE_URL / MAPTILER_API_KEY / GEOAPIFY_API_KEY en release; usando fallback OSM solo para desarrollo.',
      );
    }
    return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  }

  /// Etiqueta legal de atribución del mapa según el proveedor activo.
  static String get tileAttribution {
    if (mapTilerApiKey.isNotEmpty || customTileUrl.contains('maptiler')) {
      return '© MapTiler © OpenStreetMap contributors';
    }
    if (geoapifyApiKey.isNotEmpty || customTileUrl.contains('geoapify')) {
      return 'Powered by Geoapify | © OpenStreetMap contributors';
    }
    return '© OpenStreetMap contributors';
  }

  /// Nombre descriptivo del proveedor de geocoding activo.
  static String get geocodingProvider {
    if (customNominatimBaseUrl.isNotEmpty) return 'custom_nominatim';
    if (geoapifyApiKey.isNotEmpty) return 'geoapify';
    if (locationIqApiKey.isNotEmpty) return 'locationiq';
    if (mapTilerApiKey.isNotEmpty) return 'maptiler';
    return 'osm_dev_fallback';
  }
}
