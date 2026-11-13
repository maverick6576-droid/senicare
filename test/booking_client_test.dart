import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';
import 'package:senicare/screens/bookings_screen.dart';
import 'package:senicare/widgets/widgets.dart';

class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier({
    String userId = 'client_1',
    String role = 'client',
    String clientName = 'Carmen López',
  }) {
    isAuthenticated = true;
    currentUserId = userId;
    currentRole = role;
    onboardingComplete = true;
    currentClient = ClientProfile(
      id: userId,
      name: clientName,
      phone: '600112233',
      homeAddress: 'Calle Mayor 10, Madrid',
      patientDetails: 'Dieta sin sal',
      onboardingComplete: true,
    );
  }
}

class _FailingStreamBookingRepo extends MockBookingRepository {
  bool failCancel = false;
  bool failStream = true;

  @override
  Stream<List<Booking>> streamBookings(String userId, String role, {int? limit}) {
    if (failStream) {
      return Stream<List<Booking>>.error(Exception('Error de red simulado'));
    }
    return super.streamBookings(userId, role, limit: limit);
  }

  @override
  Future<void> cancelBooking(String bookingId, String reason, bool isLate) async {
    if (failCancel) {
      throw Exception('Error en pasarela al cancelar');
    }
    return super.cancelBooking(bookingId, reason, isLate);
  }
}

class _TrackingStatsRepo implements FirestoreStatsRepository {
  int lastHoursRecorded = 0;

  @override
  Future<void> addCompletedHours(
    String clientId,
    String caregiverId,
    int hoursToAdd,
  ) async {
    lastHoursRecorded += hoursToAdd;
  }

  @override
  Future<int> getAccumulatedHours(String clientId, String caregiverId) async =>
      lastHoursRecorded;

  @override
  Future<List<Map<String, dynamic>>> getCaregiverClientStats(
          String caregiverId) async =>
      [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Booking _makeClientBooking({
  required String id,
  String clientId = 'client_1',
  String caregiverId = 'cg_1',
  String caregiverName = 'Elena Gómez',
  String? day,
  String slot = '10:00-12:00',
  BookingStatus status = BookingStatus.confirmed,
  String escrowStatus = 'held',
  String liveStatus = 'scheduled',
  DateTime? checkInTime,
  DateTime? checkOutTime,
  String? bookingPin = '4821',
  bool isReviewed = false,
  bool reviewPromptDismissed = true,
  double cost = 40.0,
  double tipAmount = 0.0,
  List<CareChecklistItem> careChecklist = const [],
  DateTime? createdAt,
}) {
  final targetDay = day ?? _formatDate(DateTime.now().add(const Duration(days: 2)));
  return Booking(
    id: id,
    clientId: clientId,
    caregiverId: caregiverId,
    caregiverName: caregiverName,
    day: targetDay,
    slot: slot,
    clientLatitude: 40.4168,
    clientLongitude: -3.7038,
    bookingPin: bookingPin,
    status: status,
    cost: cost,
    clientFee: 1.2,
    caregiverCommissionRate: 0.15,
    caregiverCommissionAmount: 6.0,
    caregiverPayout: 34.0,
    totalPaid: cost + 1.2,
    transferGroup: 'tg_$id',
    paymentIntentId: 'pi_$id',
    escrowStatus: escrowStatus,
    isReviewed: isReviewed,
    reviewPromptDismissed: reviewPromptDismissed,
    createdAt: createdAt ?? DateTime(2026, 5, 1, 10),
    checkInTime: checkInTime,
    checkOutTime: checkOutTime,
    careChecklist: careChecklist,
    careNotes: 'Nota de cuidado',
    carePhotoUrls: const ['https://example.com/p.jpg'],
    liveStatus: liveStatus,
    tipAmount: tipAmount,
  );
}

String _formatDate(DateTime dt) =>
    '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

Widget _wrapClientBookingsHarness({
  required _TestAuthNotifier auth,
  required BookingNotifier bookingNotifier,
  required ConfigNotifier config,
  Size size = const Size(390, 844),
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthNotifier>.value(value: auth),
      ChangeNotifierProvider<BookingNotifier>.value(value: bookingNotifier),
      ChangeNotifierProvider<ConfigNotifier>.value(value: config),
    ],
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: const BookingsScreen(),
      ),
    ),
  );
}

