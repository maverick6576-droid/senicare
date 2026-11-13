import 'dart:async';
import 'dart:io';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';
import 'package:senicare/screens/admin/admin_lean_startup_tab.dart';
import 'package:senicare/screens/onboarding/live_dni_scanner_screen.dart';
import 'package:senicare/screens/screens.dart';
import 'package:senicare/widgets/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestStatsRepo implements StatsRepository {
  @override
  Future<int> getAccumulatedHours(String clientId, String caregiverId) async => 24;

  @override
  Future<List<Map<String, dynamic>>> getCaregiverClientStats(String caregiverId) async => [
        {'clientId': 'mock_user_123', 'caregiverId': caregiverId, 'accumulatedHours': 24},
      ];

  @override
  Future<void> addCompletedHours(String clientId, String caregiverId, int hoursToAdd) async {}
}

class _SilentHttpOverrides extends HttpOverrides {
  static final Uint8List _transparentPng = Uint8List.fromList(<int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);

  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeHttpClient();
}

class _FakeHttpClient implements HttpClient {
  @override
  bool autoUncompress = true;
  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = const Duration(seconds: 1);
  @override
  int? maxConnectionsPerHost;
  @override
  String? userAgent;

  @override
  void close({bool force = false}) {}
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeHttpClientRequest();
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async => _FakeHttpClientRequest();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _FakeHttpHeaders();
  @override
  Future<HttpClientResponse> close() async => _FakeHttpClientResponse();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpHeaders implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeHttpClientResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  int get statusCode => 200;
  @override
  int get contentLength => _SilentHttpOverrides._transparentPng.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([_SilentHttpOverrides._transparentPng]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  setUpAll(() {
    AppTheme.useSystemFonts = true;
    ClientTutorialService.useLocalFileStorage = false;
    CaregiverTutorialService.useLocalFileStorage = false;
    HttpOverrides.global = _SilentHttpOverrides();
  });

  tearDownAll(() {
    AppTheme.useSystemFonts = true;
  });

  void resetDI() {
    DependencyInjection.auth = MockAuthRepository();
    DependencyInjection.caregivers = MockCaregiverRepository();
    DependencyInjection.bookings = MockBookingRepository();
    DependencyInjection.chats = MockChatRepository();
    DependencyInjection.stats = _TestStatsRepo();
    DependencyInjection.reviews = MockReviewRepository();
    DependencyInjection.reports = MockReportRepository();
    DependencyInjection.clients = MockClientRepository();
    DependencyInjection.jobOffers = MockJobOfferRepository();
    DependencyInjection.families = MockFamilyRepository();
  }

  Widget wrapWithProviders(
    Widget child, {
    AuthNotifier? auth,
    ConfigNotifier? config,
    BookingNotifier? booking,
    CaregiverNotifier? caregiver,
    LocationNotifier? location,
    ChatNotifier? chat,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthNotifier>.value(value: auth ?? AuthNotifier()),
        ChangeNotifierProvider<ConfigNotifier>.value(value: config ?? ConfigNotifier()),
        ChangeNotifierProvider<BookingNotifier>.value(value: booking ?? BookingNotifier()),
        ChangeNotifierProvider<CaregiverNotifier>.value(value: caregiver ?? CaregiverNotifier()),
        ChangeNotifierProvider<LocationNotifier>.value(value: location ?? LocationNotifier()),
        ChangeNotifierProvider<ChatNotifier>.value(value: chat ?? ChatNotifier()),
      ],
      child: Consumer<ConfigNotifier>(
        builder: (context, cfg, _) {
          return MaterialApp(
            locale: cfg.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: AppTheme.getTheme(cfg.seniorMode),
            home: child,
          );
        },
      ),
    );
  }

  Future<AuthNotifier> signUpTestUser(
    WidgetTester tester, {
    required String email,
    required String role,
    required Map<String, dynamic> extra,
  }) async {
    final auth = AuthNotifier();
    await DependencyInjection.auth.signUpWithEmail(email, 'Secret123!', role, extra);
    await tester.pump(const Duration(milliseconds: 50));
    await auth.reloadRole();
    await tester.pump(const Duration(milliseconds: 50));
    return auth;
  }

  Future<AuthNotifier> createSignedInCaregiverAuth(WidgetTester tester) =>
      signUpTestUser(
        tester,
        email: 'cuidador.test@senicare.es',
        role: 'caregiver',
        extra: const {'name': 'Laura Cuidadora', 'pricePerHour': 18.0},
      );

