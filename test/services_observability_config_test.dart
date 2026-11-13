import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:senicare/core/core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingHttpClient extends http.BaseClient {
  int requestCount = 0;
  Uri? lastUri;
  final String Function(Uri uri) bodyBuilder;

  _RecordingHttpClient({
    required this.bodyBuilder,
  });

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestCount++;
    lastUri = request.url;
    final bytes = utf8.encode(bodyBuilder(request.url));
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([bytes]),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
}

void main() {
  group('ObservabilityService', () {
    setUp(() {
      ObservabilityService.resetForTesting();
    });

    tearDown(() {
      ObservabilityService.resetForTesting();
    });

    test('initializes safely without Firebase and records diagnostics into bounded log', () async {
      await ObservabilityService.initialize(firebaseReady: false);
      expect(ObservabilityService.isInitialized, isTrue);
      expect(ObservabilityService.isCrashlyticsActive, isFalse);
      expect(ObservabilityService.isAnalyticsActive, isFalse);
      expect(ObservabilityService.analyticsObserver, isNull);

      ObservabilityService.recordFlutterError(
        FlutterErrorDetails(exception: StateError('widget_err')),
      );
      final handled = ObservabilityService.recordPlatformError(
        ArgumentError('async_err'),
        StackTrace.current,
      );
      expect(handled, isTrue);

      await ObservabilityService.recordNonFatalError(
        Exception('non_fatal_test'),
        StackTrace.current,
        reason: 'unit_test',
      );
      await ObservabilityService.logEvent('booking_started', parameters: {'source': 'test'});
      await ObservabilityService.setUserContext(userId: 'uid_123', role: 'client', seniorMode: true);

      final log = ObservabilityService.recentEventLog;
      expect(log, anyElement(contains('flutter_error:Bad state: widget_err')));
      expect(log, anyElement(contains('platform_error:Invalid argument(s): async_err')));
      expect(log, anyElement(contains('non_fatal:unit_test')));
      expect(log, contains('event:booking_started'));
      expect(log, contains('user_context:set:client'));
    });

    test('caps recentEventLog buffer at 50 entries', () async {
      await ObservabilityService.initialize(firebaseReady: false);
      for (int i = 0; i < 65; i++) {
        await ObservabilityService.logEvent('evt_$i');
      }
      expect(ObservabilityService.recentEventLog.length, 50);
      expect(ObservabilityService.recentEventLog.first, 'event:evt_15');
      expect(ObservabilityService.recentEventLog.last, 'event:evt_64');
    });
  });

  group('MapConfig & NominatimService', () {
    setUp(() {
      MapConfig.testEnvOverrides = null;
      NominatimService.testHttpClient = null;
      NominatimService.clearCacheForTesting();
    });

    tearDown(() {
      MapConfig.testEnvOverrides = null;
      NominatimService.testHttpClient = null;
      NominatimService.clearCacheForTesting();
    });

    test('selects commercial tile & geocoding providers and attributions properly', () {
      expect(MapConfig.isCommercialTileConfigured, isFalse);
      expect(MapConfig.isCommercialGeocodingConfigured, isFalse);
      expect(MapConfig.geocodingProvider, 'osm_dev_fallback');
      expect(MapConfig.tileAttribution, contains('OpenStreetMap'));

      MapConfig.testEnvOverrides = {'MAPTILER_API_KEY': 'mt_key_123'};
      expect(MapConfig.isCommercialTileConfigured, isTrue);
      expect(MapConfig.isCommercialGeocodingConfigured, isTrue);
      expect(MapConfig.geocodingProvider, 'maptiler');
      expect(MapConfig.tileUrlTemplate, contains('api.maptiler.com'));
      expect(MapConfig.tileUrlTemplate, contains('mt_key_123'));
      expect(MapConfig.tileAttribution, contains('MapTiler'));

      MapConfig.testEnvOverrides = {'GEOAPIFY_API_KEY': 'geo_key_456'};
      expect(MapConfig.geocodingProvider, 'geoapify');
      expect(MapConfig.tileUrlTemplate, contains('maps.geoapify.com'));
      expect(MapConfig.tileAttribution, contains('Geoapify'));

      MapConfig.testEnvOverrides = {'LOCATIONIQ_API_KEY': 'liq_key_789'};
      expect(MapConfig.geocodingProvider, 'locationiq');
      expect(MapConfig.isCommercialGeocodingConfigured, isTrue);
    });

    test('NominatimService uses Geoapify commercial geocoding and caches responses', () async {
      MapConfig.testEnvOverrides = {'GEOAPIFY_API_KEY': 'geo_test'};
      final client = _RecordingHttpClient(
        bodyBuilder: (uri) {
          if (uri.path.contains('/search')) {
            return json.encode({
              'results': [
                {'lat': 41.3874, 'lon': 2.1686},
              ],
            });
          }
          if (uri.path.contains('/reverse')) {
            return json.encode({
              'results': [
                {'formatted': 'Plaça de Catalunya, Barcelona'},
              ],
            });
          }
          if (uri.path.contains('/autocomplete')) {
            if (uri.queryParameters['type'] == 'city') {
              return json.encode({
                'results': [
                  {'city': 'Barcelona'},
                  {'city': 'Badalona'},
                ],
              });
            }
            return json.encode({
              'results': [
                {'street': 'Carrer de Balmes', 'formatted': 'Carrer de Balmes, Barcelona'},
              ],
            });
          }
          return '{}';
        },
      );
      NominatimService.testHttpClient = client;

      final pos1 = await NominatimService.geocodeAddress('Plaça Catalunya, Barcelona');
      final pos2 = await NominatimService.geocodeAddress('Plaça Catalunya, Barcelona');
      expect(pos1, const LatLng(41.3874, 2.1686));
      expect(pos2, const LatLng(41.3874, 2.1686));
      expect(client.requestCount, 1);

      final rev = await NominatimService.reverseGeocode(41.3874, 2.1686);
      expect(rev, 'Plaça de Catalunya, Barcelona');
      expect(client.requestCount, 2);

      final cities = await NominatimService.searchCities('Bar', province: 'Barcelona');
      expect(cities, ['Barcelona', 'Badalona']);

      final streets = await NominatimService.searchStreets('Balmes', city: 'Barcelona');
      expect(streets, ['Carrer de Balmes']);

      final suggestions = await NominatimService.searchAddress('Carrer de Balmes');
      expect(suggestions, ['Carrer de Balmes, Barcelona']);
    });

    test('NominatimService falls back cleanly to OSM/Photon format in dev mode', () async {
      final client = _RecordingHttpClient(
        bodyBuilder: (uri) {
          if (uri.host.contains('photon.komoot.io')) {
            return json.encode({
              'features': [
                {
                  'properties': {'name': 'Gran Via'},
                },
              ],
            });
          }
          return json.encode([
            {'lat': '40.4168', 'lon': '-3.7038', 'display_name': 'Puerta del Sol, Madrid'},
          ]);
        },
      );
      NominatimService.testHttpClient = client;

      final pos = await NominatimService.geocodeAddress('Puerta del Sol, Madrid');
      expect(pos, const LatLng(40.4168, -3.7038));

      final streets = await NominatimService.searchStreets('Gran Via', city: 'Madrid');
      expect(streets, ['Gran Via']);
    });
  });

  group('ConfigNotifier persistence & AppLocalizations', () {
    test('persists seniorMode and locale via SharedPreferences across instances', () async {
      SharedPreferences.setMockInitialValues({});
      final config1 = ConfigNotifier();
      await config1.loadPreferences();
      expect(config1.hasLoadedPreferences, isTrue);
      expect(config1.seniorMode, isFalse);
      expect(config1.locale.languageCode, 'es');

      await config1.toggleSeniorMode(true);
      await config1.setLocale(const Locale('ca', 'ES'));

      final config2 = ConfigNotifier();
      await config2.loadPreferences();
      expect(config2.seniorMode, isTrue);
      expect(config2.locale.languageCode, 'ca');
      expect(config2.locale.countryCode, 'ES');

      await config2.setLocale(const Locale('en'));
      final config3 = ConfigNotifier();
      await config3.loadPreferences();
      expect(config3.locale.languageCode, 'en');
    });

    test('AppLocalizations resolves es, ca, and en navigation strings', () {
      const es = AppLocalizations(Locale('es', 'ES'));
      const ca = AppLocalizations(Locale('ca', 'ES'));
      const en = AppLocalizations(Locale('en', 'US'));

      expect(es.tabExplore, 'Explorar');
      expect(es.tabBookings, 'Reservas');
      expect(ca.tabBookings, 'Reserves');
      expect(ca.tabInbox, 'Missatges');
      expect(en.tabExplore, 'Explore');
      expect(en.tabBookings, 'Bookings');
      expect(en.tabSettings, 'Profile');
      expect(AppLocalizations.delegate.isSupported(const Locale('ca')), isTrue);
      expect(AppLocalizations.delegate.isSupported(const Locale('en')), isTrue);
      expect(AppLocalizations.delegate.isSupported(const Locale('es')), isTrue);
    });
  });

  group('LocationNotifier', () {
    test('falls back gracefully to Barcelona coordinates when platform location fails', () async {
      final notifier = LocationNotifier();
      await notifier.initLocation();
      expect(notifier.latitude, closeTo(41.3851, 0.001));
      expect(notifier.longitude, closeTo(2.1734, 0.001));
    });
  });
}
