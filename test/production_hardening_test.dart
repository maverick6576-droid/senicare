import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';
import 'package:senicare/screens/admin/admin_2fa_screen.dart';
import 'package:senicare/screens/auth_screen.dart';
import 'package:senicare/screens/onboarding/client_onboarding_screen.dart';

class _TestStatsRepo implements FirestoreStatsRepository {
  @override
  Future<int> getAccumulatedHours(String clientId, String caregiverId) async => 0;

  @override
  Future<List<Map<String, dynamic>>> getCaregiverClientStats(
    String caregiverId,
  ) async =>
      const [];

  @override
  Future<void> addCompletedHours(
    String clientId,
    String caregiverId,
    int hoursToAdd,
  ) async {}
}

void main() {
  setUpAll(() {
    AppTheme.useSystemFonts = true;
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
  });

  tearDownAll(() {
    AppTheme.useSystemFonts = false;
  });

  group('Bloque 3 - AppTheme & Senior Mode button constraints', () {
    testWidgets(
      'AppTheme.getTheme(true) allows ElevatedButton & OutlinedButton side-by-side in Row & AlertDialog without unbounded overflow at 360x640',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final theme = AppTheme.getTheme(true);
        expect(theme.elevatedButtonTheme.style?.minimumSize?.resolve({})?.width, 0);
        expect(theme.elevatedButtonTheme.style?.minimumSize?.resolve({})?.height, 56);
        expect(theme.outlinedButtonTheme.style?.minimumSize?.resolve({})?.width, 0);
        expect(theme.outlinedButtonTheme.style?.minimumSize?.resolve({})?.height, 56);

        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {},
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {},
                          child: const Text('Confirmar'),
                        ),
                      ),
                    ],
                  ),
                  AlertDialog(
                    title: const Text('Aviso'),
                    actions: [
                      OutlinedButton(
                        onPressed: () {},
                        child: const Text('No'),
                      ),
                      ElevatedButton(
                        onPressed: () {},
                        child: const Text('Sí'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Cancelar'), findsOneWidget);
        expect(find.text('Confirmar'), findsOneWidget);
      },
    );
  });

  group('Bloque 3 - Lifecycle dispose & screen rendering checks', () {
    testWidgets('AuthScreen mounts and disposes without leaking errors', (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AuthNotifier()),
            ChangeNotifierProvider(create: (_) => ConfigNotifier()),
          ],
          child: const MaterialApp(home: AuthScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('SeniCare'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('ClientOnboardingScreen mounts and disposes controllers cleanly', (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AuthNotifier()),
            ChangeNotifierProvider(create: (_) => ConfigNotifier()),
          ],
          child: const MaterialApp(home: ClientOnboardingScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Completar Perfil'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Admin2FAScreen handles non-Firebase mode safely and disposes cleanly', (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AuthNotifier()),
            ChangeNotifierProvider(create: (_) => ConfigNotifier()),
          ],
          child: const MaterialApp(home: Admin2FAScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Seguridad Administrador'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    test('Booking.scheduledEndTime handles overnight shift in Booking engine test coverage', () {
      final b = Booking(
        id: 'bk_night',
        clientId: 'c1',
        caregiverId: 'cg1',
        caregiverName: 'María',
        day: '12/11/2026',
        slot: '22:00-06:00',
        status: BookingStatus.confirmed,
        cost: 120.0,
        clientFee: 12.0,
        caregiverCommissionRate: 0.18,
        caregiverCommissionAmount: 21.6,
        caregiverPayout: 98.4,
        totalPaid: 132.0,
        escrowStatus: 'held',
        createdAt: DateTime(2026, 11, 12, 10),
      );
      expect(b.scheduledStartTime, DateTime(2026, 11, 12, 22));
      expect(b.scheduledEndTime, DateTime(2026, 11, 13, 6));
    });
  });
}
