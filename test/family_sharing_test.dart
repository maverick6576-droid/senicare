import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';
import 'package:senicare/screens/bookings_screen.dart';
import 'package:senicare/screens/client_profile_edit_screen.dart';
import 'package:senicare/screens/job_offers/offer_detail_screen.dart';
import 'package:senicare/screens/onboarding/client_onboarding_screen.dart';
import 'package:senicare/screens/settings_screen.dart';

class _FamilyMockAuthRepo extends MockAuthRepository {
  String? forcedUid;

  @override
  String? get currentUserId => forcedUid ?? super.currentUserId;
}

class _TestStatsRepo implements FirestoreStatsRepository {
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
  ) async {}
}

void main() {
  late _FamilyMockAuthRepo authRepo;
  late MockClientRepository clientRepo;
  late MockFamilyRepository familyRepo;
  late MockBookingRepository bookingRepo;
  late MockJobOfferRepository jobOfferRepo;

  Future<void> seedFamilyOwner({
    String ownerUid = 'owner_uid',
    String ownerName = 'Carmen López',
    List<String> authorizedEmails = const [],
    Map<String, String> emailRoles = const {},
  }) async {
    await clientRepo.updateClient(ownerUid, {
      'name': ownerName,
      'phone': '600112233',
      'homeAddress': 'Calle Mayor 10, Madrid',
      'latitude': 40.4168,
      'longitude': -3.7038,
      'patientDetails': 'Padre de 84 años',
      'onboardingComplete': true,
      'defaultCareChecklist': ['💊 Medicación mañana', '🚶 Paseo suave'],
      'authorizedFamilyEmails': authorizedEmails,
      'familyEmailRoles': emailRoles,
      'ownerUid': ownerUid,
      'memberUids': [ownerUid],
      'members': {
        ownerUid: FamilyMember(
          uid: ownerUid,
          email: 'carmen@familia.com',
          displayName: ownerName,
          role: FamilyRole.admin,
          joinedVia: 'owner',
          isOwner: true,
        ).toMap(),
      },
      'clientTutorialSeen': true,
    });
  }

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    ClientTutorialService.useLocalFileStorage = false;
    authRepo = _FamilyMockAuthRepo();
    clientRepo = MockClientRepository();
    familyRepo = MockFamilyRepository();
    bookingRepo = MockBookingRepository(filterByUser: true);
    jobOfferRepo = MockJobOfferRepository();

    DependencyInjection.auth = authRepo;
    DependencyInjection.clients = clientRepo;
    DependencyInjection.families = familyRepo;
    DependencyInjection.caregivers = MockCaregiverRepository();
    DependencyInjection.bookings = bookingRepo;
    DependencyInjection.chats = MockChatRepository();
    DependencyInjection.reviews = MockReviewRepository();
    DependencyInjection.reports = MockReportRepository();
    DependencyInjection.jobOffers = jobOfferRepo;
    DependencyInjection.stats = _TestStatsRepo();
  });

  group('FamilyAccount models & invite extraction', () {
    test('extracts invite code from raw code, dashed format and share URL', () {
      expect(FamilyInvite.extractInviteCode('sn4k8p2m'), 'SN4K8P2M');
      expect(FamilyInvite.extractInviteCode('SN4K-8P2M'), 'SN4K8P2M');
      expect(
        FamilyInvite.extractInviteCode('https://senicare.app/join?code=ab12cd34'),
        'AB12CD34',
      );
      expect(
        FamilyInvite.extractInviteCode(
          'Únete a SeniCare aquí https://senicare.app/join?code=ZX90QW12',
        ),
        'ZX90QW12',
      );
      expect(FamilyInvite.extractInviteCode('abc'), isNull);
    });

    test('computes ClientProfile permissions strictly for owner, admin and collaborator', () {
      final profile = ClientProfile(
        id: 'owner_1',
        name: 'Familia López',
        phone: '600000000',
        homeAddress: 'Madrid',
        patientDetails: 'Cuidado diario',
        onboardingComplete: true,
        ownerUid: 'owner_1',
        memberUids: const ['owner_1', 'admin_2', 'collab_3'],
        members: const {
          'owner_1': FamilyMember(
            uid: 'owner_1',
            email: 'owner@test.com',
            displayName: 'Carmen',
            role: FamilyRole.admin,
            isOwner: true,
          ),
          'admin_2': FamilyMember(
            uid: 'admin_2',
            email: 'esposo@test.com',
            displayName: 'Carlos',
            role: FamilyRole.admin,
          ),
          'collab_3': FamilyMember(
            uid: 'collab_3',
            email: 'hermano@test.com',
            displayName: 'Pedro',
            role: FamilyRole.collaborator,
          ),
        },
      );

      expect(profile.canManagePayments('owner_1'), isTrue);
      expect(profile.canManagePayments('admin_2'), isTrue);
      expect(profile.canManageMembers('admin_2'), isTrue);
      expect(profile.canManageCareDetails('admin_2'), isTrue);

      expect(profile.roleFor('collab_3'), FamilyRole.collaborator);
      expect(profile.canManagePayments('collab_3'), isFalse);
      expect(profile.canManageMembers('collab_3'), isFalse);
      expect(profile.canManageCareDetails('collab_3'), isFalse);
      expect(profile.isMember('outsider'), isFalse);
      expect(profile.roleFor('outsider'), isNull);
    });
  });

  group('Auto-join by invited email & security guards', () {
    test('does NOT auto-join unverified email, then auto-joins once verified with configured role', () async {
      await seedFamilyOwner(
        authorizedEmails: ['pedro@gmail.com', 'lucia@icloud.com'],
        emailRoles: {
          'pedro@gmail.com': 'collaborator',
          'lucia@icloud.com': 'admin',
        },
      );

      // 1. Pedro signs up with email+password BEFORE verifying email -> no auto-join
      authRepo.forcedUid = 'pedro_uid';
      final pedroAuth = AuthNotifier()
        ..isAuthenticated = true
        ..currentUserId = 'pedro_uid'
        ..currentRole = 'client'
        ..configureFamilySessionOverrides(
          email: 'pedro@gmail.com',
          displayName: 'Pedro',
          emailVerified: false,
        );

      await pedroAuth.reloadRole();
      expect(pedroAuth.onboardingComplete, isFalse);
      expect(pedroAuth.effectiveClientId, 'pedro_uid');

      // 2. Pedro verifies email (or signs in with Google) -> auto-joins as Collaborator!
      pedroAuth.configureFamilySessionOverrides(
        email: 'pedro@gmail.com',
        displayName: 'Pedro',
        emailVerified: true,
      );
      await pedroAuth.reloadRole();

      expect(pedroAuth.onboardingComplete, isTrue);
      expect(pedroAuth.effectiveClientId, 'owner_uid');
      expect(pedroAuth.currentFamilyRole, FamilyRole.collaborator);
      expect(pedroAuth.canManageFamilyPayments, isFalse);
      expect(pedroAuth.canManageFamilyMembers, isFalse);
      expect(pedroAuth.isSharedFamilyMember, isTrue);

      // Personal tutorial state stays fresh for Pedro even though Owner already saw it!
      expect(await ClientTutorialService.hasSeen(pedroAuth), isFalse);
      await ClientTutorialService.markSeen(pedroAuth);
      expect(await ClientTutorialService.hasSeen(pedroAuth), isTrue);

      // 3. Lucia signs in with Apple/verified email -> auto-joins as secondary Admin!
      authRepo.forcedUid = 'lucia_uid';
      final luciaAuth = AuthNotifier()
        ..isAuthenticated = true
        ..currentUserId = 'lucia_uid'
        ..currentRole = 'client'
        ..configureFamilySessionOverrides(
          email: 'lucia@icloud.com',
          displayName: 'Lucía',
          emailVerified: true,
        );
      await luciaAuth.reloadRole();

      expect(luciaAuth.effectiveClientId, 'owner_uid');
      expect(luciaAuth.currentFamilyRole, FamilyRole.admin);
      expect(luciaAuth.canManageFamilyPayments, isTrue);
      expect(luciaAuth.canManageFamilyMembers, isTrue);

      final familyAfter = await clientRepo.getClient('owner_uid');
      expect(familyAfter!.authorizedFamilyEmails, isEmpty);
      expect(familyAfter.memberUids, containsAll(['owner_uid', 'pedro_uid', 'lucia_uid']));
    });
  });

  group('Invite code / share URL flow (incl. Apple Hide-My-Email)', () {
    test('joins via URL with Hide-My-Email, validates revoked/expired invites, promotes & leaves cleanly', () async {
      await seedFamilyOwner();

      final invite = await familyRepo.createInvite(
        familyId: 'owner_uid',
        familyName: 'Carmen López',
        role: FamilyRole.collaborator,
        maxUses: 2,
      );
      expect(invite.code.length, 8);
      expect(invite.shareUrl, contains(invite.code));

      // Apple Hide-My-Email user joins via pasted WhatsApp URL
      authRepo.forcedUid = 'apple_uid';
      final appleAuth = AuthNotifier()
        ..isAuthenticated = true
        ..currentUserId = 'apple_uid'
        ..currentRole = 'client'
        ..configureFamilySessionOverrides(
          email: 'xyz123@privaterelay.appleid.com',
          displayName: 'Tía Marta',
          emailVerified: true,
        );
      await appleAuth.reloadRole();
      expect(appleAuth.onboardingComplete, isFalse);

      final joined = await appleAuth.joinFamilyWithCode(invite.shareUrl);
      expect(joined.familyId, 'owner_uid');
      expect(joined.role, FamilyRole.collaborator);
      expect(appleAuth.onboardingComplete, isTrue);
      expect(appleAuth.effectiveClientId, 'owner_uid');
      expect(appleAuth.currentFamilyRole, FamilyRole.collaborator);

      // Admin promotes Marta to Admin
      await familyRepo.updateMemberRole(
        familyId: 'owner_uid',
        memberUid: 'apple_uid',
        newRole: FamilyRole.admin,
      );
      await appleAuth.refreshFamilyProfile();
      expect(appleAuth.currentFamilyRole, FamilyRole.admin);
      expect(appleAuth.canManageFamilyPayments, isTrue);

      // Owner cannot be demoted or removed
      expect(
        () => familyRepo.updateMemberRole(
          familyId: 'owner_uid',
          memberUid: 'owner_uid',
          newRole: FamilyRole.collaborator,
        ),
        throwsStateError,
      );

      // Revoked code cannot be used by a third user
      await familyRepo.revokeInvite(familyId: 'owner_uid', code: invite.code);
      expect(
        () => familyRepo.joinWithCode(
          uid: 'third_uid',
          codeOrUrl: invite.code,
        ),
        throwsStateError,
      );

      // Marta leaves family cleanly -> family remains intact for Owner
      await appleAuth.leaveSharedFamily();
      expect(appleAuth.effectiveClientId, 'apple_uid');
      expect(appleAuth.onboardingComplete, isFalse);
      final familyFinal = await clientRepo.getClient('owner_uid');
      expect(familyFinal!.isMember('owner_uid'), isTrue);
      expect(familyFinal.isMember('apple_uid'), isFalse);
    });
  });

  group('UI permission gates & 360x640 Senior Mode layout checks', () {
    Future<AuthNotifier> buildAuthFor({
      required String uid,
      required FamilyRole role,
      required String displayName,
    }) async {
      await seedFamilyOwner();
      if (uid != 'owner_uid') {
        final invite = await familyRepo.createInvite(
          familyId: 'owner_uid',
          familyName: 'Carmen López',
          role: role,
        );
        await familyRepo.joinWithCode(
          uid: uid,
          codeOrUrl: invite.code,
          email: '$uid@test.com',
          displayName: displayName,
        );
      }
      authRepo.forcedUid = uid;
      final auth = AuthNotifier()
        ..isAuthenticated = true
        ..currentUserId = uid
        ..currentRole = 'client'
        ..configureFamilySessionOverrides(
          email: '$uid@test.com',
          displayName: displayName,
          emailVerified: true,
        );
      await auth.reloadRole();
      return auth;
    }

    testWidgets('Admin can generate invite code in ClientProfileEditScreen without overflow on 360x640 Senior Mode', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final adminAuth = await buildAuthFor(
        uid: 'owner_uid',
        role: FamilyRole.admin,
        displayName: 'Carmen López',
      );
      final config = ConfigNotifier()..toggleSeniorMode(true);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthNotifier>.value(value: adminAuth),
            ChangeNotifierProvider<ConfigNotifier>.value(value: config),
          ],
          child: MaterialApp(
            theme: AppTheme.getTheme(config.seniorMode),
            home: const ClientProfileEditScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Editar perfil'), findsOneWidget);
      expect(find.textContaining('Tu rol actual: Administrador'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.textContaining('Generar código y enlace'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.textContaining('Generar código y enlace'));
      await tester.pumpAndSettle();

      expect(find.text('Copiar código'), findsOneWidget);
      expect(find.text('Copiar enlace'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Collaborator sees read-only profile controls & leave button in ClientProfileEditScreen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final collabAuth = await buildAuthFor(
        uid: 'collab_uid',
        role: FamilyRole.collaborator,
        displayName: 'Hermano Pedro',
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthNotifier>.value(value: collabAuth),
            ChangeNotifierProvider<ConfigNotifier>.value(value: ConfigNotifier()),
          ],
          child: MaterialApp(
            theme: AppTheme.getTheme(false),
            home: const ClientProfileEditScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Editar perfil'), findsNothing);
      expect(
        find.textContaining('Tu rol actual: Familiar colaborador'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('Salir de esta familia'),
        300,
      );
      expect(find.text('Salir de esta familia'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Collaborator in BookingsScreen views booking & care diary without escrow release or dispute controls', (
      tester,
    ) async {
      final collabAuth = await buildAuthFor(
        uid: 'collab_uid',
        role: FamilyRole.collaborator,
        displayName: 'Hermano Pedro',
      );

      await bookingRepo.createBooking(
        Booking(
          id: 'bk_shared_1',
          clientId: 'owner_uid',
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
          status: BookingStatus.confirmed,
          escrowStatus: 'held',
          bookingPin: '4821',
          checkInTime: DateTime(2026, 12, 20, 10),
          checkOutTime: DateTime(2026, 12, 20, 12),
          liveStatus: 'completed',
          careNotes: 'Paseo genial',
        ),
      );

      final bookingNotifier = BookingNotifier()
        ..updateAuth(collabAuth.effectiveClientId, 'client');

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthNotifier>.value(value: collabAuth),
            ChangeNotifierProvider<BookingNotifier>.value(value: bookingNotifier),
            ChangeNotifierProvider<ConfigNotifier>.value(value: ConfigNotifier()),
          ],
          child: MaterialApp(
            theme: AppTheme.getTheme(false),
            home: const BookingsScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Elena Ruiz'), findsOneWidget);
      expect(find.text('Confirmar y liberar pago'), findsNothing);
      expect(
        find.textContaining(
          'Pago en garantía pendiente de confirmación por el Administrador familiar',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Collaborator in OfferDetailScreen can chat with candidate but cannot hire or cancel offer', (
      tester,
    ) async {
      final collabAuth = await buildAuthFor(
        uid: 'collab_uid',
        role: FamilyRole.collaborator,
        displayName: 'Hermano Pedro',
      );

      final offerId = await jobOfferRepo.createOffer(
        JobOffer(
          id: '',
          clientId: 'owner_uid',
          clientName: 'Carmen López',
          clientLatitude: 40.4168,
          clientLongitude: -3.7038,
          title: 'Compañía de mañana',
          description: 'Necesitamos compañía para paseo.',
          pricePerHour: 15,
          totalHours: 3,
          isRecurring: false,
          startDate: DateTime.now().add(const Duration(days: 2)),
          status: JobOfferStatus.open,
          isUrgent: false,
          urgencyBonusRate: 0.0,
          createdAt: DateTime.now(),
        ),
      );

      await jobOfferRepo.applyToOffer(
        JobApplication(
          id: 'app_1',
          offerId: offerId,
          caregiverId: 'cg_1',
          caregiverName: 'Elena Ruiz',
          caregiverImageUrl: '',
          caregiverRating: 4.9,
          caregiverReviewsCount: 8,
          message: 'Disponible',
          proposedPrice: 15,
          appliedAt: DateTime.now(),
        ),
      );

      final createdOffer = (await jobOfferRepo.streamOffer(offerId).first)!;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthNotifier>.value(value: collabAuth),
            ChangeNotifierProvider<LocationNotifier>(
              create: (_) => LocationNotifier(),
            ),
            ChangeNotifierProvider<ConfigNotifier>(
              create: (_) => ConfigNotifier(),
            ),
            ChangeNotifierProvider<JobOfferNotifier>(
              create: (_) => JobOfferNotifier(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.getTheme(false),
            home: OfferDetailScreen(offer: createdOffer),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Chatear'), findsOneWidget);
      expect(find.textContaining('Elegir a Elena'), findsNothing);
      expect(find.textContaining('Retirar / Cancelar'), findsNothing);
      await tester.scrollUntilVisible(
        find.textContaining('Rol Familiar colaborador'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Rol Familiar colaborador'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ClientOnboardingScreen allows joining existing family with code dialog on 360x640', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await seedFamilyOwner();
      final invite = await familyRepo.createInvite(
        familyId: 'owner_uid',
        familyName: 'Carmen López',
        role: FamilyRole.collaborator,
      );

      authRepo.forcedUid = 'new_relative_uid';
      final newUserAuth = AuthNotifier()
        ..isAuthenticated = true
        ..currentUserId = 'new_relative_uid'
        ..currentRole = 'client'
        ..onboardingComplete = false
        ..configureFamilySessionOverrides(
          email: 'sobri@apple.com',
          displayName: 'Sobrino',
          emailVerified: true,
        );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthNotifier>.value(value: newUserAuth),
            ChangeNotifierProvider<ConfigNotifier>(
              create: (_) => ConfigNotifier(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.getTheme(false),
            home: const ClientOnboardingScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Unirme con código o enlace'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Código o enlace de invitación'),
        invite.shareUrl,
      );
      await tester.tap(find.text('Unirme'));
      await tester.pumpAndSettle();

      expect(newUserAuth.effectiveClientId, 'owner_uid');
      expect(newUserAuth.onboardingComplete, isTrue);
      expect(newUserAuth.currentFamilyRole, FamilyRole.collaborator);
      expect(tester.takeException(), isNull);
    });

    testWidgets('SettingsScreen shows shared family info & safe leave option', (
      tester,
    ) async {
      final collabAuth = await buildAuthFor(
        uid: 'collab_uid',
        role: FamilyRole.collaborator,
        displayName: 'Hermano Pedro',
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthNotifier>.value(value: collabAuth),
            ChangeNotifierProvider<ConfigNotifier>(
              create: (_) => ConfigNotifier(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.getTheme(false),
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Salir de esta familia compartida'),
        300,
      );
      expect(find.text('Salir de esta familia compartida'), findsOneWidget);
      expect(find.textContaining('Tu rol: Familiar colaborador'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
