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
  Future<int> getAccumulatedHours(String clientId, String caregiverId) async => 0;

  @override
  Future<List<Map<String, dynamic>>> getCaregiverClientStats(String caregiverId) async => [];

  @override
  Future<void> addCompletedHours(String clientId, String caregiverId, int hoursToAdd) async {}
}

class _TestClientRepository implements ClientRepository {
  @override
  Future<ClientProfile?> getClient(String id) async => null;

  @override
  Future<void> updateClient(String id, Map<String, dynamic> data) async {}
}

class _ErrorableJobOfferRepository extends MockJobOfferRepository {
  bool shouldError = false;
  int streamClientCalls = 0;

  @override
  Stream<List<JobOffer>> streamClientOffers(String clientId, {int limit = 10}) async* {
    streamClientCalls++;
    if (shouldError) {
      throw Exception('Simulated stream error');
    }
    yield* super.streamClientOffers(clientId, limit: limit);
  }
}

void main() {
  late _ErrorableJobOfferRepository mockJobOffers;
  late MockAuthRepository mockAuth;
  late MockCaregiverRepository mockCaregivers;
  late MockBookingRepository mockBookings;
  late MockChatRepository mockChats;
  late MockReviewRepository mockReviews;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    mockJobOffers = _ErrorableJobOfferRepository();
    mockAuth = MockAuthRepository();
    mockCaregivers = MockCaregiverRepository();
    mockBookings = MockBookingRepository();
    mockChats = MockChatRepository();
    mockReviews = MockReviewRepository();

    DependencyInjection.jobOffers = mockJobOffers;
    DependencyInjection.auth = mockAuth;
    DependencyInjection.caregivers = mockCaregivers;
    DependencyInjection.clients = _TestClientRepository();
    DependencyInjection.bookings = mockBookings;
    DependencyInjection.chats = mockChats;
    DependencyInjection.reviews = mockReviews;
    DependencyInjection.stats = _TestStatsRepository();
  });

  AuthNotifier makeClientAuth() {
    return AuthNotifier()
      ..isAuthenticated = true
      ..currentUserId = 'client_1'
      ..currentRole = 'client'
      ..currentClient = ClientProfile(
        id: 'client_1',
        name: 'Lucía Pérez',
        phone: '+34600111222',
        patientDetails: 'Mi padre',
        homeAddress: 'Carrer de Balmes 120, Barcelona',
        latitude: 41.392,
        longitude: 2.159,
        onboardingComplete: true,
      );
  }

  JobOffer makeOffer({
    String id = '',
    String clientId = 'client_1',
    String title = 'Acompañamiento de tarde',
    double pricePerHour = 15.0,
    int totalHours = 4,
    DateTime? startDate,
    DateTime? createdAt,
    JobOfferStatus status = JobOfferStatus.open,
    bool isUrgent = false,
  }) {
    return JobOffer(
      id: id,
      clientId: clientId,
      clientName: 'Lucía Pérez',
      clientLatitude: 41.392,
      clientLongitude: 2.159,
      title: title,
      description: 'Paseo tranquilo y ayuda con la merienda.',
      pricePerHour: pricePerHour,
      totalHours: totalHours,
      isRecurring: false,
      startDate: startDate ?? DateTime.now().add(const Duration(days: 2)),
      status: status,
      isUrgent: isUrgent,
      urgencyBonusRate: isUrgent ? 0.10 : 0.0,
      createdAt: createdAt ?? DateTime.now(),
    );
  }

  Widget wrapWithProviders({
    required Widget child,
    AuthNotifier? auth,
    JobOfferNotifier? jobOfferNotifier,
    ConfigNotifier? config,
  }) {
    final loc = LocationNotifier()
      ..latitude = 41.392
      ..longitude = 2.159;

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthNotifier>.value(value: auth ?? makeClientAuth()),
        ChangeNotifierProvider<LocationNotifier>.value(value: loc),
        ChangeNotifierProvider<ConfigNotifier>.value(value: config ?? ConfigNotifier()),
        ChangeNotifierProvider<JobOfferNotifier>.value(value: jobOfferNotifier ?? JobOfferNotifier()),
        ChangeNotifierProvider<CaregiverNotifier>(create: (_) => CaregiverNotifier()),
        ChangeNotifierProvider<BookingNotifier>(create: (_) => BookingNotifier()),
        ChangeNotifierProvider<ChatNotifier>(create: (_) => ChatNotifier()),
      ],
      child: MaterialApp(
        theme: AppTheme.getTheme((config ?? ConfigNotifier()).seniorMode),
        home: child,
      ),
    );
  }

  group('JobOfferNotifier client state, error recovery & pagination', () {
    test('captures client stream error and recovers on refreshClientOffers', () async {
      mockJobOffers.shouldError = true;
      final notifier = JobOfferNotifier();
      notifier.initForClient('client_1');

      await Future.delayed(const Duration(milliseconds: 50));

      expect(notifier.isLoadingClientOffers, isFalse);
      expect(notifier.clientError, isNotNull);
      expect(notifier.clientOffers, isEmpty);

      mockJobOffers.shouldError = false;
      await mockJobOffers.createOffer(makeOffer(title: 'Oferta recuperada'));
      await notifier.refreshClientOffers();

      expect(notifier.clientError, isNull);
      expect(notifier.clientOffers.length, 1);
      expect(notifier.clientOffers.first.title, 'Oferta recuperada');

      notifier.dispose();
    });

    test('paginates client offers and stops re-subscribing when no more pages exist', () async {
      final base = DateTime(2026, 6, 1, 10, 0);
      for (int i = 0; i < 12; i++) {
        await mockJobOffers.createOffer(
          makeOffer(
            title: 'Oferta $i',
            createdAt: base.add(Duration(minutes: i)),
          ),
        );
      }

      final notifier = JobOfferNotifier();
      notifier.initForClient('client_1');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(notifier.clientOffers.length, 10);
      expect(notifier.clientOffers.first.title, 'Oferta 11');
      expect(notifier.hasMoreClientOffers, isTrue);

      final callsBeforeLoadMore = mockJobOffers.streamClientCalls;
      notifier.loadMoreClientOffers();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(notifier.clientOffers.length, 12);
      expect(notifier.hasMoreClientOffers, isFalse);
      expect(mockJobOffers.streamClientCalls, callsBeforeLoadMore + 1);

      // Subsequent loadMore calls do nothing when hasMoreClientOffers is false.
      notifier.loadMoreClientOffers();
      await Future.delayed(const Duration(milliseconds: 30));
      expect(mockJobOffers.streamClientCalls, callsBeforeLoadMore + 1);

      notifier.dispose();
    });

    test('rejectApplication and cancelOffer update pending applications and offer status', () async {
      final offerId = await mockJobOffers.createOffer(makeOffer(title: 'Cuidado mañana'));
      await mockJobOffers.applyToOffer(
        JobApplication(
          id: 'app_1',
          offerId: offerId,
          caregiverId: 'cg_1',
          caregiverName: 'Elena Ruiz',
          caregiverImageUrl: '',
          caregiverRating: 4.9,
          caregiverReviewsCount: 15,
          message: 'Encantada de ayudar',
          proposedPrice: 15.0,
          appliedAt: DateTime.now(),
        ),
      );
      await mockJobOffers.applyToOffer(
        JobApplication(
          id: 'app_2',
          offerId: offerId,
          caregiverId: 'cg_2',
          caregiverName: 'Carlos Vidal',
          caregiverImageUrl: '',
          caregiverRating: 4.7,
          caregiverReviewsCount: 9,
          message: 'Disponible',
          proposedPrice: 16.0,
          appliedAt: DateTime.now(),
        ),
      );

      final notifier = JobOfferNotifier();
      notifier.initForClient('client_1');
      await Future.delayed(const Duration(milliseconds: 60));

      await notifier.rejectApplication(offerId, 'app_1');
      var apps = await mockJobOffers.streamOfferApplications(offerId).first;
      expect(apps.firstWhere((a) => a.id == 'app_1').status, JobApplicationStatus.rejected);
      expect(apps.firstWhere((a) => a.id == 'app_2').status, JobApplicationStatus.pending);

      await notifier.cancelOffer(offerId);
      final updatedOffer = await mockJobOffers.getOffer(offerId);
      expect(updatedOffer?.status, JobOfferStatus.cancelled);
      apps = await mockJobOffers.streamOfferApplications(offerId).first;
      expect(apps.firstWhere((a) => a.id == 'app_2').status, JobApplicationStatus.rejected);

      notifier.dispose();
    });
  });

  group('OffersHubScreen Client UI', () {
    testWidgets('shows guided empty state CTA when no active offers exist', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        wrapWithProviders(child: const OffersHubScreen()),
      );
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.text('Aún no tienes ofertas activas'), findsOneWidget);
      expect(find.text('Publicar mi primera oferta'), findsOneWidget);
      expect(find.text('Activas (0)'), findsOneWidget);
      expect(find.text('Historial (0)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps inProgress offers in Activas with human Spanish statuses and zero Senior Mode overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await mockJobOffers.createOffer(
        makeOffer(
          title: 'Paseo matinal',
          status: JobOfferStatus.inProgress,
        ),
      );
      final openWithAppId = await mockJobOffers.createOffer(
        makeOffer(
          title: 'Compañía de noche',
          status: JobOfferStatus.open,
          isUrgent: true,
        ),
      );
      await mockJobOffers.applyToOffer(
        JobApplication(
          id: 'app_cg1',
          offerId: openWithAppId,
          caregiverId: 'cg_1',
          caregiverName: 'Elena Ruiz',
          caregiverImageUrl: '',
          caregiverRating: 4.9,
          caregiverReviewsCount: 11,
          message: 'Puedo ir hoy mismo',
          proposedPrice: 15.0,
          appliedAt: DateTime.now(),
        ),
      );
      await mockJobOffers.createOffer(
        makeOffer(
          title: 'Oferta ya pasada',
          startDate: DateTime.now().subtract(const Duration(days: 2)),
          status: JobOfferStatus.open,
        ),
      );

      final config = ConfigNotifier()..toggleSeniorMode(true);

      await tester.pumpWidget(
        wrapWithProviders(
          config: config,
          child: const OffersHubScreen(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      // Both open & inProgress stay in Activas, with clear Spanish labels (no 'INPROGRESS' jargon).
      expect(find.text('Activas (2)'), findsOneWidget);
      expect(find.text('Historial (1)'), findsOneWidget);
      expect(find.text('Paseo matinal'), findsOneWidget);
      expect(find.text('Cuidador confirmado'), findsOneWidget);
      expect(find.text('Compañía de noche'), findsOneWidget);
      expect(find.text('Revisar 1 candidato'), findsOneWidget);
      expect(find.textContaining('INPROGRESS'), findsNothing);
      expect(tester.takeException(), isNull);

      // Switch to Historial and check expired offer + Republish button.
      await tester.tap(find.text('Historial (1)'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Oferta ya pasada'),
        150,
        scrollable: find.descendant(
          of: find.byType(TabBarView),
          matching: find.byType(Scrollable),
        ).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('Oferta ya pasada'), findsOneWidget);
      expect(find.text('Fecha pasada'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Volver a publicar'),
        150,
        scrollable: find.descendant(
          of: find.byType(TabBarView),
          matching: find.byType(Scrollable),
        ).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('Volver a publicar'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Tapping 'Volver a publicar' opens CreateOfferScreen pre-filled.
      await tester.tap(find.text('Volver a publicar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Volver a Publicar Oferta'), findsOneWidget);
      expect(find.text('Oferta ya pasada'), findsWidgets);
    });
  });

  group('CreateOfferScreen & OfferDetailScreen client flows', () {
    testWidgets('CreateOfferScreen handles quick template, Spanish comma decimal price, and publishes cleanly', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        wrapWithProviders(child: const CreateOfferScreen()),
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Acompañamiento y paseo'));
      await tester.pump();

      expect(find.textContaining('Total aproximado de la oferta: 42 €'), findsOneWidget);

      // Replace price with comma decimal '14,5'
      final priceField = find.widgetWithText(TextFormField, 'Precio (€/h)');
      await tester.enterText(priceField, '14,5');
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('Publicar Oferta Gratis'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      await tester.tap(find.text('Publicar Oferta Gratis'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final created = await mockJobOffers.streamClientOffers('client_1').first;
      expect(created.length, 1);
      expect(created.first.title, 'Acompañamiento y paseo');
      expect(created.first.pricePerHour, 14.5);
      expect(created.first.totalHours, 3);
      expect(tester.takeException(), isNull);
    });

    testWidgets('OfferDetailScreen client view supports chatting, discarding candidate, and cancelling offer', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(380, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final offerId = await mockJobOffers.createOffer(
        makeOffer(title: 'Ayuda en compras', pricePerHour: 14.0, totalHours: 3),
      );
      await mockJobOffers.applyToOffer(
        JobApplication(
          id: 'app_cand_1',
          offerId: offerId,
          caregiverId: 'cg_1',
          caregiverName: 'Elena Ruiz',
          caregiverImageUrl: '',
          caregiverRating: 4.9,
          caregiverReviewsCount: 18,
          message: 'Vivo cerca y tengo disponibilidad.',
          proposedPrice: 16.0,
          appliedAt: DateTime.now(),
        ),
      );
      final offer = (await mockJobOffers.getOffer(offerId))!;

      await tester.pumpWidget(
        wrapWithProviders(child: OfferDetailScreen(offer: offer)),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Elena Ruiz'), findsOneWidget);
      expect(find.text('Propone +2.00 €/h sobre tu oferta'), findsOneWidget);
      expect(find.text('Chatear'), findsOneWidget);
      expect(find.text('Ver perfil'), findsOneWidget);

      // Discard candidate with confirmation
      await tester.scrollUntilVisible(
        find.text('Descartar candidatura'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      await tester.tap(find.text('Descartar candidatura'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.text('Descartar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final apps = await mockJobOffers.streamOfferApplications(offerId).first;
      expect(apps.first.status, JobApplicationStatus.rejected);
      expect(find.text('Candidatura descartada'), findsOneWidget);

      // Let the confirmation SnackBar dismiss before interacting with the lower action button.
      await tester.pump(const Duration(seconds: 5));

      // Cancel offer with confirmation
      await tester.scrollUntilVisible(
        find.text('Retirar / Cancelar Oferta'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      await tester.tap(find.text('Retirar / Cancelar Oferta'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.text('Sí, retirar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final updated = await mockJobOffers.getOffer(offerId);
      expect(updated?.status, JobOfferStatus.cancelled);
      expect(tester.takeException(), isNull);
    });

    testWidgets('OfferDetailScreen Chatear opens ChatScreen and JobOfferPaymentScreen renders Senior Mode cleanly', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final offerId = await mockJobOffers.createOffer(
        makeOffer(title: 'Ayuda compras y paseo', pricePerHour: 15.0, totalHours: 4),
      );
      final app = JobApplication(
        id: 'app_chat_1',
        offerId: offerId,
        caregiverId: 'cg_1',
        caregiverName: 'Elena Ruiz',
        caregiverImageUrl: '',
        caregiverRating: 4.9,
        caregiverReviewsCount: 18,
        message: 'Estoy disponible.',
        proposedPrice: 15.0,
        appliedAt: DateTime.now(),
      );
      await mockJobOffers.applyToOffer(app);
      final offer = (await mockJobOffers.getOffer(offerId))!;
      final config = ConfigNotifier()..toggleSeniorMode(true);

      await tester.pumpWidget(
        wrapWithProviders(config: config, child: OfferDetailScreen(offer: offer)),
      );
      await tester.pump(const Duration(milliseconds: 200));

      // Verify payment navigation & checklist works without overflow
      await tester.scrollUntilVisible(
        find.textContaining('Elegir a Elena'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      await tester.tap(find.textContaining('Elegir a Elena'));
      await tester.pumpAndSettle();

      expect(find.text('Confirmar y Pagar'), findsOneWidget);
      expect(find.text('Total protegido'), findsOneWidget);
      expect(find.text('61.80 €'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Añadir'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Dar merienda a las 17h');
      await tester.tap(find.text('Añadir'));
      await tester.pump();

      expect(find.text('Dar merienda a las 17h'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Go back and verify Chatear navigates cleanly to ChatScreen
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Chatear'),
        -180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Chatear'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chatear'));
      await tester.pumpAndSettle();

      expect(find.byType(ChatScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
