import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/repositories/repositories.dart';
import 'package:provider/provider.dart';

void main() {
  setUpAll(() {
    ClientTutorialService.useLocalFileStorage = false;
    CaregiverTutorialService.useLocalFileStorage = false;
    // Override dependencies with Mock implementations for headless testing
    DependencyInjection.auth = MockAuthRepository();
    DependencyInjection.caregivers = MockCaregiverRepository();
    DependencyInjection.bookings = MockBookingRepository();
    DependencyInjection.chats = MockChatRepository();
    DependencyInjection.stats = MockStatsRepository(); 
    DependencyInjection.reviews = MockReviewRepository();
    DependencyInjection.reports = MockReportRepository();
    DependencyInjection.clients = MockClientRepository();
  });

  Widget createTestApp() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthNotifier()),
        ChangeNotifierProvider(create: (_) => LocationNotifier()),
        ChangeNotifierProvider(create: (_) => ConfigNotifier()),
        ChangeNotifierProxyProvider2<AuthNotifier, LocationNotifier, CaregiverNotifier>(
          create: (_) => CaregiverNotifier(),
          update: (_, auth, location, caregiverNotifier) {
            caregiverNotifier!.updateLocation(location.latitude, location.longitude);
            return caregiverNotifier;
          },
        ),
        ChangeNotifierProxyProvider<AuthNotifier, BookingNotifier>(
          create: (_) => BookingNotifier(),
          update: (_, auth, bookingNotifier) {
            bookingNotifier!.updateAuth(auth.currentUserId, auth.currentRole);
            return bookingNotifier;
          },
        ),
        ChangeNotifierProxyProvider<AuthNotifier, ChatNotifier>(
          create: (_) => ChatNotifier(),
          update: (_, auth, chatNotifier) {
            chatNotifier!.updateAuth(auth.currentUserId, auth.currentRole);
            return chatNotifier;
          },
        ),
      ],
      child: const SeniCareApp(),
    );
  }

  group('Headless Frontend UI Tests', () {
    testWidgets('Flujo de Usuario Normal (Login y Navegación) - Sin Simulador', (tester) async {
      // Pre-poblar el mock client para evitar la pantalla de onboarding
      await DependencyInjection.clients.updateClient('mock_user_123', {
        'name': 'Test Client',
        'onboardingComplete': true,
        'clientTutorialSeen': true,
      });

      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Encontrar campos de texto en AuthScreen
      final emailField = find.byType(TextFormField).at(0);
      final passwordField = find.byType(TextFormField).at(1);
      final loginButton = find.byType(ElevatedButton).first;

      expect(emailField, findsOneWidget);

      // Escribir credenciales
      await tester.enterText(emailField, 'test_mock@senicare.com');
      await tester.enterText(passwordField, '123456');
      
      // Pulsar Entrar
      await tester.ensureVisible(loginButton);
      await tester.tap(loginButton, warnIfMissed: false);
      await tester.pump(); // Start the tap
      await tester.pump(const Duration(seconds: 2)); // Wait for async AuthNotifier
      await tester.pump(const Duration(seconds: 1)); // Wait for navigation without pumpAndSettle to avoid infinite Shimmer animation

      // Deberíamos ver la barra de navegación (MainLayout)
      final bottomNavBar = find.byType(BottomNavigationBar);
      expect(bottomNavBar, findsOneWidget);

      // Pulsar "Reservas"
      final reservasTab = find.text('Reservas');
      await tester.tap(reservasTab);
      await tester.pump(const Duration(seconds: 1));
      
      // Pulsar "Mensajes"
      final mensajesTab = find.text('Mensajes');
      await tester.tap(mensajesTab);
      await tester.pump(const Duration(seconds: 1));

      // Pulsar "Explorar" para volver
      final explorarTab = find.text('Explorar');
      await tester.tap(explorarTab);
      await tester.pump(const Duration(seconds: 1));

      // Abrir un perfil de cuidador mock
      final caregiverCard = find.byType(Card).first;
      if (caregiverCard.evaluate().isNotEmpty) {
        await tester.tap(caregiverCard);
        await tester.pump(const Duration(seconds: 1));
        
        // Verificar que hay botón de reservar
        final reservarButton = find.byType(ElevatedButton).last;
        if (reservarButton.evaluate().isNotEmpty) {
          await tester.tap(reservarButton);
          await tester.pump(const Duration(seconds: 1));
          
          // Cerrar BottomSheet
          await tester.tapAt(const Offset(10, 10)); 
          await tester.pump(const Duration(seconds: 1));
        }
      }
    });

    testWidgets('Flujo de Administrador (Login y Dashboard) - Sin Simulador', (tester) async {
      await DependencyInjection.clients.updateClient('admin_user_id', {'name': 'Admin User', 'onboardingComplete': true});

      // Sobrescribir el rol a 'admin' para este usuario mock
      final authMock = DependencyInjection.auth as MockAuthRepository;
      authMock.adminOverrideEmail = 'maverick6576@gmail.com';

      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      final emailField = find.byType(TextFormField).at(0);
      final passwordField = find.byType(TextFormField).at(1);
      final loginButton = find.byType(ElevatedButton).first;

      await tester.enterText(emailField, 'maverick6576@gmail.com');
      await tester.enterText(passwordField, '123456');
      
      await tester.ensureVisible(loginButton);
      await tester.tap(loginButton, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));

      // Verificar que estamos en Admin2FAScreen o AdminDashboard
      final admin2FA = find.text('Seguridad Administrador');
      final adminDash = find.text('Admin Panel');
      
      
      if (admin2FA.evaluate().isEmpty && adminDash.evaluate().isEmpty) {
        debugPrint('Widgets on screen:');
        for (var w in tester.allWidgets) {
          if (w.toStringShort().contains('Text')) debugPrint(w.toStringShort());
        }
      }
      expect(admin2FA.evaluate().isNotEmpty || adminDash.evaluate().isNotEmpty, true, reason: 'Debe navegar a pantalla de admin');
    });
  });
}

class MockStatsRepository implements FirestoreStatsRepository {
  Future<Map<String, dynamic>> getCaregiverStats(String caregiverId) async {
    return {'totalBookings': 5, 'totalEarnings': 100.0, 'completedBookings': 5};
  }

  Future<void> updateBookingStats(String caregiverId, double amount, String status) async {}

  @override
  Future<int> getAccumulatedHours(String clientId, String caregiverId) async => 0;

  @override
  Future<List<Map<String, dynamic>>> getCaregiverClientStats(String caregiverId) async => [];

  @override
  Future<void> addCompletedHours(String clientId, String caregiverId, int hoursToAdd) async {}
}