  Booking makeActiveBooking() {
    final now = DateTime.now();
    final start = now.subtract(const Duration(minutes: 10));
    final end = now.add(const Duration(hours: 2));
    return Booking(
      id: 'bk_active_1',
      clientId: 'cli_1',
      caregiverId: 'cg_1',
      caregiverName: 'Laura Cuidadora',
      day: DateFormat('yyyy-MM-dd').format(start),
      slot: '${DateFormat('HH:mm').format(start)}-${DateFormat('HH:mm').format(end)}',
      bookingPin: '4321',
      status: BookingStatus.confirmed,
      cost: 36.0,
      clientFee: 1.08,
      caregiverCommissionRate: 0.18,
      caregiverCommissionAmount: 6.48,
      caregiverPayout: 29.52,
      totalPaid: 37.08,
    );
  }

  group('Previously Uncovered Screens & Widgets', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      MapConfig.testEnvOverrides = null;
      resetDI();
    });

    testWidgets('CaregiverDashboard renders summary, availability CTA and client hours', (tester) async {
      final auth = await createSignedInCaregiverAuth(tester);
      final bookingNotifier = BookingNotifier();
      bookingNotifier.updateAuth(auth.currentUserId, 'caregiver');

      await tester.pumpWidget(
        wrapWithProviders(
          const Scaffold(body: CaregiverDashboard()),
          auth: auth,
          booking: bookingNotifier,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Hola,'), findsOneWidget);
      expect(find.text('Tu Disponibilidad'), findsOneWidget);
    });

    testWidgets('CaregiverCalendarScreen loads and renders slots for authenticated caregiver', (tester) async {
      final auth = await createSignedInCaregiverAuth(tester);
      await tester.pumpWidget(
        wrapWithProviders(
          const CaregiverCalendarScreen(),
          auth: auth,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(CaregiverCalendarScreen), findsOneWidget);
      expect(find.text('Mi Calendario de Horarios'), findsOneWidget);
    });

    testWidgets('CaregiverOnboardingScreen renders multi-step wizard without errors', (tester) async {
      final auth = await createSignedInCaregiverAuth(tester);
      await tester.pumpWidget(
        wrapWithProviders(
          const CaregiverOnboardingScreen(),
          auth: auth,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(CaregiverOnboardingScreen), findsOneWidget);
      expect(find.byType(TextFormField), findsWidgets);
    });

    testWidgets('IdentityVerificationScreen shows DNI and Criminal Record steps for caregiver', (tester) async {
      final auth = await createSignedInCaregiverAuth(tester);
      await tester.pumpWidget(
        wrapWithProviders(
          const IdentityVerificationScreen(),
          auth: auth,
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Verificación de Identidad'), findsOneWidget);
      expect(find.text('Paso 1: Documento de Identidad'), findsOneWidget);
      expect(find.text('Paso 2: Certificado de Penales / Delitos Sexuales'), findsOneWidget);
    });

    testWidgets('LiveDniScannerScreen handles missing camera gracefully on headless VM', (tester) async {
      const channels = [
        MethodChannel('plugins.flutter.io/camera'),
        MethodChannel('plugins.flutter.io/camera_android'),
      ];
      for (final channel in channels) {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'availableCameras') return <dynamic>[];
          return null;
        });
        addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    ctx,
                    MaterialPageRoute(builder: (_) => const LiveDniScannerScreen()),
                  );
                },
                child: const Text('Abrir Escáner'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir Escáner'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 5));

      expect(find.byType(LiveDniScannerScreen), findsNothing);
      expect(find.text('Abrir Escáner'), findsOneWidget);
    });

    testWidgets('ScannerScreen switches to PIN tab and completes check-in dialog in mock mode', (tester) async {
      final booking = makeActiveBooking();
      await DependencyInjection.bookings.createBooking(booking);

      await tester.pumpWidget(
        wrapWithProviders(
          ScannerScreen(booking: booking),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Fichar Llegada'), findsOneWidget);
      await tester.tap(find.text('Código PIN'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '4321');
      await tester.tap(find.text('Validar PIN'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('¡Llegada Verificada!'), findsOneWidget);
    });

    testWidgets('MapScreen renders FlutterMap with commercial MapConfig tile URL & attribution', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', (ByteData? message) async {
        final key = message == null
            ? ''
            : String.fromCharCodes(
                message.buffer.asUint8List(message.offsetInBytes, message.lengthInBytes),
              );
        if (key.endsWith('.png')) {
          return ByteData.sublistView(
            Uint8List.fromList(_SilentHttpOverrides._transparentPng),
          );
        }
        if (key.endsWith('.json')) {
          return ByteData.sublistView(Uint8List.fromList('{}'.codeUnits));
        }
        return const StandardMessageCodec().encodeMessage(<Object?, Object?>{});
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', null));

      MapConfig.testEnvOverrides = {'GEOAPIFY_API_KEY': 'geo_demo_key'};
      await tester.pumpWidget(
        wrapWithProviders(
          const MapScreen(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final tileLayer = tester.widget<TileLayer>(find.byType(TileLayer));
      expect(tileLayer.urlTemplate, contains('maps.geoapify.com'));
      final attributionWidget =
          tester.widget<RichAttributionWidget>(find.byType(RichAttributionWidget));
      final firstAttribution = attributionWidget.attributions.first as TextSourceAttribution;
      expect(firstAttribution.text, 'Powered by Geoapify | © OpenStreetMap contributors');
    });

    testWidgets('AdminDashboard & AdminLeanStartupTab render all tabs and empty/populated metrics safely', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeDb = FakeFirebaseFirestore();
      await fakeDb.collection('caregivers').doc('cg_pending_1').set({
        'name': 'Pedro Pendiente',
        'title': 'Auxiliar',
        'verificationStatus': 'pending',
      });
      await fakeDb.collection('admins').doc('maverick6576@gmail.com').set({
        'email': 'maverick6576@gmail.com',
        '2faEnabled': true,
      });

      await tester.pumpWidget(
        wrapWithProviders(
          AdminDashboard(firestore: fakeDb),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Admin Panel'), findsOneWidget);
      expect(find.text('Lean Startup'), findsOneWidget);
      expect(find.text('Validaciones'), findsOneWidget);

      await tester.tap(find.text('Validaciones'));
      await tester.pumpAndSettle();
      expect(find.text('Pedro Pendiente'), findsOneWidget);

      // Stand-alone AdminLeanStartupTab with empty FakeFirebaseFirestore (verifies avgCac == 0 guard)
      final emptyDb = FakeFirebaseFirestore();
      await tester.pumpWidget(
        wrapWithProviders(
          Scaffold(body: AdminLeanStartupTab(firestore: emptyDb)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AdminLeanStartupTab), findsOneWidget);
    });

    testWidgets('VideoCallModal renders Jitsi interview modal and triggers onCallEnded on close', (tester) async {
      bool ended = false;
      await tester.pumpWidget(
        MaterialApp(
          home: VideoCallModal(
            peerName: 'Ana Cuidadora',
            roomId: 'room_42',
            onCallEnded: () => ended = true,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Entrevista WebRTC Cifrada (Jitsi)'), findsOneWidget);
      expect(find.textContaining('Ana Cuidadora'), findsOneWidget);
      expect(find.text('Sala privada lista para unirte'), findsOneWidget);
      expect(find.text('Abrir Videollamada Segura'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(ended, isTrue);
    });

    testWidgets('ReviewDialog renders 4 rating categories and submits feedback', (tester) async {
      final auth = await signUpTestUser(
        tester,
        email: 'fam@senicare.es',
        role: 'client',
        extra: const {'name': 'Familia Díaz'},
      );
      final booking = makeActiveBooking();
      await DependencyInjection.bookings.createBooking(booking);

      await tester.pumpWidget(
        wrapWithProviders(
          Scaffold(
            body: ReviewDialog(bookings: [booking]),
          ),
          auth: auth,
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Valorar Servicio'), findsOneWidget);
      expect(find.text('Puntualidad y asistencia'), findsOneWidget);
      expect(find.text('Trato humano y empatía'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Cuidadora muy atenta y puntual.');
      await tester.pump();
      await tester.tap(find.text('Enviar Valoración'));
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('ReportDialog submits incident report via BookingNotifier', (tester) async {
      final auth = await signUpTestUser(
        tester,
        email: 'fam@senicare.es',
        role: 'client',
        extra: const {'name': 'Familia Ruiz'},
      );
      final booking = makeActiveBooking();

      await tester.pumpWidget(
        wrapWithProviders(
          Scaffold(
            body: ReportDialog(booking: booking),
          ),
          auth: auth,
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Reportar Incidente'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Incidencia puntual durante el turno.');
      await tester.tap(find.text('Enviar Reporte'));
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('SettingsScreen toggles Senior Mode & switches language with SharedPreferences persistence', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final config = ConfigNotifier();
      await config.loadPreferences();
      final auth = await signUpTestUser(
        tester,
        email: 'fam.prefs@senicare.es',
        role: 'client',
        extra: const {'name': 'Familia Soler'},
      );

      await tester.pumpWidget(
        wrapWithProviders(
          const SettingsScreen(),
          auth: auth,
          config: config,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final englishChip = find.text('English');
      await tester.scrollUntilVisible(englishChip, 200);
      await tester.tap(englishChip);
      await tester.pump(const Duration(milliseconds: 200));
      expect(config.locale.languageCode, 'en');

      final seniorToggle = find.text('Activar Modo Senior (Letra Grande)');
      await tester.scrollUntilVisible(seniorToggle, 200);
      await tester.tap(seniorToggle);
      await tester.pump(const Duration(milliseconds: 200));
      expect(config.seniorMode, isTrue);

      final reloadedConfig = ConfigNotifier();
      await reloadedConfig.loadPreferences();
      expect(reloadedConfig.seniorMode, isTrue);
      expect(reloadedConfig.locale.languageCode, 'en');
    });
  });
}
