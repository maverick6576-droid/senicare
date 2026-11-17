import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';
import 'package:senicare/screens/screens.dart';
import 'package:senicare/widgets/widgets.dart';

void main() {
  late MockBookingRepository mockRepo;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    mockRepo = MockBookingRepository();
    DependencyInjection.auth = MockAuthRepository();
    DependencyInjection.bookings = mockRepo;
  });

  Booking makeBooking({
    String id = 'b1',
    DateTime? startDt,
    int durationHours = 2,
    BookingStatus status = BookingStatus.confirmed,
    String escrowStatus = 'held',
    String liveStatus = 'scheduled',
    DateTime? checkInTime,
    DateTime? checkOutTime,
    double cost = 40.0,
    double caregiverCommissionRate = 0.18,
    double caregiverCommissionAmount = 0.0,
    double caregiverPayout = 0.0,
    double? disputeAmount,
  }) {
    final start = startDt ?? DateTime.now().add(const Duration(hours: 3));
    final end = start.add(Duration(hours: durationHours));
    final dayStr = DateFormat('yyyy-MM-dd').format(start);
    final slotStr =
        '${DateFormat('HH:mm').format(start)}-${DateFormat('HH:mm').format(end)}';
    return Booking(
      id: id,
      clientId: 'client_1',
      caregiverId: 'cg_1',
      caregiverName: 'Laura Pérez',
      day: dayStr,
      slot: slotStr,
      status: status,
      cost: cost,
      clientFee: cost * 0.03,
      caregiverCommissionRate: caregiverCommissionRate,
      caregiverCommissionAmount: caregiverCommissionAmount,
      caregiverPayout: caregiverPayout,
      totalPaid: cost * 1.03,
      escrowStatus: escrowStatus,
      liveStatus: liveStatus,
      checkInTime: checkInTime,
      checkOutTime: checkOutTime,
      disputeAmount: disputeAmount,
    );
  }

  group('Booking caregiver lifecycle & active status', () {
    test('keeps checked-in uncompleted shift active even past scheduled end', () {
      final pastStart = DateTime.now().subtract(const Duration(hours: 4));
      final b = makeBooking(
        startDt: pastStart,
        durationHours: 2,
        status: BookingStatus.confirmed,
        liveStatus: 'in_progress',
        checkInTime: pastStart.add(const Duration(minutes: 2)),
      );

      expect(b.isExpired, isTrue);
      expect(b.isInProgressAwaitingCheckOut, isTrue);
      expect(b.isActive, isTrue);
    });

    test('moves checked-in shift to inactive once completed', () {
      final pastStart = DateTime.now().subtract(const Duration(hours: 4));
      final b = makeBooking(
        startDt: pastStart,
        durationHours: 2,
        status: BookingStatus.confirmed,
        liveStatus: 'completed',
        checkInTime: pastStart,
        checkOutTime: pastStart.add(const Duration(hours: 2)),
      );

      expect(b.isInProgressAwaitingCheckOut, isFalse);
      expect(b.isActive, isFalse);
    });

    test('keeps expired disputed booking active until settled', () {
      final pastStart = DateTime.now().subtract(const Duration(hours: 6));
      final disputed = makeBooking(
        startDt: pastStart,
        durationHours: 2,
        status: BookingStatus.confirmed,
        escrowStatus: 'disputed',
      );
      expect(disputed.isOpenDisputePendingAction, isTrue);
      expect(disputed.isActive, isTrue);

      for (final settled in [
        'released',
        'released_manual',
        'released_auto',
        'resolved_partial',
        'refunded',
      ]) {
        final b = makeBooking(
          escrowStatus: settled,
          status: BookingStatus.confirmed,
        );
        expect(b.isEscrowSettled, isTrue);
        expect(b.isActive, isFalse);
      }
    });
  });

  group('Booking caregiver net earnings calculation', () {
    test('uses explicit caregiverPayout when available', () {
      final b = makeBooking(
        cost: 100.0,
        caregiverCommissionRate: 0.18,
        caregiverPayout: 84.50,
      );
      expect(b.netPayoutForCaregiver, closeTo(84.50, 0.001));
    });

    test('falls back to rate or commission amount when payout is zero', () {
      final byRate = makeBooking(
        cost: 100.0,
        caregiverCommissionRate: 0.15,
        caregiverPayout: 0.0,
      );
      expect(byRate.netPayoutForCaregiver, closeTo(85.0, 0.001));

      final byAmount = makeBooking(
        cost: 100.0,
        caregiverCommissionRate: 0.0,
        caregiverCommissionAmount: 18.0,
        caregiverPayout: 0.0,
      );
      expect(byAmount.netPayoutForCaregiver, closeTo(82.0, 0.001));
    });

    test('estimates net remaining payout after dispute deduction', () {
      final b = makeBooking(
        cost: 100.0,
        caregiverCommissionRate: 0.20,
        caregiverPayout: 0.0,
        escrowStatus: 'resolved_partial',
        disputeAmount: 25.0,
      );
      expect(b.estimateNetAfterDispute(25.0), closeTo(60.0, 0.001));
      expect(b.netPayoutForCaregiver, closeTo(60.0, 0.001));
      expect(b.estimateNetAfterDispute(150.0), closeTo(0.0, 0.001));
    });
  });

  group('BookingNotifier pagination and refresh guards', () {
    test('does not increment limit when fewer bookings than limit exist', () async {
      await mockRepo.createBooking(makeBooking(id: 'b1'));
      final notifier = BookingNotifier();
      notifier.updateAuth('cg_1', 'caregiver');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(notifier.bookings.length, 1);
      expect(notifier.hasMore, isFalse);

      notifier.loadMoreBookings();
      expect(notifier.currentLimit, 15);
      notifier.dispose();
    });

    test('loads next page when limit reached and preserves items on refresh', () async {
      for (int i = 0; i < 18; i++) {
        await mockRepo.createBooking(makeBooking(id: 'b_$i'));
      }
      final notifier = BookingNotifier();
      notifier.updateAuth('cg_1', 'caregiver');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(notifier.bookings.length, 15);
      expect(notifier.hasMore, isTrue);

      notifier.loadMoreBookings();
      expect(notifier.currentLimit, 30);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(notifier.bookings.length, 18);
      expect(notifier.hasMore, isFalse);

      // Switching auth resets limit back to 15.
      notifier.updateAuth('cg_2', 'caregiver');
      expect(notifier.currentLimit, 15);

      // Refresh should not wipe loaded items before stream emits.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(notifier.bookings.length, 15);
      final refreshFuture = notifier.refreshBookings();
      expect(notifier.bookings.length, 15);
      await refreshFuture;

      notifier.dispose();
    });

    test('completeService enforces non-empty careNotes for mandatory checkout summary', () async {
      final b = makeBooking(
        id: 'checkout_test_1',
        status: BookingStatus.confirmed,
        checkInTime: DateTime.now().subtract(const Duration(hours: 1)),
      );
      await mockRepo.createBooking(b);
      final notifier = BookingNotifier();
      notifier.updateAuth('cg_1', 'caregiver');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Vacío debe lanzar excepción
      expect(
        () => notifier.completeService('checkout_test_1', careNotes: '   '),
        throwsA(isA<Exception>()),
      );

      // Con notas válidas completa el servicio
      await notifier.completeService('checkout_test_1', careNotes: 'Paciente comió bien y descansó.');
      final updated = notifier.bookings.firstWhere((item) => item.id == 'checkout_test_1');
      expect(updated.liveStatus, 'completed');
      expect(updated.status, BookingStatus.completed);
      expect(updated.checkOutTime, isNotNull);
      expect(updated.careNotes, 'Paciente comió bien y descansó.');

      notifier.dispose();
    });
  });

  group('Flexible schedule availability & automatic salary calculation', () {
    test('computeAvailableIntervals clips past hours, rejects yesterday, and subtracts booked intervals', () {
      final now = DateTime(2026, 6, 15, 10, 15);
      final yesterday = DateTime(2026, 6, 14);
      final today = DateTime(2026, 6, 15);

      final slots = [
        TimeSlot(
          id: 'flex_1',
          dateTime: DateTime(2026, 6, 15, 9, 0),
          endTime: DateTime(2026, 6, 15, 16, 30),
          isAvailable: true,
        ),
        TimeSlot(
          id: 'booked_1',
          dateTime: DateTime(2026, 6, 15, 12, 0),
          endTime: DateTime(2026, 6, 15, 13, 30),
          isAvailable: false,
        ),
      ];

      expect(
        FlexibleScheduleHelper.computeAvailableIntervals(
          day: yesterday,
          slots: slots,
          now: now,
        ),
        isEmpty,
      );

      final result = FlexibleScheduleHelper.computeAvailableIntervals(
        day: today,
        slots: slots,
        now: now,
      );
      expect(result.length, 2);
      expect(result[0].startFormatted, '10:15');
      expect(result[0].endFormatted, '12:00');
      expect(result[1].startFormatted, '13:30');
      expect(result[1].endFormatted, '16:30');
    });

    test('computeExactCost calculates proportional salary with 4h+ discount', () {
      // 12 €/h × 2h 30min = 30.00 €
      expect(
        FlexibleScheduleHelper.computeExactCost(
          pricePerHour: 12.0,
          durationMinutes: 150,
        ),
        30.00,
      );
      // 12 €/h × 4h 30min × 0.95 = 51.30 €
      expect(
        FlexibleScheduleHelper.computeExactCost(
          pricePerHour: 12.0,
          durationMinutes: 270,
        ),
        51.30,
      );
    });

    testWidgets('CaregiverCalendarScreen blocks yesterday and offers flexible slot creation', (tester) async {
      final mockCaregivers = MockCaregiverRepository();
      DependencyInjection.caregivers = mockCaregivers;
      final auth = AuthNotifier()
        ..isAuthenticated = true
        ..currentUserId = 'cg_flex'
        ..currentRole = 'caregiver';

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthNotifier>.value(value: auth),
            ChangeNotifierProvider<ConfigNotifier>.value(value: ConfigNotifier()),
          ],
          child: const MaterialApp(home: CaregiverCalendarScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final picker = tester.widget<CalendarDatePicker>(find.byType(CalendarDatePicker));
      final now = DateTime.now();
      final todayOnly = DateTime(now.year, now.month, now.day);
      expect(picker.firstDate, todayOnly);
      expect(find.byKey(const Key('add_flexible_slot_btn')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('CaregiverDetailScreen displays flexible availability and automatic salary preview', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final mockCaregivers = MockCaregiverRepository();
      DependencyInjection.caregivers = mockCaregivers;
      DependencyInjection.reviews = MockReviewRepository();

      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final dayStr =
          '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';

      await mockCaregivers.setBatchTimeSlots('cg_flex_detail', dayStr, [
        TimeSlot(
          id: 'flex_tomorrow',
          dateTime: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9, 30),
          endTime: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 12, 0),
          isAvailable: true,
        ),
      ]);

      final caregiver = CaregiverProfile(
        id: 'cg_flex_detail',
        name: 'Marta Soler',
        title: 'Auxiliar de Geriatría',
        bio: 'Experiencia en cuidados a domicilio',
        pricePerHour: 12.0,
        rating: 4.9,
        reviewsCount: 5,
        distance: '1.2 km',
        imageUrl: '',
        specialties: ['Acompañamiento'],
        verified: true,
        availableSlots: {},
        verificationStatus: 'approved',
        stripeAccountId: 'acct_test_123',
      );

      final auth = AuthNotifier()
        ..isAuthenticated = true
        ..currentUserId = 'client_1'
        ..currentRole = 'client';

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthNotifier>.value(value: auth),
            ChangeNotifierProvider<ConfigNotifier>.value(value: ConfigNotifier()),
            ChangeNotifierProvider<LocationNotifier>(create: (_) => LocationNotifier()),
          ],
          child: MaterialApp(home: CaregiverDetailScreen(caregiver: caregiver)),
        ),
      );
      await tester.pumpAndSettle();

      // Seleccionar mañana en el calendario (el PageView de CalendarDatePicker renderiza también el mes siguiente a la derecha)
      final pickerFinder = find.byType(CalendarDatePicker);
      await tester.ensureVisible(pickerFinder);
      await tester.pump();
      if (tomorrow.month == DateTime.now().month) {
        final tomorrowFinder = find.descendant(
          of: pickerFinder,
          matching: find.text('${tomorrow.day}'),
        ).first;
        await tester.tap(tomorrowFinder);
      } else {
        tester.widget<CalendarDatePicker>(pickerFinder).onDateChanged(tomorrow);
      }
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('dynamic_salary_preview_card')));
      await tester.pump();
      expect(find.byKey(const Key('dynamic_salary_preview_card')), findsOneWidget);
      expect(find.textContaining('09:30 - 12:00'), findsWidgets);
      expect(find.textContaining('30.00 €'), findsOneWidget);
      expect(find.byKey(const Key('reserve_flexible_btn')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('CareBasicInfoCard & expandable care details', () {
    ClientProfile buildRichClientProfile() {
      return ClientProfile(
        id: 'client_1',
        name: 'Familia García',
        phone: '+34 600 111 222',
        homeAddress: 'Calle Mayor 45, Madrid',
        patientDetails: 'Necesita acompañamiento tranquilo por la tarde.',
        onboardingComplete: true,
        careRecipientName: 'Antonio García',
        mobilityLevel: 'Usa andador',
        cognitiveNeeds: 'Alzhéimer leve',
        dietNotes: 'Dieta blanda sin sal',
        emergencyPhone: '+34 600 999 888',
        homeAccessNotes: '3º B, portero automático 12#',
        defaultCareChecklist: const ['Dar medicación 17:00', 'Paseo corto'],
      );
    }

    testWidgets(
      'CareBasicInfoCard expands and collapses cleanly in Senior Mode at 360x640',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final booking = makeBooking(
          id: 'b_info_1',
          status: BookingStatus.pending,
        )..careChecklist = [
            CareChecklistItem(id: 'c1', title: 'Control de tensión'),
          ];
        final profile = buildRichClientProfile();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: CareBasicInfoCard(
                  booking: booking,
                  clientProfile: profile,
                  seniorMode: true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Información básica del cuidado'), findsOneWidget);
        expect(find.text('Desplegar'), findsOneWidget);
        expect(find.textContaining('Dieta blanda sin sal'), findsNothing);

        await tester.tap(find.byKey(const Key('toggle_care_info_b_info_1')));
        await tester.pumpAndSettle();

        expect(find.text('Ocultar'), findsOneWidget);
        expect(find.textContaining('Antonio García', findRichText: true), findsWidgets);
        expect(find.textContaining('Usa andador', findRichText: true), findsWidgets);
        expect(find.textContaining('Alzhéimer leve', findRichText: true), findsWidgets);
        expect(find.textContaining('Dieta blanda sin sal', findRichText: true), findsWidgets);
        expect(find.textContaining('Calle Mayor 45, Madrid', findRichText: true), findsWidgets);
        expect(find.textContaining('3º B, portero automático 12#', findRichText: true), findsWidgets);
        expect(find.textContaining('+34 600 999 888', findRichText: true), findsWidgets);
        expect(find.text('Control de tensión'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'CaregiverDashboard pending request expands to show all basic care info',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final mockClients = MockClientRepository();
        mockClients.seedClient(buildRichClientProfile());
        DependencyInjection.clients = mockClients;
        DependencyInjection.caregivers = MockCaregiverRepository();
        DependencyInjection.reviews = MockReviewRepository();
        DependencyInjection.jobOffers = MockJobOfferRepository();
        DependencyInjection.chats = MockChatRepository();

        final pendingBooking = makeBooking(
          id: 'pending_1',
          status: BookingStatus.pending,
        )..careChecklist = [
            CareChecklistItem(id: 't1', title: 'Merienda sin azúcar'),
          ];
        await mockRepo.createBooking(pendingBooking);

        final auth = AuthNotifier()
          ..isAuthenticated = true
          ..currentUserId = 'cg_1'
          ..currentRole = 'caregiver';
        final config = ConfigNotifier();
        final bookingNotifier = BookingNotifier()..updateAuth('cg_1', 'caregiver');

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthNotifier>.value(value: auth),
              ChangeNotifierProvider<ConfigNotifier>.value(value: config),
              ChangeNotifierProvider<BookingNotifier>.value(value: bookingNotifier),
              ChangeNotifierProvider<CaregiverNotifier>(create: (_) => CaregiverNotifier()),
              ChangeNotifierProvider<LocationNotifier>(create: (_) => LocationNotifier()),
              ChangeNotifierProvider<JobOfferNotifier>(create: (_) => JobOfferNotifier()),
              ChangeNotifierProvider<ChatNotifier>(create: (_) => ChatNotifier()),
            ],
            child: const MaterialApp(
              home: Scaffold(body: CaregiverDashboard()),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));

        final toggleFinder = find.byKey(const Key('toggle_care_info_pending_1'));
        await tester.ensureVisible(toggleFinder);
        await tester.pump();
        expect(toggleFinder, findsOneWidget);
        expect(find.text('Merienda sin azúcar'), findsNothing);

        await tester.tap(toggleFinder);
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.textContaining('Antonio García', findRichText: true), findsWidgets);
        expect(find.textContaining('Usa andador', findRichText: true), findsWidgets);
        expect(find.textContaining('Alzhéimer leve', findRichText: true), findsWidgets);
        expect(find.textContaining('Dieta blanda sin sal', findRichText: true), findsWidgets);
        expect(find.text('Merienda sin azúcar'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'BookingsScreen in caregiver mode displays expandable basic care info for pending requests',
      (tester) async {
        final mockClients = MockClientRepository();
        mockClients.seedClient(buildRichClientProfile());
        DependencyInjection.clients = mockClients;
        DependencyInjection.caregivers = MockCaregiverRepository();
        DependencyInjection.reviews = MockReviewRepository();
        DependencyInjection.jobOffers = MockJobOfferRepository();
        DependencyInjection.chats = MockChatRepository();

        final pendingBooking = makeBooking(
          id: 'pending_res_1',
          status: BookingStatus.pending,
        )..careChecklist = [
            CareChecklistItem(id: 't2', title: 'Preparar cena ligera'),
          ];
        await mockRepo.createBooking(pendingBooking);

        final auth = AuthNotifier()
          ..isAuthenticated = true
          ..currentUserId = 'cg_1'
          ..currentRole = 'caregiver';
        final config = ConfigNotifier();
        final bookingNotifier = BookingNotifier()..updateAuth('cg_1', 'caregiver');

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthNotifier>.value(value: auth),
              ChangeNotifierProvider<ConfigNotifier>.value(value: config),
              ChangeNotifierProvider<BookingNotifier>.value(value: bookingNotifier),
              ChangeNotifierProvider<CaregiverNotifier>(create: (_) => CaregiverNotifier()),
              ChangeNotifierProvider<LocationNotifier>(create: (_) => LocationNotifier()),
              ChangeNotifierProvider<JobOfferNotifier>(create: (_) => JobOfferNotifier()),
              ChangeNotifierProvider<ChatNotifier>(create: (_) => ChatNotifier()),
            ],
            child: const MaterialApp(home: BookingsScreen()),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));

        final toggleFinder = find.byKey(const Key('toggle_care_info_pending_res_1'));
        await tester.ensureVisible(toggleFinder);
        await tester.pump();
        expect(toggleFinder, findsOneWidget);
        expect(find.text('Preparar cena ligera'), findsNothing);

        await tester.tap(toggleFinder);
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.textContaining('Antonio García', findRichText: true), findsWidgets);
        expect(find.textContaining('Dieta blanda sin sal', findRichText: true), findsWidgets);
        expect(find.textContaining('3º B, portero automático 12#', findRichText: true), findsWidgets);
        expect(find.text('Preparar cena ligera'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
