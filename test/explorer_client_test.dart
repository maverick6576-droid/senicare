import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';
import 'package:senicare/screens/screens.dart';

class _TestStatsRepository implements FirestoreStatsRepository {
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

class _TestClientRepository implements ClientRepository {
  @override
  Future<ClientProfile?> getClient(String id) async => null;

  @override
  Future<void> updateClient(String id, Map<String, dynamic> data) async {}
}

class _FlakyCaregiverRepository extends MockCaregiverRepository {
  bool shouldFail = false;

  @override
  Future<List<CaregiverProfile>> fetchCaregivers({
    String specialty = 'Todos',
    String query = '',
    bool refresh = false,
    double? mapLat,
    double? mapLng,
  }) async {
    if (shouldFail) {
      throw Exception('Simulated network outage');
    }
    return super.fetchCaregivers(
      specialty: specialty,
      query: query,
      refresh: refresh,
      mapLat: mapLat,
      mapLng: mapLng,
    );
  }
}

class _RacingCaregiverRepository extends MockCaregiverRepository {
  final Completer<List<CaregiverProfile>> firstCompleter = Completer();
  int _callCount = 0;

  @override
  Future<List<CaregiverProfile>> fetchCaregivers({
    String specialty = 'Todos',
    String query = '',
    bool refresh = false,
    double? mapLat,
    double? mapLng,
  }) async {
    _callCount++;
    if (_callCount == 2) {
      return firstCompleter.future;
    }
    return super.fetchCaregivers(
      specialty: specialty,
      query: query,
      refresh: refresh,
      mapLat: mapLat,
      mapLng: mapLng,
    );
  }
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
    mockAuth = MockAuthRepository();
    mockCaregivers = MockCaregiverRepository();
    mockBookings = MockBookingRepository();
    mockChats = MockChatRepository();
    mockJobOffers = MockJobOfferRepository();
    mockReviews = MockReviewRepository();

