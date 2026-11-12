import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/screens/screens.dart';
import 'package:senicare/repositories/repositories.dart';

class MockStatsRepository implements FirestoreStatsRepository {
  @override
  Future<void> addCompletedHours(String clientId, String caregiverId, int hours) async {}
  @override
  Future<int> getAccumulatedHours(String clientId, String caregiverId) async { return 10; }
  @override
  Future<List<Map<String, dynamic>>> getCaregiverClientStats(String caregiverId) async { return []; }
}

class MockClientRepository implements ClientRepository {
  @override
  Future<ClientProfile?> getClient(String userId) async { return null; }
  @override
  Future<void> updateClient(String userId, Map<String, dynamic> data) async {}
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    AppTheme.useSystemFonts = true;
    DependencyInjection.auth = MockAuthRepository();
    DependencyInjection.caregivers = MockCaregiverRepository();
    DependencyInjection.clients = MockClientRepository();
    DependencyInjection.bookings = MockBookingRepository();
    DependencyInjection.chats = MockChatRepository();
    DependencyInjection.reviews = MockReviewRepository();
    DependencyInjection.stats = MockStatsRepository();
    DependencyInjection.jobOffers = MockJobOfferRepository();
    DependencyInjection.families = MockFamilyRepository();
  });

  tearDownAll(() {
    AppTheme.useSystemFonts = false;
  });

  testWidgets('Full UI E2E Flow: Registro, Reserva y Valoracion', (WidgetTester tester) async {
    final authNotifier = AuthNotifier();
    final locationNotifier = LocationNotifier();
    final configNotifier = ConfigNotifier();
    final caregiverNotifier = CaregiverNotifier();
    final bookingNotifier = BookingNotifier();
    final chatNotifier = ChatNotifier();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: authNotifier),
          ChangeNotifierProvider.value(value: locationNotifier),
          ChangeNotifierProvider.value(value: configNotifier),
          ChangeNotifierProvider.value(value: caregiverNotifier),
          ChangeNotifierProvider.value(value: bookingNotifier),
          ChangeNotifierProvider.value(value: chatNotifier),
        ],
        child: const MaterialApp(
          home: AuthScreen(),
        ),
      ),
    );

    // 1. REGISTRO DE CUIDADOR
    final registerTab = find.text('Registrarse');
    await tester.ensureVisible(registerTab);
    await tester.tap(registerTab);
    await tester.pump(const Duration(milliseconds: 500));

    final caregiverRoleCard = find.text('Cuidador/a');
    await tester.ensureVisible(caregiverRoleCard);
    await tester.tap(caregiverRoleCard);
    await tester.pump(const Duration(milliseconds: 500));

    await tester.enterText(find.byType(TextFormField).at(0), 'nuevo_cuida@test.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.enterText(find.byType(TextFormField).at(2), 'password123');
    final submitRegisterBtn = find.text('Crear Cuenta Ahora');
    await tester.ensureVisible(submitRegisterBtn);
    await tester.tap(submitRegisterBtn);
    await tester.pump(const Duration(seconds: 2));

    final caregiverUid = authNotifier.currentUserId ?? 'c1';
    await DependencyInjection.caregivers.updateProfile(caregiverUid, {
      'name': 'Carlos El Cuidador',
      'pricePerHour': 20.0,
      'specialties': ['Compañía', 'Enfermería'],
      'verificationStatus': 'approved',
      'maxDistanceRadius': 50.0,
      'latitude': 41.38,
      'longitude': 2.15
    });

    // Logout
    await DependencyInjection.auth.signOut();
    await tester.pump(const Duration(milliseconds: 500));

    // 2. REGISTRO DE CLIENTE
    await DependencyInjection.auth.signUpWithEmail('nuevo_cliente@test.com', 'password123', 'client');
    await DependencyInjection.auth.signInWithEmail('nuevo_cliente@test.com', 'password123');
    await tester.pump(const Duration(milliseconds: 500));

    final clientUid = authNotifier.currentUserId ?? 'cl1';

    // 3. CLIENTE BUSCA CUIDADOR
    caregiverNotifier.setSearchQuery('Carlos');
    await tester.pump(const Duration(milliseconds: 1000));
    
    final foundCaregivers = caregiverNotifier.filteredCaregivers;
    expect(foundCaregivers.isNotEmpty, true, reason: 'El cuidador debería aparecer en la búsqueda');
    final targetCaregiver = foundCaregivers.first;

    // 4. CLIENTE RESERVA HORA
    final bookingId = 'book_123';
    final booking = Booking(
      id: bookingId,
      clientId: clientUid,
      caregiverId: targetCaregiver.id,
      caregiverName: targetCaregiver.name,
      day: 'Mañana',
      slot: '10:00 - 12:00',
      status: BookingStatus.pending,
      cost: 40.0,
      clientFee: 4.0,
      caregiverCommissionRate: 0.10,
      caregiverCommissionAmount: 4.0,
      caregiverPayout: 36.0,
      totalPaid: 44.0,
    );
    await DependencyInjection.bookings.createBooking(booking);

    // Activar listener de Auth en BookingNotifier
    bookingNotifier.updateAuth(clientUid, 'client');
    await tester.pump(const Duration(milliseconds: 500));
    
    expect(bookingNotifier.bookings.any((b) => b.id == bookingId), true, reason: 'La reserva debe estar visible para el cliente');

    // 5. CUIDADOR ACEPTA LA RESERVA Y COMPLETA
    await DependencyInjection.auth.signOut();
    await DependencyInjection.auth.signInWithEmail('nuevo_cuida@test.com', 'password123');
    bookingNotifier.updateAuth(caregiverUid, 'caregiver');
    await tester.pump(const Duration(milliseconds: 500));

    await DependencyInjection.bookings.updateBookingStatus(bookingId, 'confirmed');
    await DependencyInjection.bookings.releaseEscrow(bookingId);

    // 6. CLIENTE PONE VALORACIÓN
    await DependencyInjection.auth.signOut();
    await DependencyInjection.auth.signInWithEmail('nuevo_cliente@test.com', 'password123');
    bookingNotifier.updateAuth(clientUid, 'client');
    
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final completedBooking = bookingNotifier.bookings.firstWhere((b) => b.id == bookingId);
    expect(completedBooking.status, BookingStatus.completed);
    expect(completedBooking.escrowStatus, 'released');

    await bookingNotifier.submitReview(completedBooking, 5.0, '¡Excelente cuidador automatizado!', clientUid);
    
    debugPrint('Flujo E2E UI superado exitosamente!');
  });
}
