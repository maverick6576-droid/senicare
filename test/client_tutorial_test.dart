import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/repositories/repositories.dart';
import 'package:senicare/screens/main_layout.dart';
import 'package:senicare/widgets/spotlight_tutorial_overlay.dart';

void main() {
  late MockClientRepository clientRepo;
  late MockCaregiverRepository caregiverRepo;
  late MockBookingRepository bookingRepo;
  late MockChatRepository chatRepo;
  late MockJobOfferRepository jobOfferRepo;
  late MockAuthRepository authRepo;

  setUp(() {
    ClientTutorialService.useLocalFileStorage = false;
    CaregiverTutorialService.useLocalFileStorage = false;
    authRepo = MockAuthRepository();
    clientRepo = MockClientRepository();
    caregiverRepo = MockCaregiverRepository();
    bookingRepo = MockBookingRepository();
    chatRepo = MockChatRepository();
    jobOfferRepo = MockJobOfferRepository();

    DependencyInjection.auth = authRepo;
    DependencyInjection.clients = clientRepo;
    DependencyInjection.caregivers = caregiverRepo;
    DependencyInjection.bookings = bookingRepo;
    DependencyInjection.chats = chatRepo;
    DependencyInjection.jobOffers = jobOfferRepo;
    DependencyInjection.reviews = MockReviewRepository();
    DependencyInjection.reports = MockReportRepository();
    DependencyInjection.stats = _TestStatsRepository();
  });

  tearDown(() {
    ClientTutorialService.useLocalFileStorage = false;
    CaregiverTutorialService.useLocalFileStorage = false;
  });

  Widget buildMainLayoutApp({
    required AuthNotifier auth,
    ConfigNotifier? config,
    Size size = const Size(412, 840),
  }) {
    final effectiveConfig = config ?? ConfigNotifier();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthNotifier>.value(value: auth),
        ChangeNotifierProvider<LocationNotifier>(
          create: (_) => LocationNotifier(),
        ),
        ChangeNotifierProvider<ConfigNotifier>.value(value: effectiveConfig),
        ChangeNotifierProxyProvider2<AuthNotifier, LocationNotifier,
            CaregiverNotifier>(
          create: (_) => CaregiverNotifier(),
          update: (_, a, l, n) {
            n!.updateLocation(
              a.currentClient?.latitude ?? l.latitude ?? 40.4168,
              a.currentClient?.longitude ?? l.longitude ?? -3.7038,
            );
            return n;
          },
        ),
        ChangeNotifierProxyProvider2<AuthNotifier, LocationNotifier,
            JobOfferNotifier>(
          create: (_) => JobOfferNotifier(),
          update: (_, a, _, n) {
            if (a.isAuthenticated && a.currentUserId != null) {
              n!.initForClient(a.currentUserId!);
            }
            return n!;
          },
        ),
        ChangeNotifierProxyProvider<AuthNotifier, BookingNotifier>(
          create: (_) => BookingNotifier(),
          update: (_, a, n) {
            n!.updateAuth(a.currentUserId, a.currentRole);
            return n;
          },
        ),
        ChangeNotifierProxyProvider<AuthNotifier, ChatNotifier>(
          create: (_) => ChatNotifier(),
          update: (_, a, n) {
            n!.updateAuth(a.currentUserId, a.currentRole);
            return n;
          },
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.getTheme(effectiveConfig.seniorMode),
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: const MainLayout(),
        ),
      ),
    );
  }

  group('Client interactive spotlight tutorial', () {
    testWidgets(
      'auto-starts once for first-time clients, persists Exit, and does not re-open',
      (tester) async {
        await clientRepo.updateClient('client_first_1', {
          'name': 'Familia Gómez',
          'homeAddress': 'Calle Mayor 10, Madrid',
          'latitude': 40.4168,
          'longitude': -3.7038,
          'onboardingComplete': true,
          'clientTutorialSeen': false,
        });
        final profile = await clientRepo.getClient('client_first_1');

        final auth = AuthNotifier()
          ..isAuthenticated = true
          ..currentUserId = 'client_first_1'
          ..currentRole = 'client'
          ..onboardingComplete = true
          ..currentClient = profile;

        await tester.pumpWidget(buildMainLayoutApp(auth: auth));
        await tester.pump(const Duration(milliseconds: 300));

        // Spotlight overlay auto-starts on step 1
        expect(find.byKey(const Key('client_tutorial_overlay')), findsOneWidget);
        expect(find.byKey(const Key('caregiver_tutorial_overlay')), findsNothing);
        expect(find.text('Paso 1 de 9'), findsOneWidget);
        expect(find.text('¡Bienvenido a SeniCare!'), findsOneWidget);
        expect(
          find.byKey(const Key('client_tutorial_exit_button')),
          findsOneWidget,
        );

        // Background navigation taps are intercepted while overlay is active
        await tester.tap(find.text('Reservas'), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 150));
        expect(find.byKey(const Key('client_tutorial_overlay')), findsOneWidget);
        expect(find.text('Paso 1 de 9'), findsOneWidget);

        // Tapping Exit dismisses overlay and persists clientTutorialSeen = true
        await tester.tap(find.byKey(const Key('client_tutorial_exit_button')));
        await tester.pump(const Duration(milliseconds: 250));

        expect(find.byKey(const Key('client_tutorial_overlay')), findsNothing);
        final updated = await clientRepo.getClient('client_first_1');
        expect(updated?.hasSeenClientTutorial, isTrue);

        // Returning client does NOT get auto-started tutorial
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(buildMainLayoutApp(auth: auth));
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byKey(const Key('client_tutorial_overlay')), findsNothing);
      },
    );

    testWidgets(
      'walks through all 9 steps across every client flow with Previous/Next and finishes cleanly',
      (tester) async {
        await clientRepo.updateClient('client_walk_1', {
          'name': 'Elena Ruiz',
          'homeAddress': 'Paseo del Prado 2, Madrid',
          'latitude': 40.415,
          'longitude': -3.694,
          'onboardingComplete': true,
          'clientTutorialSeen': true,
        });
        final profile = await clientRepo.getClient('client_walk_1');

        final auth = AuthNotifier()
          ..isAuthenticated = true
          ..currentUserId = 'client_walk_1'
          ..currentRole = 'client'
          ..onboardingComplete = true
          ..currentClient = profile;

        await tester.pumpWidget(buildMainLayoutApp(auth: auth));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byKey(const Key('client_tutorial_overlay')), findsNothing);

        // Open from top-right "Más opciones" menu
        await tester.tap(find.byTooltip('Más opciones'));
        await tester.pumpAndSettle();
        expect(find.text('Tutorial guiado paso a paso'), findsOneWidget);

        await tester.tap(find.text('Tutorial guiado paso a paso'));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('client_tutorial_overlay')), findsOneWidget);
        expect(find.text('Paso 1 de 9'), findsOneWidget);

        const expectedTitles = <String>[
          '¡Bienvenido a SeniCare!',
          'Busca cuidadores de tu zona',
          'Elige con total tranquilidad',
          'Publica tu oferta y elige candidato',
          'Agenda y pago protegido',
          'Código PIN/QR y Diario del Cuidado',
          'Habla directo como en WhatsApp',
          'Ficha familiar y checklist',
          'Modo Senior y tutorial arriba',
        ];
        const stepsWithAlwaysMountedTarget = <int>{0, 1, 3, 4, 6, 7, 8};

        for (var i = 0; i < expectedTitles.length; i++) {
          expect(find.text('Paso ${i + 1} de 9'), findsOneWidget);
          expect(find.text(expectedTitles[i]), findsOneWidget);

          if (stepsWithAlwaysMountedTarget.contains(i)) {
            final paint = tester.widget<CustomPaint>(
              find
                  .descendant(
                    of: find.byKey(const Key('client_tutorial_overlay')),
                    matching: find.byWidgetPredicate(
                      (w) => w is CustomPaint && w.painter is SpotlightPainter,
                    ),
                  )
                  .first,
            );
            expect(
              (paint.painter as SpotlightPainter).highlightRect,
              isNotNull,
              reason: 'Step ${i + 1} should illuminate a target spotlight rect',
            );
          }

          if (i < expectedTitles.length - 1) {
            await tester
                .tap(find.byKey(const Key('client_tutorial_next_button')));
            await tester.pumpAndSettle();
          }
        }

        // Navigate backwards with Anterior and verify previous step
        expect(
          find.byKey(const Key('client_tutorial_prev_button')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('client_tutorial_prev_button')));
        await tester.pumpAndSettle();
        expect(find.text('Paso 8 de 9'), findsOneWidget);
        expect(find.text('Ficha familiar y checklist'), findsOneWidget);

        // Return to step 9 and finish
        await tester.tap(find.byKey(const Key('client_tutorial_next_button')));
        await tester.pumpAndSettle();
        expect(find.text('¡Entendido, empezar!'), findsOneWidget);

        await tester.tap(find.byKey(const Key('client_tutorial_next_button')));
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.byKey(const Key('client_tutorial_overlay')), findsNothing);
      },
    );

    testWidgets(
      'launches from top-right SettingsScreen and renders without overflow in Senior Mode on 360x640',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await clientRepo.updateClient('client_senior_1', {
          'name': 'Carmen López',
          'homeAddress': 'Gran Vía 20, Madrid',
          'onboardingComplete': true,
          'clientTutorialSeen': true,
        });
        final profile = await clientRepo.getClient('client_senior_1');

        final auth = AuthNotifier()
          ..isAuthenticated = true
          ..currentUserId = 'client_senior_1'
          ..currentRole = 'client'
          ..onboardingComplete = true
          ..currentClient = profile;
        final config = ConfigNotifier()..seniorMode = true;

        await tester.pumpWidget(
          buildMainLayoutApp(
            auth: auth,
            config: config,
            size: const Size(360, 640),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        // Open top-right SettingsScreen ("Ajustes y Cuenta")
        await tester.tap(find.byTooltip('Ajustes y Cuenta'));
        await tester.pumpAndSettle();

        expect(find.text('🎓 Ayuda y Tutorial para Familias'), findsOneWidget);
        expect(find.text('Tutorial guiado paso a paso'), findsOneWidget);

        await tester.tap(find.text('Tutorial guiado paso a paso'));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('client_tutorial_overlay')), findsOneWidget);
        expect(find.text('Paso 1 de 9'), findsOneWidget);

        // Step through all 9 steps under Senior Mode on a compact 360x640 phone
        for (var i = 1; i < 9; i++) {
          await tester.tap(find.byKey(const Key('client_tutorial_next_button')));
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('Paso ${i + 1} de 9'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }

        // Exit closes cleanly
        await tester.tap(find.byKey(const Key('client_tutorial_exit_button')));
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.byKey(const Key('client_tutorial_overlay')), findsNothing);
      },
    );
  });
}

class _TestStatsRepository implements FirestoreStatsRepository {
  @override
  Future<int> getAccumulatedHours(String clientId, String caregiverId) async =>
      0;

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

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