    DependencyInjection.auth = mockAuth;
    DependencyInjection.caregivers = mockCaregivers;
    DependencyInjection.clients = _TestClientRepository();
    DependencyInjection.bookings = mockBookings;
    DependencyInjection.chats = mockChats;
    DependencyInjection.jobOffers = mockJobOffers;
    DependencyInjection.reviews = mockReviews;
    DependencyInjection.stats = _TestStatsRepository();
  });

  Widget buildExplorerHarness({
    required AuthNotifier auth,
    required CaregiverNotifier caregiverNotifier,
    ConfigNotifier? config,
    LocationNotifier? location,
    BookingNotifier? bookingNotifier,
  }) {
    final loc = location ??
        (LocationNotifier()
          ..latitude = 41.3851
          ..longitude = 2.1734);
    final cfg = config ?? ConfigNotifier();
    final bookings = bookingNotifier ?? BookingNotifier();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthNotifier>.value(value: auth),
        ChangeNotifierProvider<LocationNotifier>.value(value: loc),
        ChangeNotifierProvider<ConfigNotifier>.value(value: cfg),
        ChangeNotifierProvider<CaregiverNotifier>.value(value: caregiverNotifier),
        ChangeNotifierProvider<BookingNotifier>.value(value: bookings),
        ChangeNotifierProvider<JobOfferNotifier>(
          create: (_) => JobOfferNotifier(),
        ),
        ChangeNotifierProvider<ChatNotifier>(create: (_) => ChatNotifier()),
      ],
      child: const MaterialApp(home: ExplorerScreen()),
    );
  }

  group('CaregiverNotifier improvements & bug fixes', () {
    test('handles fetch errors cleanly and recovers on refresh', () async {
      final flaky = _FlakyCaregiverRepository()..shouldFail = true;
      DependencyInjection.caregivers = flaky;

      final notifier = CaregiverNotifier();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(notifier.isFetchingCaregivers, isFalse);
      expect(notifier.errorMessage, isNotNull);
      expect(notifier.caregivers, isEmpty);

      flaky.shouldFail = false;
      await notifier.refreshCaregivers();

      expect(notifier.isFetchingCaregivers, isFalse);
      expect(notifier.errorMessage, isNull);
      expect(notifier.caregivers.length, 3);
    });

    test('deduplicates pagination and stops loadMore when no new IDs arrive',
        () async {
      final notifier = CaregiverNotifier();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(notifier.caregivers.length, 3);
      await notifier.loadMoreCaregivers();

      // Mock repository returns the same 3 items; notifier must deduplicate and stop.
      expect(notifier.caregivers.length, 3);
      expect(notifier.hasMoreCaregivers, isFalse);
    });

    test('toggleSpecialty toggles back to Todos and supports extended catalog',
        () async {
      await mockCaregivers.updateProfile('cg_alz', {
        'name': 'Laura Gómez',
        'title': 'Especialista Alzheimer',
        'bio': 'Experiencia en deterioro cognitivo y estimulación.',
        'pricePerHour': 55.0,
        'specialties': ['Alzheimer', 'Demencia'],
        'verificationStatus': 'approved',
        'latitude': 41.3851,
        'longitude': 2.1734,
        'maxDistanceRadius': 10.0,
        'imageUrl': '',
      });

      final notifier = CaregiverNotifier()..updateLocation(41.3851, 2.1734);
      await Future.delayed(const Duration(milliseconds: 50));

      // >=50 filter is "Sin límite", so 55€/h specialist stays visible.
      expect(
        notifier.filteredCaregivers.any((c) => c.id == 'cg_alz'),
        isTrue,
      );

      notifier.toggleSpecialty('Alzheimer');
      await Future.delayed(const Duration(milliseconds: 50));
      expect(notifier.selectedSpecialty, 'Alzheimer');
      expect(notifier.filteredCaregivers.length, 1);

      notifier.toggleSpecialty('Alzheimer');
      await Future.delayed(const Duration(milliseconds: 50));
      expect(notifier.selectedSpecialty, 'Todos');
      expect(notifier.filteredCaregivers.length, 4);
    });

    test('discards stale async responses during rapid query updates', () async {
      final racing = _RacingCaregiverRepository();
      DependencyInjection.caregivers = racing;

      final notifier = CaregiverNotifier();
      await Future.delayed(const Duration(milliseconds: 30));

      // Call 2 hangs on firstCompleter
      notifier.setSearchQuery('Slow');
      // Call 3 supersedes Call 2 immediately and completes fast with 'Javier'
      notifier.setSearchQuery('Javier');
      await Future.delayed(const Duration(milliseconds: 40));

      expect(notifier.caregivers.map((c) => c.name), ['Javier Domínguez']);

      // Complete stale slow call with Elena; must be ignored!
      racing.firstCompleter.complete([
        CaregiverProfile(
          id: 'stale',
          name: 'Stale User',
          title: 'Test',
          bio: '',
          pricePerHour: 15,
          rating: 5,
          reviewsCount: 1,
          distance: '1 km',
          imageUrl: '',
          specialties: const [],
          verified: true,
          verificationStatus: 'approved',
          availableSlots: const {},
        ),
      ]);
      await Future.delayed(const Duration(milliseconds: 30));

      expect(notifier.caregivers.map((c) => c.name), ['Javier Domínguez']);
    });
  });

  group('ExplorerScreen UI, filters & Senior Mode', () {
    testWidgets(
      'syncs pre-existing search, preserves price/rating filters when toggling Más cercanos, and clears filters',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final auth = AuthNotifier()
          ..isAuthenticated = true
          ..currentUserId = 'client_1'
          ..currentRole = 'client'
          ..currentClient = ClientProfile(
            id: 'client_1',
            name: 'Lucía Pérez',
            phone: '+34600111222',
            patientDetails: 'Mi padre',
            homeAddress: 'Carrer d’Aragó 200, Barcelona',
            latitude: 41.3851,
            longitude: 2.1734,
            onboardingComplete: true,
          );

        final notifier = CaregiverNotifier()
          ..updateLocation(41.3851, 2.1734)
          ..setMaxPriceFilter(20.0);
        notifier.setSearchQuery('Elena');

        await tester.pumpWidget(
          buildExplorerHarness(auth: auth, caregiverNotifier: notifier),
        );
        await tester.pump(const Duration(milliseconds: 300));

        // Header shows client address and keeps search input in sync with notifier
        expect(find.text('Carrer d’Aragó 200, Barcelona'), findsOneWidget);
        expect(find.text('Elena'), findsWidgets);
        expect(find.text('Filtros (1)'), findsOneWidget);

        // Clearing search via X restores list
        await tester.tap(find.byTooltip('Limpiar búsqueda'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(notifier.searchQuery, '');

        // Toggling 'Más cercanos' keeps maxPriceFilter == 20.0 (does NOT wipe user filters!)
        await tester.tap(find.text('Más cercanos'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(notifier.sortOption, CaregiverSortOption.distanceAsc);
        expect(notifier.maxPriceFilter, 20.0);
        expect(find.text('Filtros (2)'), findsOneWidget);

        // María (22€) is excluded because maxPriceFilter is still 20€
        expect(find.text('María Fernández'), findsNothing);

        // Cleaning filters brings María back
        await tester.tap(find.text('Limpiar'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('María Fernández'), findsOneWidget);
      },
    );

    testWidgets(
      'handles far client location with Ampliar zona, shows error recovery, and renders cleanly in Senior Mode on compact viewport',
      (tester) async {
        tester.view.physicalSize = const Size(380, 780);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final flaky = _FlakyCaregiverRepository()..shouldFail = true;
        DependencyInjection.caregivers = flaky;

        final auth = AuthNotifier()
          ..isAuthenticated = true
          ..currentUserId = 'client_madrid'
          ..currentRole = 'client'
          ..currentClient = ClientProfile(
            id: 'client_madrid',
            name: 'Carlos Ruiz',
            phone: '+34600333444',
            patientDetails: 'Mi madre',
            homeAddress: 'Gran Vía 10, Madrid',
            latitude: 40.4168,
            longitude: -3.7038,
            onboardingComplete: true,
          );

        final config = ConfigNotifier()..toggleSeniorMode(true);
        final notifier = CaregiverNotifier()..updateLocation(40.4168, -3.7038);

        await tester.pumpWidget(
          buildExplorerHarness(
            auth: auth,
            caregiverNotifier: notifier,
            config: config,
          ),
        );
        await tester.pump(const Duration(milliseconds: 200));

        // 1. Error state with Reintentar
        expect(find.text('Reintentar'), findsOneWidget);

        // 2. Recover: no caregivers within Madrid radius of Barcelona mocks -> Ampliar zona
        flaky.shouldFail = false;
        await tester.tap(find.text('Reintentar'));
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.text('Ampliar zona'), findsOneWidget);
        await tester.tap(find.text('Ampliar zona'));
        await tester.pump(const Duration(milliseconds: 200));

        expect(notifier.ignoreDistanceLimit, isTrue);
        expect(find.text('María Fernández'), findsOneWidget);

        await tester.scrollUntilVisible(
          find.text('Elena Sanz'),
          250,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.text('Elena Sanz'), findsOneWidget);

        // 3. Open filter sheet and verify zero overflow + live count + clean close
        await tester.tap(find.byKey(const Key('explorer_filter_button')));
        await tester.pumpAndSettle();

        expect(find.text('Sin límite'), findsOneWidget);
        expect(find.text('Ver 3 cuidadores'), findsOneWidget);
        await tester.tap(find.text('Ver 3 cuidadores'));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'GuidedMatchingWizard maps selected care need to valid specialty without empty results',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final auth = AuthNotifier()
          ..isAuthenticated = true
          ..currentUserId = 'client_bcn'
          ..currentRole = 'client'
          ..currentClient = ClientProfile(
            id: 'client_bcn',
            name: 'Sofía Vidal',
            phone: '+34600555666',
            patientDetails: 'Mi abuelo',
            homeAddress: 'Barcelona',
            latitude: 41.3851,
            longitude: 2.1734,
            onboardingComplete: true,
          );

        final notifier = CaregiverNotifier()..updateLocation(41.3851, 2.1734);

        await tester.pumpWidget(
          buildExplorerHarness(auth: auth, caregiverNotifier: notifier),
        );
        await tester.pump(const Duration(milliseconds: 200));

        await tester.tap(find.text('¿No sabes a quién elegir?'));
        await tester.pumpAndSettle();

        // Step 1 -> Step 2
        await tester.tap(find.text('Continuar'));
        await tester.pumpAndSettle();

        // Pick 'Movilidad reducida' (which used to emit invalid 'Movilidad reducida') and unselect default
        await tester.tap(find.text('Movilidad reducida'));
        await tester.pump();
        await tester.tap(find.text('Acompañamiento'));
        await tester.pump();

        // Step 2 -> Step 3 -> Results
        await tester.tap(find.text('Continuar'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ver cuidadores compatibles'));
        await tester.pumpAndSettle();

        expect(find.text('Tus 3 cuidadores ideales'), findsOneWidget);

        await tester.tap(find.text('Aplicar filtros al explorador'));
        await tester.pumpAndSettle();

        // Properly mapped to 'Movilidad' instead of 'Movilidad reducida', showing real results!
        expect(notifier.selectedSpecialty, 'Movilidad');
        expect(notifier.filteredCaregivers, isNotEmpty);
        expect(find.text('Elena Sanz'), findsOneWidget);
      },
    );
  });
}
