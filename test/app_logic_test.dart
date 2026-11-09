import 'package:flutter_test/flutter_test.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
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
  Future<void> createClient(ClientProfile client) async {}
  @override
  Future<ClientProfile?> getClient(String userId) async { return null; }
  @override
  Future<void> updateClient(String userId, Map<String, dynamic> data) async {}
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    DependencyInjection.auth = MockAuthRepository();
    DependencyInjection.caregivers = MockCaregiverRepository();
    DependencyInjection.clients = MockClientRepository();
    DependencyInjection.bookings = MockBookingRepository();
    DependencyInjection.chats = MockChatRepository();
    DependencyInjection.reviews = MockReviewRepository();
    DependencyInjection.reports = MockReportRepository();
    DependencyInjection.stats = MockStatsRepository();
  });

  test('E2E Logic: Flujo Completo Cuidador y Cliente', () async {
    final authNotifier = AuthNotifier();
    final caregiverNotifier = CaregiverNotifier();
    final bookingNotifier = BookingNotifier();
    
    // ==========================================
    // ESCENARIO 1: Registro de Cuidador
    // ==========================================
    final caregiverEmail = 'nuevo_cuidador@test.com';
    await DependencyInjection.auth.signUpWithEmail(caregiverEmail, 'password', 'caregiver');
    
    // Simular login
    await DependencyInjection.auth.signInWithEmail(caregiverEmail, 'password');
    await Future.delayed(const Duration(milliseconds: 100));
    
    // El usuario rellena su perfil
    final caregiverUid = authNotifier.currentUserId ?? 'c1';
    final newProfileData = {
      'name': 'Carlos El Cuidador',
      'bio': 'Test bio',
      'pricePerHour': 20.0,
      'specialties': ['Compañía', 'Enfermería'],
    };
    await DependencyInjection.caregivers.updateProfile(caregiverUid, newProfileData);

    // ==========================================
    // ESCENARIO 2: Cliente se registra y reserva
    // ==========================================
    final clientEmail = 'cliente@test.com';
    await DependencyInjection.auth.signUpWithEmail(clientEmail, 'password', 'client');
    await DependencyInjection.auth.signInWithEmail(clientEmail, 'password');
    await Future.delayed(const Duration(milliseconds: 100));
    
    authNotifier.currentUserId = authNotifier.currentUserId ?? 'dummy_client_uid'; // Forzar asignación por si falla el stream
    authNotifier.setRole('client');

    caregiverNotifier.setSearchQuery('Elena');
    await Future.delayed(const Duration(milliseconds: 1000)); // wait for fetch to complete (>800ms)
    
    final elena = caregiverNotifier.filteredCaregivers.first;
    
    final booking = Booking(
      id: 'test_booking_123',
      caregiverId: elena.id,
      clientId: authNotifier.currentUserId!,
      caregiverName: elena.name,
      day: 'Lunes',
      slot: '10:00 - 12:00',
      status: BookingStatus.pending,
      cost: 30.0,
      clientFee: 3.0,
      caregiverCommissionRate: 0.10,
      caregiverCommissionAmount: 3.0,
      caregiverPayout: 27.0,
      totalPaid: 33.0,
    );

    await bookingNotifier.addBooking(booking);

    bookingNotifier.updateAuth(authNotifier.currentUserId, authNotifier.currentRole);

    // Esperar a que el stream del mock llegue al notifier
    await Future.delayed(const Duration(milliseconds: 500));
    
    expect(bookingNotifier.bookings.length, 1);
    expect(bookingNotifier.bookings.first.totalPaid, 33.0);
  });
}
