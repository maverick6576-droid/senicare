import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';
import 'package:senicare/screens/screens.dart';

class _AuditStatsRepo implements StatsRepository {
  @override
  Future<int> getAccumulatedHours(String clientId, String caregiverId) async =>
      36;

  @override
  Future<List<Map<String, dynamic>>> getCaregiverClientStats(
          String caregiverId) async =>
      [
        {
          'clientId': 'cli_audit_1',
          'caregiverId': caregiverId,
          'accumulatedHours': 36,
        },
        {
          'clientId': 'cli_audit_2',
          'caregiverId': caregiverId,
          'accumulatedHours': 112,
        },
      ];

  @override
  Future<void> addCompletedHours(
      String clientId, String caregiverId, int hoursToAdd) async {}
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
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _FakeHttpClientRequest();
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

class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
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
    return Stream<List<int>>.fromIterable(
            [_SilentHttpOverrides._transparentPng])
        .listen(
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

  void resetDI() {
    DependencyInjection.auth = MockAuthRepository();
    DependencyInjection.caregivers = MockCaregiverRepository();
    DependencyInjection.bookings = MockBookingRepository();
    DependencyInjection.chats = MockChatRepository();
    DependencyInjection.stats = _AuditStatsRepo();
    DependencyInjection.reviews = MockReviewRepository();
    DependencyInjection.reports = MockReportRepository();
    DependencyInjection.clients = MockClientRepository();
    DependencyInjection.jobOffers = MockJobOfferRepository();
    DependencyInjection.families = MockFamilyRepository();
  }

  void setCompactViewport15x(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
  }

  Widget wrapSenior15x(
    Widget child, {
    required AuthNotifier auth,
    required ConfigNotifier config,
    required BookingNotifier booking,
  }) {
    config.seniorMode = true;
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthNotifier>.value(value: auth),
        ChangeNotifierProvider<ConfigNotifier>.value(value: config),
        ChangeNotifierProvider<BookingNotifier>.value(value: booking),
        ChangeNotifierProvider<CaregiverNotifier>(
            create: (_) => CaregiverNotifier()),
        ChangeNotifierProvider<LocationNotifier>(
            create: (_) => LocationNotifier()),
        ChangeNotifierProvider<ChatNotifier>(create: (_) => ChatNotifier()),
      ],
      child: MediaQuery(
        data: const MediaQueryData(
          size: Size(360, 800),
          textScaler: TextScaler.linear(1.5),
        ),
        child: MaterialApp(
          locale: const Locale('es', 'ES'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.getTheme(true),
          home: child,
        ),
      ),
    );
  }

  Future<void> verifyWcagContrastAndNoOverflow(WidgetTester tester) async {
    final err = tester.takeException();
    if (err != null) {
      final details = err is FlutterError ? err.toStringDeep() : '$err';
      fail('Unexpected exception/overflow:\n$details');
    }
    final handle = tester.ensureSemantics();
    try {
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    } finally {
      handle.dispose();
    }
  }

