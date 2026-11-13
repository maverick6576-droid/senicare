import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';
import 'package:senicare/screens/payment_screen.dart';
import 'package:senicare/widgets/widgets.dart';

class _TestStatsRepo implements FirestoreStatsRepository {
  int addedHoursCalls = 0;
  int lastAddedHours = 0;

  @override
  Future<int> getAccumulatedHours(String clientId, String caregiverId) async => 0;

  @override
  Future<List<Map<String, dynamic>>> getCaregiverClientStats(
    String caregiverId,
  ) async =>
      [];

  @override
  Future<void> addCompletedHours(
    String clientId,
    String caregiverId,
    int hoursToAdd,
  ) async {
    addedHoursCalls++;
    lastAddedHours = hoursToAdd;
  }
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    ClientTutorialService.useLocalFileStorage = false;
    DependencyInjection.auth = MockAuthRepository();
    DependencyInjection.clients = MockClientRepository();
    DependencyInjection.families = MockFamilyRepository();
    DependencyInjection.caregivers = MockCaregiverRepository();
    DependencyInjection.bookings = MockBookingRepository(filterByUser: true);
    DependencyInjection.chats = MockChatRepository();
    DependencyInjection.reviews = MockReviewRepository();
    DependencyInjection.reports = MockReportRepository();
    DependencyInjection.jobOffers = MockJobOfferRepository();
    DependencyInjection.stats = _TestStatsRepo();
  });

  group('ClientPaymentMethod & StripeService helpers', () {
    test('exposes platform-specific wallet names and Stripe backend preferences', () {
      expect(
        ClientPaymentMethod.platformPay.labelForPlatform(TargetPlatform.iOS),
        'Apple Pay',
      );
      expect(
        ClientPaymentMethod.platformPay.labelForPlatform(TargetPlatform.android),
        'Google Pay',
      );

      expect(ClientPaymentMethod.platformPay.backendId, 'wallet');
      expect(ClientPaymentMethod.cardAndLink.backendId, 'card_link');
      expect(ClientPaymentMethod.bizum.backendId, 'bizum');
      expect(ClientPaymentMethod.klarna.backendId, 'klarna');
      expect(ClientPaymentMethod.revolutPay.backendId, 'revolut_pay');
      expect(ClientPaymentMethod.sepaDebit.backendId, 'sepa_debit');
      expect(ClientPaymentMethod.allSheet.backendId, 'auto');

      expect(ClientPaymentMethod.bizum.usesExternalCheckout, isTrue);
      expect(ClientPaymentMethod.klarna.usesExternalCheckout, isFalse);
      expect(ClientPaymentMethod.sepaDebit.isDelayedBankMethod, isTrue);
      expect(ClientPaymentMethod.cardAndLink.isDelayedBankMethod, isFalse);

      expect(ClientPaymentMethod.klarna.paymentMethodOrder.first, 'klarna');
      expect(ClientPaymentMethod.sepaDebit.paymentMethodOrder.first, 'sepa_debit');
      expect(ClientPaymentMethod.revolutPay.paymentMethodOrder.first, 'revolut_pay');
    });

    test('StripeService safe test mode & merchant defaults do not throw before init', () {
      expect(StripeService.isTestMode, isTrue);
      expect(StripeService.merchantIdentifier, 'merchant.com.senicare.app');
      expect(StripeService.returnUrl, 'senicare://stripe-redirect');
    });

    test('Booking preserves paymentMethodType and paymentStatus in Firestore map & copyWith', () {
      final booking = Booking(
        id: 'bk_pay_1',
        clientId: 'cli_1',
        caregiverId: 'cg_1',
        caregiverName: 'Elena Ruiz',
        day: '2026-12-20',
        slot: '10:00-12:00',
        cost: 30,
        clientFee: 0.9,
        caregiverCommissionRate: 0.15,
        caregiverCommissionAmount: 4.5,
        caregiverPayout: 25.5,
        totalPaid: 30.9,
        paymentMethodType: 'bizum',
        paymentStatus: 'paid',
      );

      final map = booking.toFirestore();
      expect(map['paymentMethodType'], 'bizum');
      expect(map['paymentStatus'], 'paid');

      final updated = booking.copyWith(
        paymentMethodType: 'sepa_debit',
        paymentStatus: 'processing',
      );
      expect(updated.paymentMethodType, 'sepa_debit');
      expect(updated.paymentStatus, 'processing');
    });
  });

  group('Payment UI widgets & 360x640 Senior Mode layout', () {
    testWidgets('PaymentMethodSelectorCard allows selecting all alternatives without overflow on 360x640', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      ClientPaymentMethod current = ClientPaymentMethod.platformPay;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            platform: TargetPlatform.iOS,
            useMaterial3: true,
            splashFactory: InkRipple.splashFactory,
          ),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: PaymentMethodSelectorCard(
                  selectedMethod: current,
                  seniorMode: true,
                  platformPaySupported: true,
                  onChanged: (next) => setState(() => current = next),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Apple Pay'), findsOneWidget);
      expect(find.text('Bizum'), findsOneWidget);
      expect(find.text('Tarjeta o Link'), findsOneWidget);
      expect(find.text('Klarna (3 cuotas sin intereses)'), findsOneWidget);
      expect(find.text('Revolut Pay'), findsOneWidget);
      expect(find.text('Transferencia / Adeudo SEPA'), findsOneWidget);
      expect(
        find.text('Cartera digital verificada en este dispositivo ✓'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('payment_method_bizum')));
      await tester.pumpAndSettle();
      expect(current, ClientPaymentMethod.bizum);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('payment_method_sepaDebit')),
        200,
      );
      await tester.tap(find.byKey(const ValueKey('payment_method_sepaDebit')));
      await tester.pumpAndSettle();
      expect(current, ClientPaymentMethod.sepaDebit);
      expect(tester.takeException(), isNull);
    });

    testWidgets('PrimaryCheckoutActionBar renders native PlatformPayButton when wallet supported & selected', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.getTheme(false),
          home: Scaffold(
            body: Column(
              children: [
                PrimaryCheckoutActionBar(
                  selectedMethod: ClientPaymentMethod.platformPay,
                  platformPaySupported: true,
                  isProcessing: false,
                  fallbackButtonLabel: 'Pagar 30,90 €',
                  onPressed: () {},
                ),
                const SizedBox(height: 12),
                PrimaryCheckoutActionBar(
                  selectedMethod: ClientPaymentMethod.bizum,
                  platformPaySupported: true,
                  isProcessing: false,
                  fallbackButtonLabel: 'Pagar 30,90 € · Bizum',
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(PlatformPayButton), findsOneWidget);
      expect(find.text('Pagar 30,90 € · Bizum'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('PaymentScreen integrates alternative methods smoothly on 360x640 Senior Mode', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final auth = AuthNotifier()
        ..isAuthenticated = true
        ..currentUserId = 'cli_pay_1'
        ..currentRole = 'client';
      final config = ConfigNotifier()..toggleSeniorMode(true);
      final booking = BookingNotifier();
      final location = LocationNotifier();

      final caregiver = CaregiverProfile(
        id: 'cg_1',
        name: 'Elena Ruiz',
        title: 'Auxiliar Geriatría',
        bio: 'Experiencia en cuidados a domicilio.',
        pricePerHour: 15.0,
        rating: 4.9,
        reviewsCount: 12,
        distance: '1.2 km',
        imageUrl: '',
        specialties: const ['Acompañamiento'],
        verified: true,
        availableSlots: const {},
        stripeAccountId: 'acct_test_123',
      );
      final slots = [
        TimeSlot(id: 's1', dateTime: DateTime(2026, 12, 20, 10, 0)),
        TimeSlot(id: 's2', dateTime: DateTime(2026, 12, 20, 11, 0)),
      ];

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthNotifier>.value(value: auth),
            ChangeNotifierProvider<ConfigNotifier>.value(value: config),
            ChangeNotifierProvider<BookingNotifier>.value(value: booking),
            ChangeNotifierProvider<LocationNotifier>.value(value: location),
          ],
          child: MaterialApp(
            theme: AppTheme.getTheme(config.seniorMode),
            home: PaymentScreen(
              caregiver: caregiver,
              dateString: '2026-12-20',
              slots: slots,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final klarnaTile = find.byKey(const ValueKey('payment_method_klarna'));
      await tester.scrollUntilVisible(
        klarnaTile,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(klarnaTile);
      await tester.pumpAndSettle();
      await tester.tap(klarnaTile);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Klarna (3 cuotas sin intereses)'),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    });

    test('Booking.toFirestore conserva clientFeeRate y CheckoutFlowResult sessionId', () {
      final booking = Booking(
        id: 'b_fee',
        clientId: 'fam_1',
        caregiverId: 'cg_1',
        caregiverName: 'Lucía',
        day: '2026-12-20',
        slot: '10:00-12:00',
        cost: 24.0,
        clientFee: 0.72,
        clientFeeRate: 0.03,
        caregiverCommissionRate: 0.18,
        caregiverCommissionAmount: 4.32,
        caregiverPayout: 19.68,
        totalPaid: 24.72,
        status: BookingStatus.pendingPayment,
        escrowStatus: 'none',
        createdAt: DateTime(2026, 12, 1),
      );
      final map = booking.toFirestore();
      expect(map['clientFeeRate'], 0.03);
      expect(map['escrowStatus'], 'none');

      const result = CheckoutFlowResult(
        outcome: 'success',
        paymentIntentId: 'pi_123',
        paymentMethodType: 'bizum',
        sessionId: 'cs_test_abc',
      );
      expect(result.sessionId, 'cs_test_abc');
      expect(result.paymentIntentId, 'pi_123');
    });

    test('BookingNotifier.releaseEscrow en modo Mock suma horas nocturnas una sola vez', () async {
      final statsRepo = _TestStatsRepo();
      DependencyInjection.stats = statsRepo;
      final bookingNotifier = BookingNotifier();
      bookingNotifier.bookings = [
        Booking(
          id: 'b_night',
          clientId: 'fam_1',
          caregiverId: 'cg_1',
          caregiverName: 'Lucía',
          day: '2026-12-20',
          slot: '22:00-06:00',
          cost: 80.0,
          clientFee: 2.40,
          clientFeeRate: 0.03,
          caregiverCommissionRate: 0.18,
          caregiverCommissionAmount: 14.40,
          caregiverPayout: 65.60,
          totalPaid: 82.40,
          status: BookingStatus.completed,
          escrowStatus: 'held',
          createdAt: DateTime(2026, 12, 1),
        ),
      ];

      await bookingNotifier.releaseEscrow('b_night');

      expect(statsRepo.addedHoursCalls, 1);
      expect(statsRepo.lastAddedHours, 8);
      expect(bookingNotifier.bookings.first.escrowStatus, 'released');
    });
  });
}
