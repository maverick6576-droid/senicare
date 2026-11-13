import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';
import 'package:senicare/screens/screens.dart';

class _TutorialMockStatsRepository implements FirestoreStatsRepository {
  @override
  Future<int> getAccumulatedHours(String clientId, String caregiverId) async =>
      0;

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
  ) async {}
}

class _SilentClientRepository implements ClientRepository {
  @override
  Future<ClientProfile?> getClient(String id) async => null;

  @override
  Future<void> updateClient(String id, Map<String, dynamic> data) async {}
}

void main() {
  late MockAuthRepository mockAuth;
  late MockCaregiverRepository mockCaregivers;
  late MockBookingRepository mockBookings;
  late MockChatRepository mockChats;
  late MockJobOfferRepository mockJobOffers;
  late MockReviewRepository mockReviews;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    CaregiverTutorialService.useLocalFileStorage = false;
    ClientTutorialService.useLocalFileStorage = false;
    mockAuth = MockAuthRepository();
    mockCaregivers = MockCaregiverRepository();
    mockBookings = MockBookingRepository();
    mockChats = MockChatRepository();
    mockJobOffers = MockJobOfferRepository();
    mockReviews = MockReviewRepository();

    DependencyInjection.auth = mockAuth;
    DependencyInjection.caregivers = mockCaregivers;
    DependencyInjection.clients = _SilentClientRepository();
    DependencyInjection.bookings = mockBookings;
    DependencyInjection.chats = mockChats;
    DependencyInjection.jobOffers = mockJobOffers;
    DependencyInjection.reviews = mockReviews;
    DependencyInjection.stats = _TutorialMockStatsRepository();
  });

  tearDown(() {
    CaregiverTutorialService.useLocalFileStorage = false;
    ClientTutorialService.useLocalFileStorage = false;
  });

  Widget buildMainLayoutApp({
    required AuthNotifier auth,
    ConfigNotifier? config,
  }) {
    final location = LocationNotifier()
      ..latitude = 41.3888
      ..longitude = 2.1589;
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthNotifier>.value(value: auth),
        ChangeNotifierProvider<LocationNotifier>.value(value: location),
        ChangeNotifierProvider<ConfigNotifier>.value(
          value: config ?? ConfigNotifier(),
        ),
        ChangeNotifierProvider<CaregiverNotifier>(
          create: (_) => CaregiverNotifier(),
        ),
        ChangeNotifierProxyProvider2<AuthNotifier, LocationNotifier,
            JobOfferNotifier>(
          create: (_) => JobOfferNotifier(),
          update: (_, a, loc, notifier) {
            if (a.currentRole == 'caregiver') {
              notifier!.initForCaregiver(
                a.currentCaregiver?.latitude ?? loc.latitude ?? 41.3888,
                a.currentCaregiver?.longitude ?? loc.longitude ?? 2.1589,
                a.currentCaregiver?.maxDistanceRadius ?? 20.0,
                caregiverId: a.currentUserId,
              );
            }
            return notifier!;
          },
        ),
        ChangeNotifierProxyProvider<AuthNotifier, BookingNotifier>(
          create: (_) => BookingNotifier(),
          update: (_, a, notifier) {
            notifier!.updateAuth(a.currentUserId, a.currentRole);
            return notifier;
          },
        ),
        ChangeNotifierProxyProvider<AuthNotifier, ChatNotifier>(
          create: (_) => ChatNotifier(),
          update: (_, a, notifier) {
            notifier!.updateAuth(a.currentUserId, a.currentRole);
            return notifier;
          },
        ),
      ],
      child: const MaterialApp(home: MainLayout()),
    );
  }

  group('Caregiver interactive spotlight tutorial', () {
    testWidgets(
      'auto-starts for first-time caregivers, persists Exit, and does not re-open for returning caregivers',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await mockCaregivers.updateProfile('cg_first', {
          'name': 'Carmen Ruiz',
          'title': 'Auxiliar',
          'bio': 'Cuidados con paciencia.',
          'pricePerHour': 16.0,
          'homeAddress': 'Calle Mayor 10, Madrid, Madrid, España',
          'latitude': 40.4168,
          'longitude': -3.7038,
          'imageUrl': '',
          'onboardingComplete': true,
          'caregiverTutorialSeen': false,
        });

        final auth = AuthNotifier()
          ..isAuthenticated = true
          ..currentUserId = 'cg_first'
          ..currentRole = 'caregiver'
          ..onboardingComplete = true;
        await auth.reloadRole();

        await tester.pumpWidget(buildMainLayoutApp(auth: auth));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('caregiver_tutorial_overlay')),
          findsOneWidget,
        );
        expect(find.text('Paso 1 de 11'), findsOneWidget);
        expect(find.text('¡Bienvenido/a a SeniCare!'), findsOneWidget);

        // User can exit immediately at any step
        await tester.tap(find.byKey(const Key('caregiver_tutorial_exit_button')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('caregiver_tutorial_overlay')),
          findsNothing,
        );

        final updated = await mockCaregivers.getCaregiver('cg_first');
        expect(updated?.hasSeenCaregiverTutorial, isTrue);

        // Re-mounting MainLayout as a returning user does not auto-open
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(buildMainLayoutApp(auth: auth));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('caregiver_tutorial_overlay')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'walks through all 11 caregiver flow steps from top-right menu across all tabs and finishes cleanly',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await mockCaregivers.updateProfile('cg_tour', {
          'name': 'Pedro Navarro',
          'title': 'Gerocultor',
          'bio': 'Experiencia hospitalaria y domiciliaria.',
          'pricePerHour': 17.0,
          'homeAddress': 'Carrer de Balmes, 100, Barcelona, España',
          'latitude': 41.392,
          'longitude': 2.155,
          'imageUrl': '',
          'onboardingComplete': true,
          'caregiverTutorialSeen': true,
        });

        final auth = AuthNotifier()
          ..isAuthenticated = true
          ..currentUserId = 'cg_tour'
          ..currentRole = 'caregiver'
          ..onboardingComplete = true;
        await auth.reloadRole();

        await tester.pumpWidget(buildMainLayoutApp(auth: auth));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('caregiver_tutorial_overlay')),
          findsNothing,
        );

        // Open top-right menu -> launch tutorial
        await tester.tap(find.byTooltip('Más opciones'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Tutorial guiado paso a paso'));
        await tester.pumpAndSettle();

        expect(find.text('Paso 1 de 11'), findsOneWidget);

        Future<void> nextAndVerify(String expectedStep, String expectedTitle) async {
          await tester.tap(find.byKey(const Key('caregiver_tutorial_next_button')));
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pumpAndSettle();
          expect(find.text(expectedStep), findsOneWidget);
          expect(find.text(expectedTitle), findsOneWidget);
        }

        await nextAndVerify('Paso 2 de 11', 'Marca tus días disponibles');
        await nextAndVerify('Paso 3 de 11', 'Controla lo que has cobrado');
        await nextAndVerify('Paso 4 de 11', 'Cómo hacer cada servicio');
        await nextAndVerify('Paso 5 de 11', 'Cuanto más cuidas, más ganas');
        await nextAndVerify('Paso 6 de 11', 'Encuentra ofertas cerca de ti');
        await nextAndVerify('Paso 7 de 11', 'Gestiona turnos e incidencias');
        await nextAndVerify('Paso 8 de 11', 'Habla directo con las familias');
        await nextAndVerify('Paso 9 de 11', 'Tu ficha y vista previa');
        await nextAndVerify('Paso 10 de 11', 'Documentos y cuenta bancaria');

        // Go back one step with Anterior
        await tester.tap(find.byKey(const Key('caregiver_tutorial_prev_button')));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        expect(find.text('Paso 9 de 11'), findsOneWidget);

        // Advance back to final step
        await nextAndVerify('Paso 10 de 11', 'Documentos y cuenta bancaria');
        await nextAndVerify('Paso 11 de 11', 'Letra grande y repetir tutorial');

        expect(find.text('¡Entendido, empezar!'), findsOneWidget);
        await tester.tap(find.byKey(const Key('caregiver_tutorial_next_button')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('caregiver_tutorial_overlay')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'launches caregiver tutorial when selected from top-right SettingsScreen and launches client tutorial in client mode',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await mockCaregivers.updateProfile('cg_settings', {
          'name': 'Ana Torres',
          'title': 'Enfermera',
          'bio': 'Atención personalizada.',
          'pricePerHour': 19.0,
          'homeAddress': 'Gran Via 50, Madrid, España',
          'latitude': 40.42,
          'longitude': -3.70,
          'imageUrl': '',
          'onboardingComplete': true,
          'caregiverTutorialSeen': true,
        });

        final auth = AuthNotifier()
          ..isAuthenticated = true
          ..currentUserId = 'cg_settings'
          ..currentRole = 'caregiver'
          ..onboardingComplete = true;
        await auth.reloadRole();

        await tester.pumpWidget(buildMainLayoutApp(auth: auth));
        await tester.pumpAndSettle();

        // Tap top-right Settings gear icon
        await tester.tap(find.byTooltip('Ajustes y Cuenta'));
        await tester.pumpAndSettle();

        expect(find.text('Tutorial guiado paso a paso'), findsOneWidget);
        await tester.tap(find.text('Tutorial guiado paso a paso'));
        await tester.pumpAndSettle();

        // Returned to MainLayout with tutorial running
        expect(
          find.byKey(const Key('caregiver_tutorial_overlay')),
          findsOneWidget,
        );
        expect(find.text('Paso 1 de 11'), findsOneWidget);

        // Client mode never triggers caregiver tutorial; it uses client tutorial instead.
        final clientAuth = AuthNotifier()
          ..isAuthenticated = true
          ..currentUserId = 'client_1'
          ..currentRole = 'client'
          ..onboardingComplete = true;

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(buildMainLayoutApp(auth: clientAuth));
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          find.byKey(const Key('caregiver_tutorial_overlay')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('client_tutorial_overlay')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('client_tutorial_exit_button')));
        await tester.pump(const Duration(milliseconds: 250));

        await tester.tap(find.byTooltip('Más opciones'));
        await tester.pumpAndSettle();
        expect(find.text('Tutorial guiado paso a paso'), findsOneWidget);
        await tester.tap(find.text('Tutorial guiado paso a paso'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('caregiver_tutorial_overlay')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('client_tutorial_overlay')),
          findsOneWidget,
        );
      },
    );
  });
}