  group('Senior Mode + 1.5x Text Scale + WCAG AA Audit (360x800)', () {
    testWidgets(
        'PaymentScreen (4h+ pack, custom checklist, Escudo modal) renders with 0 overflows and passes WCAG AA',
        (tester) async {
      resetDI();
      setCompactViewport15x(tester);

      final auth = AuthNotifier();
      await DependencyInjection.auth.signUpWithEmail(
        'familia.audit@senicare.es',
        'Secret123!',
        'client',
        const {'name': 'Carmen Martínez Ruiz'},
      );
      await tester.pump(const Duration(milliseconds: 50));
      await auth.reloadRole();
      final uid = auth.currentUserId ?? 'cli_audit_1';
      await DependencyInjection.clients.updateClient(uid, {
        'defaultCareChecklist': [
          '💊 Control de medicación a las 10:00',
          '🚶 Paseo tranquilo por el parque',
        ],
      });
      await auth.reloadRole();

      final caregiver = CaregiverProfile(
        id: 'cg_audit_1',
        name: 'María Elena Rodríguez García',
        title: 'Auxiliar de Enfermería Geriátrica',
        bio: 'Auxiliar de enfermería geriátrica con 10 años de experiencia.',
        imageUrl: '',
        pricePerHour: 16.50,
        rating: 4.9,
        reviewsCount: 28,
        distance: '1.2 km',
        specialties: const ['Alzheimer', 'Movilidad reducida'],
        verified: true,
        availableSlots: const {},
        stripeAccountId: 'acct_test_123',
        verificationStatus: 'approved',
      );

      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final dateStr = DateFormat('yyyy-MM-dd').format(tomorrow);
      final slots = List.generate(
        4,
        (i) => TimeSlot(
          id: 'slot_$i',
          dateTime:
              DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9 + i),
          isAvailable: true,
        ),
      );

      await tester.pumpWidget(
        wrapSenior15x(
          PaymentScreen(
            caregiver: caregiver,
            dateString: dateStr,
            slots: slots,
          ),
          auth: auth,
          config: ConfigNotifier(),
          booking: BookingNotifier(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Resumen de Reserva'), findsOneWidget);
      await verifyWcagContrastAndNoOverflow(tester);

      // Scroll through the entire PaymentScreen (payment methods, checklist input, escrow notice)
      final scrollState =
          tester.state<ScrollableState>(find.byType(Scrollable).first);
      final maxScroll = scrollState.position.maxScrollExtent;
      for (double pos = 0; pos <= maxScroll; pos += 280) {
        scrollState.position.jumpTo(pos.clamp(0.0, maxScroll));
        await tester.pump(const Duration(milliseconds: 100));
        await verifyWcagContrastAndNoOverflow(tester);
      }
      scrollState.position.jumpTo(maxScroll);
      await tester.pump(const Duration(milliseconds: 100));
      await verifyWcagContrastAndNoOverflow(tester);

      // Jump back to top and open the Escudo de Protección bottom sheet at 1.5x
      scrollState.position.jumpTo(0);
      await tester.pumpAndSettle();
      final shieldRow = find.textContaining('Escudo de Protección');
      await tester.scrollUntilVisible(
        shieldRow,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(shieldRow.first);
      await tester.pumpAndSettle();

      await verifyWcagContrastAndNoOverflow(tester);
      await tester.ensureVisible(find.text('Entendido'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entendido'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'BookingsScreen (Client & Caregiver roles, all booking states & modals) renders with 0 overflows and passes WCAG AA',
        (tester) async {
      resetDI();
      setCompactViewport15x(tester);

      final now = DateTime.now();
      final todayStr = DateFormat('yyyy-MM-dd').format(now);
      final tomorrow = now.add(const Duration(days: 1));
      final tomorrowStr = DateFormat('yyyy-MM-dd').format(tomorrow);
      final yesterday = now.subtract(const Duration(days: 2));
      final yesterdayStr = DateFormat('yyyy-MM-dd').format(yesterday);

      await DependencyInjection.clients.updateClient('cli_audit_1', {
        'name': 'Carmen Martínez Ruiz',
        'phone': '600123456',
        'homeAddress': 'Calle Mayor 42, 3º B, Madrid',
        'careRecipientName': 'Don Antonio Martínez',
        'mobilityLevel': 'Camina con andador',
        'patientDetails': 'Hipertensión controlada, pastilla a las 11:00.',
        'onboardingComplete': true,
      });

      final authClient = AuthNotifier();
      await DependencyInjection.auth.signUpWithEmail(
        'cliente.reservas@senicare.es',
        'Secret123!',
        'client',
        const {'name': 'Carmen Martínez Ruiz'},
      );
      await tester.pump(const Duration(milliseconds: 50));
      await authClient.reloadRole();
      final clientId =
          authClient.effectiveClientId ?? authClient.currentUserId ?? 'cli_audit_1';

      final seededBookings = [
        // 1. Confirmed upcoming with PIN
        Booking(
          id: 'bk_upcoming',
          clientId: clientId,
          caregiverId: 'cg_1',
          caregiverName: 'Laura Gómez Sánchez',
          day: tomorrowStr,
          slot: '10:00-14:00',
          bookingPin: '8492',
          status: BookingStatus.confirmed,
          liveStatus: 'on_the_way',
          onTheWayAt: now,
          cost: 60.0,
          clientFee: 1.50,
          caregiverCommissionRate: 0.18,
          caregiverCommissionAmount: 10.80,
          totalPaid: 61.50,
          caregiverPayout: 49.20,
          careChecklist: [
            CareChecklistItem(id: 't1', title: 'Control de tensión arterial'),
            CareChecklistItem(
                id: 't2',
                title: 'Paseo matinal',
                completed: true,
                completedAt: '10:30'),
          ],
          careNotes: 'Don Antonio ha desayunado muy bien y está animado.',
          carePhotoUrls: const ['https://example.com/photo1.jpg'],
        ),
        // 2. Pending confirmation
        Booking(
          id: 'bk_pending',
          clientId: clientId,
          caregiverId: 'cg_1',
          caregiverName: 'Laura Gómez Sánchez',
          day: tomorrowStr,
          slot: '16:00-18:00',
          status: BookingStatus.pending,
          cost: 30.0,
          clientFee: 1.50,
          caregiverCommissionRate: 0.18,
          caregiverCommissionAmount: 5.40,
          totalPaid: 31.50,
          caregiverPayout: 24.60,
        ),
        // 3. Disputed booking
        Booking(
          id: 'bk_disputed',
          clientId: clientId,
          caregiverId: 'cg_1',
          caregiverName: 'Laura Gómez Sánchez',
          day: todayStr,
          slot: '08:00-10:00',
          status: BookingStatus.completed,
          checkInTime: now.subtract(const Duration(hours: 3)),
          checkOutTime: now.subtract(const Duration(hours: 1)),
          liveStatus: 'completed',
          escrowStatus: 'disputed',
          disputeAmount: 10.0,
          cost: 30.0,
          clientFee: 1.50,
          caregiverCommissionRate: 0.18,
          caregiverCommissionAmount: 5.40,
          totalPaid: 31.50,
          caregiverPayout: 24.60,
        ),
        // 4. Expired No-Show booking
        Booking(
          id: 'bk_noshow',
          clientId: clientId,
          caregiverId: 'cg_1',
          caregiverName: 'Laura Gómez Sánchez',
          day: yesterdayStr,
          slot: '09:00-11:00',
          status: BookingStatus.confirmed,
          escrowStatus: 'held',
          cost: 30.0,
          clientFee: 1.50,
          caregiverCommissionRate: 0.18,
          caregiverCommissionAmount: 5.40,
          caregiverPayout: 24.60,
          totalPaid: 31.50,
        ),
        // 5. Completed & reviewed in History with tip
        Booking(
          id: 'bk_history_reviewed',
          clientId: clientId,
          caregiverId: 'cg_1',
          caregiverName: 'Laura Gómez Sánchez',
          day: yesterdayStr,
          slot: '16:00-20:00',
          status: BookingStatus.completed,
          escrowStatus: 'released',
          isReviewed: true,
          tipAmount: 5.0,
          cost: 60.0,
          clientFee: 1.50,
          caregiverCommissionRate: 0.18,
          caregiverCommissionAmount: 10.80,
          totalPaid: 61.50,
          caregiverPayout: 49.20,
        ),
      ];

      for (final b in seededBookings) {
        await DependencyInjection.bookings.createBooking(b);
      }

      final bookingNotifier = BookingNotifier();
      bookingNotifier.updateAuth(clientId, 'client');
      await tester.pump(const Duration(milliseconds: 100));

      // --- A. Client Role ---
      await tester.pumpWidget(
        wrapSenior15x(
          const BookingsScreen(),
          auth: authClient,
          config: ConfigNotifier(),
          booking: bookingNotifier,
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await verifyWcagContrastAndNoOverflow(tester);

      // If ReviewDialog auto-opened, audit it and close it so we also scroll all cards
      if (find.text('Más tarde').evaluate().isNotEmpty) {
        await verifyWcagContrastAndNoOverflow(tester);
        await tester.tap(find.text('Más tarde'));
        await tester.pumpAndSettle();
      }

      // Scroll through Client Active bookings
      for (int i = 0; i < 5; i++) {
        await tester.drag(find.byType(ListView).first, const Offset(0, -350),
            warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 150));
        await verifyWcagContrastAndNoOverflow(tester);
      }

      // Switch to Historial tab (dismissing ReviewDialog if re-shown)
      while (find.text('Más tarde').evaluate().isNotEmpty) {
        await verifyWcagContrastAndNoOverflow(tester);
        await tester.tap(find.text('Más tarde'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byType(Tab).at(1));
      await tester.pumpAndSettle();
      await verifyWcagContrastAndNoOverflow(tester);

      // --- B. Caregiver Role ---
      final authCaregiver = AuthNotifier();
      await DependencyInjection.auth.signUpWithEmail(
        'cuidadora.reservas@senicare.es',
        'Secret123!',
        'caregiver',
        const {'name': 'Laura Gómez Sánchez', 'pricePerHour': 15.0},
      );
      await tester.pump(const Duration(milliseconds: 50));
      await authCaregiver.reloadRole();
      final cgId = authCaregiver.currentCaregiver?.id ??
          authCaregiver.currentUserId ??
          'cg_1';

      await DependencyInjection.bookings.createBooking(
        Booking(
          id: 'bk_cg_inprogress',
          clientId: 'cli_audit_1',
          caregiverId: cgId,
          caregiverName: 'Laura Gómez Sánchez',
          day: todayStr,
          slot: '00:00-23:59',
          status: BookingStatus.confirmed,
          checkInTime: now.subtract(const Duration(minutes: 45)),
          liveStatus: 'in_progress',
          cost: 45.0,
          clientFee: 2.25,
          caregiverCommissionRate: 0.18,
          caregiverCommissionAmount: 8.10,
          totalPaid: 47.25,
          caregiverPayout: 36.90,
          careChecklist: [
            CareChecklistItem(id: 'c1', title: 'Preparar almuerzo bajo en sal'),
          ],
        ),
      );
      await DependencyInjection.bookings.createBooking(
        Booking(
          id: 'bk_cg_pending',
          clientId: 'cli_audit_1',
          caregiverId: cgId,
          caregiverName: 'Laura Gómez Sánchez',
          day: tomorrowStr,
          slot: '11:00-13:00',
          status: BookingStatus.pending,
          cost: 30.0,
          clientFee: 1.50,
          caregiverCommissionRate: 0.18,
          caregiverCommissionAmount: 5.40,
          totalPaid: 31.50,
          caregiverPayout: 24.60,
        ),
      );
      await DependencyInjection.bookings.createBooking(
        Booking(
          id: 'bk_cg_dispute',
          clientId: 'cli_audit_1',
          caregiverId: cgId,
          caregiverName: 'Laura Gómez Sánchez',
          day: yesterdayStr,
          slot: '10:00-12:00',
          status: BookingStatus.completed,
          escrowStatus: 'disputed',
          disputeAmount: 8.0,
          cost: 30.0,
          clientFee: 1.50,
          caregiverCommissionRate: 0.18,
          caregiverCommissionAmount: 5.40,
          totalPaid: 31.50,
          caregiverPayout: 24.60,
        ),
      );
      bookingNotifier.updateAuth(cgId, 'caregiver');
      await tester.pump(const Duration(milliseconds: 100));

      await tester.pumpWidget(
        wrapSenior15x(
          const BookingsScreen(),
          auth: authCaregiver,
          config: ConfigNotifier(),
          booking: bookingNotifier,
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await verifyWcagContrastAndNoOverflow(tester);

      // Tap Activas tab first
      while (find.text('Más tarde').evaluate().isNotEmpty) {
        await tester.tap(find.text('Más tarde'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byType(Tab).at(0));
      await tester.pumpAndSettle();
      await verifyWcagContrastAndNoOverflow(tester);

      for (int i = 0; i < 5; i++) {
        await tester.drag(find.byType(ListView).first, const Offset(0, -350),
            warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 150));
        await verifyWcagContrastAndNoOverflow(tester);
      }
    });

    testWidgets(
        'CaregiverDashboard (alerts, disputes, incoming requests, active service & loyalty tiers) renders with 0 overflows and passes WCAG AA',
        (tester) async {
      resetDI();
      setCompactViewport15x(tester);

      await DependencyInjection.clients.updateClient('cli_audit_1', {
        'name': 'Carmen Martínez Ruiz',
        'phone': '600123456',
        'homeAddress': 'Avenida Diagonal 210, Barcelona',
        'careRecipientName': 'Doña Pilar',
        'patientDetails': 'Control glucemia antes de comer.',
        'onboardingComplete': true,
      });

      final authCaregiver = AuthNotifier();
      await DependencyInjection.auth.signUpWithEmail(
        'cuidadora.panel@senicare.es',
        'Secret123!',
        'caregiver',
        const {'name': 'Laura Gómez Sánchez', 'pricePerHour': 16.0},
      );
      await tester.pump(const Duration(milliseconds: 50));
      await authCaregiver.reloadRole();
      final cgId = authCaregiver.currentCaregiver?.id ??
          authCaregiver.currentUserId ??
          'cg_panel';

      final now = DateTime.now();
      final todayStr = DateFormat('yyyy-MM-dd').format(now);
      final tomorrowStr =
          DateFormat('yyyy-MM-dd').format(now.add(const Duration(days: 1)));

      await DependencyInjection.bookings.createBooking(
        Booking(
          id: 'dash_active_1',
          clientId: 'cli_audit_1',
          caregiverId: cgId,
          caregiverName: 'Laura Gómez Sánchez',
          day: todayStr,
          slot: '00:00-23:59',
          status: BookingStatus.confirmed,
          checkInTime: now.subtract(const Duration(minutes: 30)),
          liveStatus: 'in_progress',
          cost: 64.0,
          clientFee: 1.60,
          caregiverCommissionRate: 0.14,
          caregiverCommissionAmount: 8.96,
          totalPaid: 65.60,
          caregiverPayout: 55.04,
          careChecklist: [
            CareChecklistItem(id: 'd1', title: 'Medir tensión arterial'),
            CareChecklistItem(
                id: 'd2', title: 'Dar paseo corto', completed: true),
          ],
          careNotes: 'Todo en orden durante la mañana.',
        ),
      );
      await DependencyInjection.bookings.createBooking(
        Booking(
          id: 'dash_req_1',
          clientId: 'cli_audit_1',
          caregiverId: cgId,
          caregiverName: 'Laura Gómez Sánchez',
          day: tomorrowStr,
          slot: '09:00-13:00',
          status: BookingStatus.pending,
          cost: 64.0,
          clientFee: 1.60,
          caregiverCommissionRate: 0.14,
          caregiverCommissionAmount: 8.96,
          totalPaid: 65.60,
          caregiverPayout: 55.04,
        ),
      );
      await DependencyInjection.bookings.createBooking(
        Booking(
          id: 'dash_dispute_1',
          clientId: 'cli_audit_1',
          caregiverId: cgId,
          caregiverName: 'Laura Gómez Sánchez',
          day: todayStr,
          slot: '07:00-08:00',
          status: BookingStatus.completed,
          escrowStatus: 'disputed',
          disputeAmount: 5.0,
          cost: 16.0,
          clientFee: 1.50,
          caregiverCommissionRate: 0.18,
          caregiverCommissionAmount: 2.88,
          totalPaid: 17.50,
          caregiverPayout: 13.12,
        ),
      );

      final bookingNotifier = BookingNotifier();
      bookingNotifier.updateAuth(cgId, 'caregiver');
      await tester.pump(const Duration(milliseconds: 100));

      await tester.pumpWidget(
        wrapSenior15x(
          const Scaffold(body: CaregiverDashboard()),
          auth: authCaregiver,
          config: ConfigNotifier(),
          booking: bookingNotifier,
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await verifyWcagContrastAndNoOverflow(tester);

      // Scroll down the entire CaregiverDashboard on 360x800 at 1.5x Senior Mode
      final dashScroll =
          tester.state<ScrollableState>(find.byType(Scrollable).first);
      for (int i = 0; i < 8; i++) {
        final next = (dashScroll.position.pixels + 300)
            .clamp(0.0, dashScroll.position.maxScrollExtent);
        dashScroll.position.jumpTo(next);
        await tester.pump(const Duration(milliseconds: 120));
        await verifyWcagContrastAndNoOverflow(tester);
      }

      // Jump back to top and scrollUntilVisible to open Tramos modal at 1.5x
      dashScroll.position.jumpTo(0);
      await tester.pumpAndSettle();
      final tramosBtn = find.textContaining('Tramos');
      await tester.scrollUntilVisible(
        tramosBtn,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(tramosBtn);
      await tester.pumpAndSettle();
      await verifyWcagContrastAndNoOverflow(tester);
      await tester.ensureVisible(find.text('Entendido'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entendido'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
