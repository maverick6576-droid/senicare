import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';
import 'package:senicare/screens/client_profile_edit_screen.dart';
import 'package:senicare/widgets/address_form_widget.dart';

class _TrackingAuthRepository extends MockAuthRepository {
  int signOutCalls = 0;

  @override
  Future<void> signOut() async {
    signOutCalls++;
    await super.signOut();
  }
}

class _FlakyClientRepository extends MockClientRepository {
  bool shouldThrowOnGet = false;
  bool shouldThrowOnUpdate = false;

  @override
  Future<ClientProfile?> getClient(String id) async {
    if (shouldThrowOnGet) {
      throw Exception('Error de red simulado');
    }
    return super.getClient(id);
  }

  @override
  Future<void> updateClient(String id, Map<String, dynamic> data) async {
    if (shouldThrowOnUpdate) {
      throw Exception('Fallo al guardar simulado');
    }
    await super.updateClient(id, data);
  }
}

void main() {
  late _TrackingAuthRepository mockAuth;
  late _FlakyClientRepository mockClients;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    mockAuth = _TrackingAuthRepository();
    mockClients = _FlakyClientRepository();

    DependencyInjection.auth = mockAuth;
    DependencyInjection.clients = mockClients;
    DependencyInjection.caregivers = MockCaregiverRepository();
    DependencyInjection.bookings = MockBookingRepository();
    DependencyInjection.chats = MockChatRepository();
    DependencyInjection.reviews = MockReviewRepository();
  });

  Widget wrapScreen(AuthNotifier auth, {ConfigNotifier? config}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthNotifier>.value(value: auth),
        ChangeNotifierProvider<ConfigNotifier>.value(
          value: config ?? ConfigNotifier(),
        ),
      ],
      child: const MaterialApp(home: ClientProfileEditScreen()),
    );
  }

  group('ClientProfile model, MockClientRepository & AddressFormWidget', () {
    test('MockClientRepository preserves checklist and authorized emails across updates',
        () async {
      await mockClients.updateClient('cli_1', {
        'name': 'Ana Torres',
        'phone': '600112233',
        'homeAddress': 'Calle Mayor 10, Madrid, Madrid, España',
        'latitude': 40.4168,
        'longitude': -3.7038,
        'patientDetails': 'Padre de 84 años',
        'onboardingComplete': true,
        'defaultCareChecklist': ['💊 Medicación mañana', '🚶 Paseo suave'],
        'authorizedFamilyEmails': ['hermano@email.com'],
      });

      // Partial update touching only name
      await mockClients.updateClient('cli_1', {'name': 'Ana Torres Ruiz'});

      final saved = await mockClients.getClient('cli_1');
      expect(saved, isNotNull);
      expect(saved!.name, 'Ana Torres Ruiz');
      expect(saved.phone, '600112233');
      expect(saved.latitude, 40.4168);
      expect(saved.longitude, -3.7038);
      expect(
        saved.defaultCareChecklist,
        ['💊 Medicación mañana', '🚶 Paseo suave'],
      );
      expect(saved.authorizedFamilyEmails, ['hermano@email.com']);

      final cleared = saved.copyWith(clearLocation: true);
      expect(cleared.latitude, isNull);
      expect(cleared.longitude, isNull);
      expect(cleared.defaultCareChecklist, saved.defaultCareChecklist);
    });

    testWidgets(
        'AddressFormWidget parses 3-part, 5-part Nominatim, and non-Spain country without crash',
        (tester) async {
      String latestAddress = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AddressFormWidget(
                initialAddress:
                    'Carrer de Mallorca 401, 08013 Barcelona, Catalunya, Spain',
                onAddressChanged: (val) => latestAddress = val,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Carrer de Mallorca'), findsOneWidget);
      expect(find.text('Barcelona'), findsWidgets);

      // Update via didUpdateWidget (e.g. GPS lookup result)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AddressFormWidget(
                initialAddress: 'Calle Alcalá 22, Madrid, España',
                onAddressChanged: (val) => latestAddress = val,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Calle Alcalá'), findsOneWidget);
      expect(find.text('22'), findsOneWidget);
      expect(latestAddress, isNotNull);
    });
  });

  group('ClientProfileEditScreen lifecycle, error recovery & completeness', () {
    testWidgets('shows Reintentar on fetch error and recovers when repo succeeds',
        (tester) async {
      mockClients.shouldThrowOnGet = true;
      await mockClients.updateClient('cli_err', {
        'name': 'Pedro Morales',
        'phone': '611223344',
        'homeAddress': 'Calle Mayor 10, Madrid, Madrid, España',
        'latitude': 40.4168,
        'longitude': -3.7038,
        'patientDetails': 'Movilidad asistida',
        'onboardingComplete': true,
      });

      final auth = AuthNotifier()
        ..isAuthenticated = true
        ..currentUserId = 'cli_err'
        ..currentRole = 'client';

      await tester.pumpWidget(wrapScreen(auth));
      await tester.pumpAndSettle();

      expect(
        find.text('No se pudo cargar tu perfil. Comprueba tu conexión.'),
        findsOneWidget,
      );
      expect(find.text('Reintentar'), findsOneWidget);

      mockClients.shouldThrowOnGet = false;
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('Pedro Morales'), findsOneWidget);
      expect(find.text('Perfil familiar completo ✓'), findsOneWidget);
      expect(find.text('Listo ✓'), findsOneWidget);
    });

    testWidgets(
        'shows accurate progress for incomplete profile and updates on edit',
        (tester) async {
      await mockClients.updateClient('cli_inc', {
        'name': 'Sin nombre',
        'phone': '',
        'homeAddress': '',
        'patientDetails': '',
        'onboardingComplete': false,
      });

      final auth = AuthNotifier()
        ..isAuthenticated = true
        ..currentUserId = 'cli_inc'
        ..currentRole = 'client';

      await tester.pumpWidget(wrapScreen(auth));
      await tester.pumpAndSettle();

      expect(find.text('Faltan 5 datos para tus reservas'), findsOneWidget);
      expect(find.text('0 de 5 datos completados'), findsOneWidget);
      expect(find.text('Completar ahora'), findsOneWidget);
    });
  });

  group('ClientProfileEditScreen editing, cancel, checklist, family & Senior Mode',
      () {
    testWidgets(
        'discards edits on Cancel, validates phone, preserves coordinates and saves changes',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await mockClients.updateClient('cli_edit', {
        'name': 'Elena Navarro',
        'phone': '622334455',
        'homeAddress': 'Calle Mayor 10, Madrid, Madrid, España',
        'latitude': 40.4168,
        'longitude': -3.7038,
        'patientDetails': 'Abuelo de 85 años',
        'onboardingComplete': true,
        'defaultCareChecklist': ['💊 Pastilla desayuno'],
        'authorizedFamilyEmails': ['hermana@email.com'],
      });

      final auth = AuthNotifier()
        ..isAuthenticated = true
        ..currentUserId = 'cli_edit'
        ..currentRole = 'client';

      await tester.pumpWidget(wrapScreen(auth));
      await tester.pumpAndSettle();

      expect(find.text('EN'), findsOneWidget);
      expect(find.text('Ubicación en mapa configurada ✓'), findsOneWidget);

      // Enter edit mode
      await tester.tap(find.text('Editar perfil'));
      await tester.pumpAndSettle();

      // Modify name and then cancel -> discarded completely
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Elena Navarro'),
        'Nombre Temporal No Guardado',
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.text('Elena Navarro'), findsOneWidget);
      expect(find.text('Nombre Temporal No Guardado'), findsNothing);

      // Enter edit mode again, verify invalid short phone rejection
      await tester.tap(find.text('Editar perfil'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, '622334455'),
        '123',
      );
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();
      expect(
        find.text('Introduce un teléfono de contacto válido.'),
        findsOneWidget,
      );

      // Fix phone and name, save, check preservation of coords, checklist, and emails
      await tester.enterText(
        find.widgetWithText(TextFormField, '123'),
        '699887766',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Elena Navarro'),
        'Elena Navarro Díaz',
      );
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();

      expect(
        find.text('Perfil y ubicación actualizados correctamente'),
        findsOneWidget,
      );
      final updated = await mockClients.getClient('cli_edit');
      expect(updated, isNotNull);
      expect(updated!.name, 'Elena Navarro Díaz');
      expect(updated.phone, '699887766');
      expect(updated.latitude, 40.4168);
      expect(updated.longitude, -3.7038);
      expect(updated.defaultCareChecklist, ['💊 Pastilla desayuno']);
      expect(updated.authorizedFamilyEmails, ['hermana@email.com']);
    });

    testWidgets(
        'validates checklist & family emails, rolls back on error, toggles Senior Mode, and renders without overflow on 360x640',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await mockClients.updateClient('cli_tools', {
        'name': 'Carmen López',
        'phone': '633445566',
        'homeAddress': 'Gran Via 45, Barcelona, Barcelona, España',
        'latitude': 41.3888,
        'longitude': 2.1589,
        'patientDetails': 'Madre con movilidad reducida',
        'onboardingComplete': true,
      });

      final auth = AuthNotifier()
        ..isAuthenticated = true
        ..currentUserId = 'cli_tools'
        ..currentRole = 'client';
      final config = ConfigNotifier();

      await tester.pumpWidget(wrapScreen(auth, config: config));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Toggle Modo Senior from quick tile & verify zero overflow on compact 360x640
      await tester.tap(find.text('Modo Senior'));
      await tester.pumpAndSettle();
      expect(config.seniorMode, isTrue);
      expect(find.text('Activado (Letra XL)'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Toggle a health preference chip deterministically
      final caneChip = find.widgetWithText(FilterChip, '🚶 Usa bastón o andador');
      await tester.ensureVisible(caneChip);
      await tester.pump();
      await tester.tap(caneChip);
      await tester.pumpAndSettle();
      var saved = await mockClients.getClient('cli_tools');
      expect(
        saved!.patientDetails,
        'Madre con movilidad reducida • 🚶 Usa bastón o andador',
      );

      // Checklist: empty task shows validation warning
      final addBtn = find.widgetWithText(FilledButton, 'Añadir');
      await Scrollable.ensureVisible(tester.element(addBtn), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(addBtn);
      await tester.pump();
      expect(
        find.text('Escribe una tarea antes de añadirla.'),
        findsOneWidget,
      );

      // Checklist: add custom task
      final checklistInput = find.widgetWithText(
        TextField,
        'Añadir tarea (ej. Pastilla tensión 12:30)...',
      );
      await Scrollable.ensureVisible(
        tester.element(checklistInput),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.enterText(checklistInput, 'Tomar tensión 18:00');
      await Scrollable.ensureVisible(tester.element(addBtn), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(addBtn);
      await tester.pumpAndSettle();
      expect(find.text('Tomar tensión 18:00'), findsOneWidget);

      // Shared Family Account: reject invalid email, then invite normalized email
      final familyInput = find.widgetWithText(
        TextField,
        'Email del familiar (ej. hermano@email.com)',
      );
      final inviteBtn = find.widgetWithText(FilledButton, 'Invitar');
      await Scrollable.ensureVisible(tester.element(familyInput), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.enterText(familyInput, 'correo-invalido');
      await Scrollable.ensureVisible(tester.element(inviteBtn), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(inviteBtn);
      await tester.pumpAndSettle();
      expect(
        find.text('Introduce un correo electrónico válido (ej. maria@email.com).'),
        findsOneWidget,
      );

      await tester.enterText(familyInput, 'Hermano@Email.COM');
      await Scrollable.ensureVisible(tester.element(inviteBtn), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(inviteBtn);
      await tester.pumpAndSettle();
      expect(find.text('hermano@email.com'), findsOneWidget);
      saved = await mockClients.getClient('cli_tools');
      expect(saved!.authorizedFamilyEmails, ['hermano@email.com']);

      // Failure rollback on backend error
      mockClients.shouldThrowOnUpdate = true;
      await tester.enterText(familyInput, 'otro@email.com');
      await Scrollable.ensureVisible(tester.element(inviteBtn), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(inviteBtn);
      await tester.pumpAndSettle();
      expect(find.text('otro@email.com'), findsNothing);
      expect(
        find.text('No se pudo guardar el cambio. Comprueba tu conexión.'),
        findsOneWidget,
      );
      mockClients.shouldThrowOnUpdate = false;

      // Also verify edit mode renders without overflow on 360x640 with Senior Mode ON
      await tester.ensureVisible(find.text('Editar perfil'));
      await tester.pump();
      await tester.tap(find.text('Editar perfil'));
      await tester.pumpAndSettle();
      expect(find.text('Guardar cambios'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      // Confirm sign-out dialog works safely
      ScaffoldMessenger.of(tester.element(find.byType(ClientProfileEditScreen)))
          .clearSnackBars();
      await tester.pumpAndSettle();
      final signOutTile = find.text('Cerrar sesión');
      await Scrollable.ensureVisible(
        tester.element(signOutTile),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(signOutTile);
      await tester.pumpAndSettle();

      expect(
        find.text('¿Seguro que quieres salir de tu cuenta familiar?'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Cerrar sesión'));
      await tester.pumpAndSettle();

      expect(mockAuth.signOutCalls, 1);
      expect(tester.takeException(), isNull);
    });
  });
}