void main() {
  late MockBookingRepository mockBookingRepo;
  late _TrackingStatsRepo statsRepo;

  setUp(() {
    mockBookingRepo = MockBookingRepository(filterByUser: true);
    statsRepo = _TrackingStatsRepo();
    DependencyInjection.auth = MockAuthRepository();
    DependencyInjection.caregivers = MockCaregiverRepository();
    DependencyInjection.clients = MockClientRepository();
    DependencyInjection.bookings = mockBookingRepo;
    DependencyInjection.chats = MockChatRepository();
    DependencyInjection.reviews = MockReviewRepository();
    DependencyInjection.reports = MockReportRepository();
    DependencyInjection.stats = statsRepo;
  });

  group('MockBookingRepository & Booking.copyWith', () {
    test('preserves all extended fields across releaseEscrow and cancelBooking', () async {
      final b = _makeClientBooking(
        id: 'bk_preserve',
        bookingPin: '9912',
        tipAmount: 5.0,
        careChecklist: [
          CareChecklistItem(id: 't1', title: 'Medicación 10:00', completed: true),
        ],
        checkInTime: DateTime(2026, 5, 1, 10, 2),
      );
      await mockBookingRepo.createBooking(b);

      await mockBookingRepo.releaseEscrow('bk_preserve');
      final afterRelease =
          (await mockBookingRepo.streamBookings('client_1', 'client').first).first;
      expect(afterRelease.status, BookingStatus.completed);
      expect(afterRelease.escrowStatus, 'released');
      expect(afterRelease.bookingPin, '9912');
      expect(afterRelease.tipAmount, 5.0);
      expect(afterRelease.careChecklist.length, 1);
      expect(afterRelease.checkInTime, isNotNull);
      expect(afterRelease.clientLatitude, closeTo(40.4168, 0.0001));
      expect(afterRelease.paymentIntentId, 'pi_bk_preserve');

      await mockBookingRepo.cancelBooking('bk_preserve', 'Cambio familiar', true);
      final afterCancel =
          (await mockBookingRepo.streamBookings('client_1', 'client').first).first;
      expect(afterCancel.status, BookingStatus.cancelledLate);
      expect(afterCancel.cancellationReason, 'Cambio familiar');
      expect(afterCancel.bookingPin, '9912');
      expect(afterCancel.careNotes, 'Nota de cuidado');
    });

    test('filters strictly by userId and role and sorts descending by createdAt', () async {
      await mockBookingRepo.createBooking(_makeClientBooking(
        id: 'old_c1',
        clientId: 'client_1',
        createdAt: DateTime(2026, 5, 1, 8),
      ));
      await mockBookingRepo.createBooking(_makeClientBooking(
        id: 'other_client',
        clientId: 'client_2',
        createdAt: DateTime(2026, 5, 2, 12),
      ));
      await mockBookingRepo.createBooking(_makeClientBooking(
        id: 'new_c1',
        clientId: 'client_1',
        createdAt: DateTime(2026, 5, 3, 9),
      ));

      final list = await mockBookingRepo.streamBookings('client_1', 'client').first;
      expect(list.map((b) => b.id).toList(), ['new_c1', 'old_c1']);
    });
  });

  group('BookingNotifier client error/loading & mock-safe mutations', () {
    test('handles stream errors cleanly and recovers via retryBookings', () async {
      final flakyRepo = _FailingStreamBookingRepo();
      await flakyRepo.createBooking(_makeClientBooking(id: 'recovered_1'));
      DependencyInjection.bookings = flakyRepo;

      final notifier = BookingNotifier();
      notifier.updateAuth('client_1', 'client');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(notifier.bookingError, isNotNull);
      expect(notifier.isLoadingBookings, isFalse);

      flakyRepo.failStream = false;
      notifier.retryBookings();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(notifier.bookingError, isNull);
      expect(notifier.bookings.length, 1);
      expect(notifier.bookings.first.id, 'recovered_1');
      notifier.dispose();
    });

    test('executes releaseEscrow, cancelBooking, openDispute and dismissReviewPrompt safely without Firebase', () async {
      final b1 = _makeClientBooking(
        id: 'b_release',
        slot: '10:00-12:30',
        liveStatus: 'completed',
      );
      final b2 = _makeClientBooking(id: 'b_cancel');
      final b3 = _makeClientBooking(id: 'b_dispute');
      await mockBookingRepo.createBooking(b1);
      await mockBookingRepo.createBooking(b2);
      await mockBookingRepo.createBooking(b3);

      final notifier = BookingNotifier();
      notifier.updateAuth('client_1', 'client');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // releaseEscrow uses rounded minutes -> 2.5h rounds to 3h
      await notifier.releaseEscrow('b_release');
      final rel = notifier.bookings.firstWhere((b) => b.id == 'b_release');
      expect(rel.status, BookingStatus.completed);
      expect(rel.escrowStatus, 'released');
      expect(statsRepo.lastHoursRecorded, 3);

      // cancelBooking updates model copy cleanly even with final cancellationReason
      await notifier.cancelBooking('b_cancel', 'Ya no es necesario', false);
      final can = notifier.bookings.firstWhere((b) => b.id == 'b_cancel');
      expect(can.status, BookingStatus.cancelled);
      expect(can.escrowStatus, 'refunded');
      expect(can.cancellationReason, 'Ya no es necesario');

      // openDispute updates local dispute fields without Firestore crash
      await notifier.openDispute('b_dispute', 20.0, 'Llegó tarde', 'Media hora');
      final disp = notifier.bookings.firstWhere((b) => b.id == 'b_dispute');
      expect(disp.disputeRequested, isTrue);
      expect(disp.disputeAmount, 20.0);
      expect(disp.disputeReason, 'Llegó tarde');
      expect(disp.disputeDescription, 'Media hora');
      expect(disp.escrowStatus, 'disputed');

      // dismissReviewPrompt works offline without Firestore crash
      await notifier.dismissReviewPrompt([rel]);
      expect(rel.reviewPromptDismissed, isTrue);

      notifier.dispose();
    });
  });

  group('BookingsScreen Client UI, filters, Senior Mode & error handling', () {
    testWidgets('renders empty state CTAs for client with zero bookings', (tester) async {
      final auth = _TestAuthNotifier();
      final notifier = BookingNotifier()..updateAuth('client_1', 'client');
      final config = ConfigNotifier()..toggleSeniorMode(true);

      await tester.pumpWidget(_wrapClientBookingsHarness(
        auth: auth,
        bookingNotifier: notifier,
        config: config,
      ));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Aún no tienes cuidados activos'), findsOneWidget);
      expect(find.text('Buscar cuidador'), findsOneWidget);
      expect(find.text('Publicar oferta de cuidado'), findsOneWidget);

      notifier.dispose();
    });

    testWidgets('shows error state with Reintentar and recovers when repo succeeds', (tester) async {
      final flakyRepo = _FailingStreamBookingRepo();
      await flakyRepo.createBooking(_makeClientBooking(id: 'ok_1', caregiverName: 'Lucía Pérez'));
      DependencyInjection.bookings = flakyRepo;

      final auth = _TestAuthNotifier();
      final notifier = BookingNotifier()..updateAuth('client_1', 'client');
      final config = ConfigNotifier();

      await tester.pumpWidget(_wrapClientBookingsHarness(
        auth: auth,
        bookingNotifier: notifier,
        config: config,
      ));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('No pudimos cargar tus reservas'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);

      flakyRepo.failStream = false;
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('Lucía Pérez'), findsOneWidget);
      notifier.dispose();
    });

    testWidgets('renders client filters, PIN button, release CTA, Historial expired-pending fix & zero Senior Mode overflow at 360x640', (tester) async {
      final now = DateTime.now();
      final todayStr = _formatDate(now);
      final futureStr = _formatDate(now.add(const Duration(days: 3)));

      // Active 1: Confirmed awaiting arrival with PIN
      await mockBookingRepo.createBooking(_makeClientBooking(
        id: 'act_pin',
        caregiverName: 'María Ruiz',
        day: todayStr,
        slot: '23:00-23:59',
        bookingPin: '4821',
        createdAt: DateTime(2026, 5, 5, 10),
      ));
      // Active 2: Service finished by caregiver, awaiting client release confirmation
      await mockBookingRepo.createBooking(_makeClientBooking(
        id: 'act_release',
        caregiverName: 'Carlos Vega',
        day: futureStr,
        slot: '10:00-12:00',
        status: BookingStatus.confirmed,
        liveStatus: 'completed',
        checkInTime: now.subtract(const Duration(hours: 2)),
        checkOutTime: now,
        escrowStatus: 'held',
        createdAt: DateTime(2026, 5, 4, 10),
      ));
      // History: Expired pending booking (must NOT display 'Esperando confirmación')
      await mockBookingRepo.createBooking(_makeClientBooking(
        id: 'hist_expired',
        caregiverName: 'Sofía Mora',
        day: '2024-01-10',
        slot: '09:00-11:00',
        status: BookingStatus.pending,
        escrowStatus: 'held',
        createdAt: DateTime(2024, 1, 9, 10),
      ));

      final auth = _TestAuthNotifier();
      final notifier = BookingNotifier()..updateAuth('client_1', 'client');
      final config = ConfigNotifier()..toggleSeniorMode(true);

      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_wrapClientBookingsHarness(
        auth: auth,
        bookingNotifier: notifier,
        config: config,
        size: const Size(360, 640),
      ));
      await tester.pump(const Duration(milliseconds: 60));

      expect(tester.takeException(), isNull);
      expect(find.text('Activas (2)'), findsOneWidget);
      expect(find.text('Historial (1)'), findsOneWidget);

      // Client header & filters
      expect(find.text('Pago protegido hasta que termine el cuidado'), findsOneWidget);
      expect(find.text('Todas (2)'), findsOneWidget);
      expect(find.text('Por confirmar (1)'), findsOneWidget);
      expect(find.text('Hoy / En curso (1)'), findsOneWidget);

      // PIN & release CTAs directly visible (filter to Por confirmar first to bring second card into 640px viewport, after verifying PIN button on first card)
      expect(find.textContaining('4821'), findsWidgets);

      // Filter to 'Por confirmar (1)' -> only Carlos Vega shows with release & problem buttons
      await tester.ensureVisible(find.text('Por confirmar (1)'));
      await tester.pump();
      await tester.tap(find.text('Por confirmar (1)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Carlos Vega'), findsOneWidget);
      expect(find.text('Confirmar y liberar pago'), findsOneWidget);
      expect(find.text('Informar de un problema'), findsOneWidget);
      expect(find.text('María Ruiz'), findsNothing);

      // Reset to Todas (2)
      await tester.tap(find.text('Todas (2)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('María Ruiz'), findsOneWidget);

      // Switch to Historial tab -> expired pending MUST NOT show 'Esperando confirmación'
      await tester.tap(find.text('Historial (1)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Sofía Mora'), findsOneWidget);
      expect(find.textContaining('Esperando confirmación de'), findsNothing);
      expect(find.text('Buscar otro cuidador'), findsOneWidget);
      expect(tester.takeException(), isNull);

      notifier.dispose();
    });

    testWidgets('shows real error message when discarding/cancelling fails instead of lying success', (tester) async {
      final failingRepo = _FailingStreamBookingRepo()
        ..failStream = false
        ..failCancel = true;
      await failingRepo.createBooking(_makeClientBooking(
        id: 'pending_pay_1',
        caregiverName: 'Ana Torres',
        day: _formatDate(DateTime.now().add(const Duration(days: 2))),
        slot: '10:00-12:00',
        status: BookingStatus.pendingPayment,
      ));
      DependencyInjection.bookings = failingRepo;

      final auth = _TestAuthNotifier();
      final notifier = BookingNotifier()..updateAuth('client_1', 'client');
      final config = ConfigNotifier();

      await tester.pumpWidget(_wrapClientBookingsHarness(
        auth: auth,
        bookingNotifier: notifier,
        config: config,
      ));
      await tester.pump(const Duration(milliseconds: 60));

      await tester.tap(find.text('Descartar intento no pagado'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Descartar Intento'), findsOneWidget);
      await tester.tap(find.text('Descartar'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('No se pudo completar la acción'), findsOneWidget);
      expect(find.text('Intento descartado.'), findsNothing);

      notifier.dispose();
    });

    testWidgets('DisputeDialog shows visible inline validation error before submitting', (tester) async {
      final b = _makeClientBooking(id: 'disp_ui', cost: 50.0);
      final notifier = BookingNotifier()..updateAuth('client_1', 'client');
      final config = ConfigNotifier()..toggleSeniorMode(true);

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<BookingNotifier>.value(value: notifier),
          ChangeNotifierProvider<ConfigNotifier>.value(value: config),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showDialog(
                  context: ctx,
                  builder: (_) => DisputeDialog(booking: b),
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Abrir'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Informar de un problema'), findsOneWidget);
      await tester.tap(find.text('Enviar Incidencia'));
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.text('Por favor, selecciona un motivo antes de enviar.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      notifier.dispose();
    });

    testWidgets('opens PIN/QR modal and adds checklist task in mock mode', (tester) async {
      final todayStr = _formatDate(DateTime.now());
      await mockBookingRepo.createBooking(_makeClientBooking(
        id: 'act_tools',
        caregiverName: 'Beatriz Soler',
        day: todayStr,
        slot: '23:00-23:59',
        bookingPin: '7394',
        careChecklist: [
          CareChecklistItem(id: 'c1', title: 'Paseo suave', completed: false),
        ],
      ));

      final auth = _TestAuthNotifier();
      final notifier = BookingNotifier()..updateAuth('client_1', 'client');
      final config = ConfigNotifier();

      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_wrapClientBookingsHarness(
        auth: auth,
        bookingNotifier: notifier,
        config: config,
      ));
      await tester.pump(const Duration(milliseconds: 60));

      // Verify caregiver initials avatar & PIN button
      expect(find.text('BS'), findsOneWidget);
      expect(find.text('🔑 Código de Entrada: 7394'), findsOneWidget);

      // Tap PIN button to open access modal
      await tester.tap(find.text('🔑 Código de Entrada: 7394'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('7394'), findsWidgets);
      await tester.ensureVisible(find.text('Cerrar'));
      await tester.pump();
      await tester.tap(find.text('Cerrar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Expand Diario y Pautas del Cuidado checklist & add custom task
      await tester.ensureVisible(find.text('Diario y Pautas del Cuidado'));
      await tester.pump();
      await tester.tap(find.text('Diario y Pautas del Cuidado'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      await tester.ensureVisible(find.text('Escribir tarea a medida'));
      await tester.pump();
      await tester.tap(find.text('Escribir tarea a medida'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.enterText(find.byType(TextField).last, 'Tomar pastilla 13:00');
      await tester.tap(find.text('Añadir a la Checklist'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Tomar pastilla 13:00'), findsOneWidget);
      expect(tester.takeException(), isNull);
      notifier.dispose();
    });
  });
}
