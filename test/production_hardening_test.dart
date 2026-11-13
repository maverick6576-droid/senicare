import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';
import 'package:senicare/screens/admin/admin_2fa_screen.dart';
import 'package:senicare/screens/auth_screen.dart';
import 'package:senicare/screens/caregiver_detail_screen.dart';
import 'package:senicare/screens/job_offers/create_offer_screen.dart';
import 'package:senicare/screens/onboarding/client_onboarding_screen.dart';
import 'package:senicare/screens/payment_screen.dart';

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

  group('Bloque A - Hardening de Seguridad, Privacidad y Reglas de Precio', () {
    test('CaregiverProfile expone flags públicos sin filtrar documentos sensibles en toFirestore', () {
      final profileWithFlags = CaregiverProfile(
        id: 'cg_sec_1',
        name: 'Laura Gómez',
        title: 'Auxiliar',
        bio: 'Experiencia clínica',
        pricePerHour: 16.0,
        rating: 4.8,
        reviewsCount: 5,
        distance: '1.0 km',
        imageUrl: '',
        specialties: const ['Acompañamiento'],
        verified: true,
        availableSlots: const {},
        hasDniSubmitted: true,
        hasCriminalSubmitted: true,
      );
      expect(profileWithFlags.hasDni, isTrue);
      expect(profileWithFlags.hasCriminalRecord, isTrue);

      final profileWithLegacyUrls = CaregiverProfile(
        id: 'cg_sec_2',
        name: 'Laura Gómez',
        title: 'Auxiliar',
        bio: 'Experiencia clínica',
        pricePerHour: 16.0,
        rating: 4.8,
        reviewsCount: 5,
        distance: '1.0 km',
        imageUrl: '',
        specialties: const ['Acompañamiento'],
        verified: true,
        availableSlots: const {},
        dniUrl: 'https://private.example/dni.jpg',
        criminalRecordUrl: 'https://private.example/penales.pdf',
      );
      expect(profileWithLegacyUrls.hasDni, isTrue);
      expect(profileWithLegacyUrls.hasCriminalRecord, isTrue);

      final publicMap = profileWithLegacyUrls.toFirestore();
      expect(publicMap['hasDniSubmitted'], isTrue);
      expect(publicMap['hasCriminalSubmitted'], isTrue);
      expect(publicMap.containsKey('dniUrl'), isFalse);
      expect(publicMap.containsKey('criminalRecordUrl'), isFalse);
    });

    test('Review.toFirestore conserva bookingId para verificación en reglas', () {
      final review = Review(
        id: 'bk_verified_1',
        bookingId: 'bk_verified_1',
        caregiverId: 'cg_sec_1',
        clientId: 'cli_1',
        clientName: 'Ana',
        rating: 5.0,
        comment: 'Trato excelente.',
      );
      final map = review.toFirestore();
      expect(map['bookingId'], 'bk_verified_1');
      expect(map['caregiverId'], 'cg_sec_1');
      expect(map['clientId'], 'cli_1');
    });

    testWidgets(
      'PaymentScreen bloquea activación manual del descuento pack (<4h -> 4h+ Auto, >=4h -> -5% Activo)',
      (tester) async {
        final auth = AuthNotifier()
          ..isAuthenticated = true
          ..currentUserId = 'cli_sec_1'
          ..currentRole = 'client';
        final config = ConfigNotifier();
        final booking = BookingNotifier();
        final location = LocationNotifier();

        final caregiver = CaregiverProfile(
          id: 'cg_sec_pay',
          name: 'Elena Ruiz',
          title: 'Auxiliar Geriatría',
          bio: 'Cuidados a domicilio',
          pricePerHour: 15.0,
          rating: 4.9,
          reviewsCount: 10,
          distance: '1.0 km',
          imageUrl: '',
          specialties: const ['Acompañamiento'],
          verified: true,
          availableSlots: const {},
          stripeAccountId: 'acct_test_123',
        );

        final shortSlots = [
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
              home: PaymentScreen(
                caregiver: caregiver,
                dateString: '2026-12-20',
                slots: shortSlots,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(Switch), findsNothing);
        expect(find.text('4h+ Auto'), findsOneWidget);
        expect(find.text('-5% Activo'), findsNothing);

        final packSlots = [
          TimeSlot(id: 's1', dateTime: DateTime(2026, 12, 20, 10, 0)),
          TimeSlot(id: 's2', dateTime: DateTime(2026, 12, 20, 11, 0)),
          TimeSlot(id: 's3', dateTime: DateTime(2026, 12, 20, 12, 0)),
          TimeSlot(id: 's4', dateTime: DateTime(2026, 12, 20, 13, 0)),
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
              home: PaymentScreen(
                caregiver: caregiver,
                dateString: '2026-12-20',
                slots: packSlots,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(Switch), findsNothing);
        expect(find.text('-5% Activo'), findsOneWidget);
      },
    );

    test('MLKitService.evaluateIdentityOcrText valida DNI, NIE, Pasaporte y rechaza texto vacío/inválido', () async {
      final dniOk = MLKitService.evaluateIdentityOcrText(
        'ESPAÑA DOCUMENTO NACIONAL DE IDENTIDAD 12345678Z CARLOS MARTINEZ LOPEZ',
        'Carlos Martinez',
      );
      expect(dniOk.isApproved, isTrue);
      expect(dniOk.isManualReview, isFalse);

      final nieOk = MLKitService.evaluateIdentityOcrText(
        'NIE X1234567L MARIA GOMEZ RUIZ PERMISO DE RESIDENCIA',
        'Maria Gomez',
      );
      expect(nieOk.isApproved, isTrue);

      final passportOk = MLKitService.evaluateIdentityOcrText(
        'PASAPORTE ESPANA ANA BELEN TORRES',
        'Ana Torres',
      );
      expect(passportOk.isApproved, isTrue);

      final emptyResult = MLKitService.evaluateIdentityOcrText('', 'Carlos Martinez');
      expect(emptyResult.isApproved, isFalse);
      expect(emptyResult.isManualReview, isTrue);

      final garbageResult = MLKitService.evaluateIdentityOcrText(
        'TICKET SUPERMERCADO PAN LECHE 3.50 EUR',
        'Carlos Martinez',
      );
      expect(garbageResult.isApproved, isFalse);
      expect(garbageResult.isManualReview, isFalse);

      // En Windows/macOS/Linux/Web sin OCR móvil nunca debe auto-aprobar
      final desktopResult = await MLKitService.validateDNI('dummy.jpg', 'Carlos Martinez');
      expect(desktopResult.isApproved, isFalse);
      expect(desktopResult.isManualReview, isTrue);
    });

    test('CaregiverProfile serializa voiceIntroUrl en toFirestore con default vacío', () {
      final emptyVoice = CaregiverProfile(
        id: 'cg_1',
        name: 'Laura Díaz',
        title: 'Auxiliar',
        bio: 'Experiencia',
        pricePerHour: 14.0,
        rating: 4.9,
        reviewsCount: 5,
        distance: '2 km',
        imageUrl: '',
        specialties: const ['Compañía'],
        verified: true,
        availableSlots: const {},
      );
      expect(emptyVoice.voiceIntroUrl, '');
      expect(emptyVoice.toFirestore()['voiceIntroUrl'], '');

      final withVoice = CaregiverProfile(
        id: 'cg_2',
        name: 'Elena Ruiz',
        title: 'Enfermera',
        bio: 'Experiencia',
        pricePerHour: 16.0,
        rating: 4.9,
        reviewsCount: 5,
        distance: '1 km',
        imageUrl: '',
        voiceIntroUrl: 'https://firebasestorage.googleapis.com/v0/b/senicare/o/voice.m4a',
        specialties: const ['Movilidad'],
        verified: true,
        availableSlots: const {},
      );
      expect(
        withVoice.toFirestore()['voiceIntroUrl'],
        'https://firebasestorage.googleapis.com/v0/b/senicare/o/voice.m4a',
      );
    });

    testWidgets('AuthScreen bloquea registro si no se aceptan Términos y Privacidad', (tester) async {
      final auth = AuthNotifier();
      final config = ConfigNotifier();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthNotifier>.value(value: auth),
            ChangeNotifierProvider<ConfigNotifier>.value(value: config),
          ],
          child: const MaterialApp(home: AuthScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Registrarse'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'test_rgpd@senicare.es');
      await tester.enterText(find.byType(TextFormField).at(1), 'Password123!');
      await tester.enterText(find.byType(TextFormField).at(2), 'Password123!');

      final btn = find.text('Crear Cuenta Ahora');
      await tester.ensureVisible(btn);
      await tester.tap(btn);
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text('Debes aceptar los Términos de Servicio y la Política de Privacidad para crear tu cuenta.'),
        findsOneWidget,
      );
      expect(auth.isAuthenticated, isFalse);
    });

    testWidgets('ClientOnboardingScreen exige consentimiento explícito RGPD Art. 9', (tester) async {
      final auth = AuthNotifier()
        ..isAuthenticated = true
        ..currentUserId = 'cli_rgpd_1'
        ..currentRole = 'client';
      final config = ConfigNotifier();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthNotifier>.value(value: auth),
            ChangeNotifierProvider<ConfigNotifier>.value(value: config),
          ],
          child: const MaterialApp(home: ClientOnboardingScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final checkboxFinder = find.byType(CheckboxListTile);
      expect(checkboxFinder, findsOneWidget);
      expect(tester.widget<CheckboxListTile>(checkboxFinder).value, isFalse);

      // Rellenar campos obligatorios y enviar sin marcar el consentimiento
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'María Gómez');
      await tester.enterText(fields.at(1), '600123456');

      final provinceDrop = find.byType(DropdownButtonFormField<String>).last;
      await tester.ensureVisible(provinceDrop);
      await tester.tap(provinceDrop);
      await tester.pumpAndSettle();
      await tester.tap(find.text('A Coruña').last);
      await tester.pumpAndSettle();

      await tester.enterText(fields.at(2), 'Si');
      await tester.enterText(fields.at(3), 'Ma');

      final submitBtn = find.text('Finalizar Registro');
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text('Debes confirmar el consentimiento RGPD Art. 9 para el tratamiento de datos asistenciales.'),
        findsOneWidget,
      );
    });

    testWidgets('CreateOfferScreen expone configuración real de oferta recurrente semanal', (tester) async {
      final auth = AuthNotifier()
        ..isAuthenticated = true
        ..currentUserId = 'cli_offer_1'
        ..currentRole = 'client';
      final config = ConfigNotifier();
      final loc = LocationNotifier();
      final offers = JobOfferNotifier();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthNotifier>.value(value: auth),
            ChangeNotifierProvider<ConfigNotifier>.value(value: config),
            ChangeNotifierProvider<LocationNotifier>.value(value: loc),
            ChangeNotifierProvider<JobOfferNotifier>.value(value: offers),
          ],
          child: const MaterialApp(home: CreateOfferScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final listScrollable = find.byType(Scrollable).first;
      final switchFinder = find.text('Repetir todas las semanas');
      await tester.scrollUntilVisible(switchFinder, 300, scrollable: listScrollable);
      await tester.ensureVisible(switchFinder);
      await tester.pumpAndSettle();
      expect(switchFinder, findsOneWidget);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      final durationFinder = find.text('Duración: 4 semanas');
      await tester.scrollUntilVisible(durationFinder, 200, scrollable: listScrollable);
      await tester.ensureVisible(durationFinder);
      await tester.pumpAndSettle();
      expect(find.text('Lun'), findsOneWidget);
      expect(durationFinder, findsOneWidget);
    });

    testWidgets('CaregiverDetailScreen oculta presentación de voz fake si voiceIntroUrl está vacío', (tester) async {
      final auth = AuthNotifier()
        ..isAuthenticated = true
        ..currentUserId = 'cli_detail_1'
        ..currentRole = 'client';
      final config = ConfigNotifier();
      final loc = LocationNotifier();

      final caregiverNoVoice = CaregiverProfile(
        id: 'cg_no_voice',
        name: 'Elena Ruiz',
        title: 'Auxiliar Geriatría',
        bio: 'Cuidados a domicilio',
        pricePerHour: 15.0,
        rating: 4.9,
        reviewsCount: 10,
        distance: '1.0 km',
        imageUrl: '',
        voiceIntroUrl: '',
        specialties: const ['Acompañamiento'],
        verified: true,
        availableSlots: const {},
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthNotifier>.value(value: auth),
            ChangeNotifierProvider<ConfigNotifier>.value(value: config),
            ChangeNotifierProvider<LocationNotifier>.value(value: loc),
          ],
          child: MaterialApp(home: CaregiverDetailScreen(caregiver: caregiverNoVoice)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Presentación en voz'), findsNothing);
    });
  });
}
