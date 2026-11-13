import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';
import 'package:senicare/screens/caregiver_profile_edit_screen.dart';

class _TestClientRepository implements ClientRepository {
  @override
  Future<ClientProfile?> getClient(String id) async => null;

  @override
  Future<void> updateClient(String id, Map<String, dynamic> data) async {}
}

class _TrackingAuthRepository extends MockAuthRepository {
  int signOutCalls = 0;

  @override
  Future<void> signOut() async {
    signOutCalls++;
    await super.signOut();
  }
}

void main() {
  late _TrackingAuthRepository mockAuth;
  late MockCaregiverRepository mockCaregivers;
  late MockBookingRepository mockBookings;
  late MockChatRepository mockChats;
  late MockReviewRepository mockReviews;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    mockAuth = _TrackingAuthRepository();
    mockCaregivers = MockCaregiverRepository();
    mockBookings = MockBookingRepository();
    mockChats = MockChatRepository();
    mockReviews = MockReviewRepository();

    DependencyInjection.auth = mockAuth;
    DependencyInjection.caregivers = mockCaregivers;
    DependencyInjection.clients = _TestClientRepository();
    DependencyInjection.bookings = mockBookings;
    DependencyInjection.chats = mockChats;
    DependencyInjection.reviews = mockReviews;
  });

  Widget wrapScreen(AuthNotifier auth, {ConfigNotifier? config}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthNotifier>.value(value: auth),
        ChangeNotifierProvider<ConfigNotifier>.value(
          value: config ?? ConfigNotifier(),
        ),
        ChangeNotifierProvider<LocationNotifier>(
          create: (_) => LocationNotifier(),
        ),
      ],
      child: const MaterialApp(home: CaregiverProfileEditScreen()),
    );
  }

  group('CaregiverProfileEditScreen lifecycle & status banners', () {
    testWidgets('shows friendly error with Reintentar when profile is missing',
        (tester) async {
      final auth = AuthNotifier()
        ..isAuthenticated = true
        ..currentUserId = 'missing_cg'
        ..currentRole = 'caregiver';

      await tester.pumpWidget(wrapScreen(auth));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No hemos encontrado tu ficha de cuidador'),
        findsOneWidget,
      );
      expect(find.text('Reintentar'), findsOneWidget);

      // Seed profile and tap Reintentar
      await mockCaregivers.updateProfile('missing_cg', {
        'name': 'Carmen Silva',
        'title': 'Enfermera Geriátrica',
        'bio': 'Cuidados cercanos',
        'pricePerHour': 18.0,
        'homeAddress': 'Calle Mayor 10, Madrid, Madrid, España',
        'latitude': 40.4168,
        'longitude': -3.7038,
      });

      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('Carmen Silva'), findsOneWidget);
      expect(find.text('Enfermera Geriátrica'), findsOneWidget);
    });

    testWidgets(
        'shows accurate incomplete checklist vs rejected vs complete verified banners',
        (tester) async {
      // 1) Incomplete profile (c1 in MockCaregiverRepository misses imageUrl check? c1 has pravatar, misses dni/criminal/stripe)
      final auth = AuthNotifier()
        ..isAuthenticated = true
        ..currentUserId = 'c1'
        ..currentRole = 'caregiver';

      await tester.pumpWidget(wrapScreen(auth));
      await tester.pumpAndSettle();

      expect(find.textContaining('Faltan 3 datos para activarte'), findsOneWidget);
      expect(find.text('5 de 8 pasos completados'), findsOneWidget);
      expect(find.text('Completar ahora'), findsOneWidget);

      // 2) Rejected verification status shows red rejection banner
      await mockCaregivers.updateProfile('c1', {
        'verificationStatus': 'rejected',
        'verified': false,
        'isVerified': false,
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(wrapScreen(auth));
      await tester.pumpAndSettle();

      expect(find.text('Documentación rechazada'), findsOneWidget);
      expect(find.text('Corregir documentos'), findsOneWidget);

      // 3) Complete & approved with KYC shows verified banner and KYC ✓
      await mockCaregivers.updateProfile('c1', {
        'verificationStatus': 'approved',
        'verified': true,
        'isVerified': true,
        'dniUrl': 'https://example.com/dni.jpg',
        'criminalRecordUrl': 'https://example.com/penales.pdf',
        'stripeAccountId': 'acct_123456',
        'isKycVerified': true,
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(wrapScreen(auth));
      await tester.pumpAndSettle();

      expect(find.text('Perfil Verificado y Visible ✓'), findsOneWidget);
      expect(find.text('Verificada (KYC ✓)'), findsOneWidget);
    });
  });

  group('CaregiverProfileEditScreen editing, validation, preview & signOut',
      () {
    testWidgets(
        'validates minimum price, supports Spanish decimal comma, preserves all specialties, and supports cancel',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await mockCaregivers.updateProfile('cg_edit', {
        'name': 'Laura Gómez',
        'title': 'Auxiliar',
        'bio': 'Experiencia con mayores de 80 años',
        'pricePerHour': 15.0,
        'homeAddress': 'Carrer de Mallorca, 401, Barcelona',
        'latitude': 41.3888,
        'longitude': 2.1589,
        'specialties': ['Movilidad', 'Alzheimer'],
        'verificationStatus': 'pending',
        'verified': false,
      });

      final auth = AuthNotifier()
        ..isAuthenticated = true
        ..currentUserId = 'cg_edit'
        ..currentRole = 'caregiver';

      await tester.pumpWidget(wrapScreen(auth));
      await tester.pumpAndSettle();

      // Unified 10-specialty support: legacy Alzheimer appears in read mode
      expect(find.text('Alzheimer'), findsOneWidget);

      // Enter edit mode
      await tester.tap(find.text('Editar perfil'));
      await tester.pumpAndSettle();

      expect(find.text('Cancelar'), findsOneWidget);
      expect(find.text('Guardar cambios'), findsOneWidget);
      // Unified specialties include Fisioterapia & Alzheimer in edit mode too
      expect(find.text('Fisioterapia'), findsOneWidget);

      // Modify name and test Cancel restores original
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Laura Gómez'),
        'Nombre Temporal Descartado',
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.text('Laura Gómez'), findsOneWidget);
      expect(find.text('Nombre Temporal Descartado'), findsNothing);

      // Enter edit mode again, try invalid price < 6
      await tester.tap(find.text('Editar perfil'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, '15'),
        '5,5',
      );
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('la tarifa mínima es de 6 €/hora'),
        findsOneWidget,
      );
      // Stays in edit mode
      expect(find.text('Guardar cambios'), findsOneWidget);

      // Now enter valid comma decimal price, new title, select Fisioterapia, and save
      await tester.enterText(
        find.widgetWithText(TextFormField, '5,5'),
        '21,5',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Auxiliar'),
        'Enfermera Geriátrica',
      );
      final fisioChip = find.widgetWithText(FilterChip, 'Fisioterapia');
      await tester.ensureVisible(fisioChip);
      await tester.tap(fisioChip);
      await tester.pump();

      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();

      expect(
        find.text('Perfil actualizado correctamente'),
        findsOneWidget,
      );
      final saved = await mockCaregivers.getCaregiver('cg_edit');
      expect(saved, isNotNull);
      expect(saved!.pricePerHour, 21.5);
      expect(saved.title, 'Enfermera Geriátrica');
      expect(saved.specialties, containsAll(['Movilidad', 'Alzheimer', 'Fisioterapia']));
      // Preserved GPS coordinates without losing address when street wasn't re-entered
      expect(saved.latitude, 41.3888);
      expect(saved.longitude, 2.1589);
      // Exited edit mode back to read view
      expect(find.text('Editar perfil'), findsOneWidget);
    });

    testWidgets(
        'opens public CaregiverDetailScreen in preview mode without Contactar FAB & confirms signOut',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await mockCaregivers.updateProfile('cg_preview', {
        'name': 'Elena Morales',
        'title': 'Enfermera Geriátrica',
        'bio': 'Especialista en alzhéimer y curas.',
        'pricePerHour': 20.0,
        'homeAddress': 'Carrer de Balmes, 120, Barcelona, España',
        'latitude': 41.392,
        'longitude': 2.155,
        'imageUrl': '',
        'specialties': ['Alzheimer', 'Compañía'],
        'verificationStatus': 'approved',
        'verified': true,
        'isVerified': true,
        'dniUrl': 'https://example.com/dni.jpg',
        'criminalRecordUrl': 'https://example.com/penales.pdf',
        'stripeAccountId': 'acct_preview',
        'isKycVerified': true,
      });

      final auth = AuthNotifier()
        ..isAuthenticated = true
        ..currentUserId = 'cg_preview'
        ..currentRole = 'caregiver';

      await tester.pumpWidget(wrapScreen(auth));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Vista previa'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Vista previa pública: así ven tu perfil las familias'),
        findsOneWidget,
      );
      expect(find.text('Contactar'), findsNothing);

      // Navigate back to Mi Perfil
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Scroll down to Cerrar sesión and confirm dialog
      final signOutFinder = find.text('Cerrar sesión');
      await tester.ensureVisible(signOutFinder);
      await tester.tap(signOutFinder);
      await tester.pumpAndSettle();

      expect(
        find.text('¿Seguro que quieres salir de tu cuenta de cuidador?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Salir'));
      await tester.pumpAndSettle();

      expect(mockAuth.signOutCalls, 1);
    });
  });
}
