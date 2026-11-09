import 'package:flutter/foundation.dart';
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
  Future<ClientProfile?> getClient(String userId) async { return null; }
  @override
  Future<void> updateClient(String userId, Map<String, dynamic> data) async {}
}

void main() {
  setUpAll(() {
    DependencyInjection.auth = MockAuthRepository();
    DependencyInjection.caregivers = MockCaregiverRepository();
    DependencyInjection.clients = MockClientRepository();
    DependencyInjection.bookings = MockBookingRepository();
    DependencyInjection.chats = MockChatRepository();
    DependencyInjection.reviews = MockReviewRepository();
    DependencyInjection.stats = MockStatsRepository();
  });

  test('Simulación de Flujo Completo E2E', () async {
    final authNotifier = AuthNotifier();
    final caregiverNotifier = CaregiverNotifier();
    final bookingNotifier = BookingNotifier();

    debugPrint('=== INICIANDO SIMULACIÓN E2E ===');

    // 1. Registro Cuidador
    debugPrint('1. Registrando/iniciando sesión cuidador...');
    await DependencyInjection.auth.signUpWithEmail('elena@test.com', 'pass', 'caregiver');
    await DependencyInjection.auth.signInWithEmail('elena@test.com', 'pass');
    
    // 2. Registro Cliente
    debugPrint('2. Registrando cliente...');
    await DependencyInjection.auth.signOut();
    await DependencyInjection.auth.signUpWithEmail('cliente@test.com', 'pass', 'client');
    await DependencyInjection.auth.signInWithEmail('cliente@test.com', 'pass');
    authNotifier.setRole('client');
    final clientUid = 'cl_123';

    // 3. Cliente busca cuidadores
    debugPrint('3. Cliente buscando cuidador...');
    caregiverNotifier.setSearchQuery('Elena');
    await Future.delayed(const Duration(milliseconds: 1500));
    
    debugPrint('Total cuidadores en notifier: \${caregiverNotifier.caregivers.length}');
    for(var c in caregiverNotifier.caregivers) {
      debugPrint(' - ${c.name} (Verified: ${c.verificationStatus})');
    }
    
    expect(caregiverNotifier.filteredCaregivers.isNotEmpty, true);
    final targetCaregiver = caregiverNotifier.filteredCaregivers.first;
    debugPrint('   -> Cuidador encontrado: ${targetCaregiver.name}');

    // 4. Cliente reserva hora
    debugPrint('4. Cliente reserva hora...');
    final bookingId = 'booking_test_1';
    final booking = Booking(
      id: bookingId,
      clientId: clientUid,
      caregiverId: targetCaregiver.id,
      caregiverName: targetCaregiver.name,
      day: 'Mañana',
      slot: '10:00 - 12:00',
      status: BookingStatus.pending,
      cost: 30.0,
      clientFee: 3.0,
      caregiverCommissionRate: 0.10,
      caregiverCommissionAmount: 3.0,
      caregiverPayout: 27.0,
      totalPaid: 33.0,
    );
    await DependencyInjection.bookings.createBooking(booking);

    bookingNotifier.updateAuth(clientUid, 'client');
    await Future.delayed(const Duration(milliseconds: 500));
    expect(bookingNotifier.bookings.any((b) => b.id == bookingId), true);
    debugPrint('   -> Reserva creada exitosamente. Estado: PENDING');

    // 5. Cuidador confirma reserva
    debugPrint('5. Cuidador confirma reserva...');
    await DependencyInjection.bookings.updateBookingStatus(bookingId, 'confirmed');
    
    var currentBookings = await DependencyInjection.bookings.streamBookings(clientUid, 'client').first;
    expect(currentBookings.firstWhere((b) => b.id == bookingId).status, BookingStatus.confirmed);
    debugPrint('   -> Reserva confirmada.');

    // 6. Cuidador completa reserva
    debugPrint('6. Cuidador completa la reserva (libera escrow)...');
    await DependencyInjection.bookings.releaseEscrow(bookingId);
    
    currentBookings = await DependencyInjection.bookings.streamBookings(clientUid, 'client').first;
    final finalBooking = currentBookings.firstWhere((b) => b.id == bookingId);
    expect(finalBooking.status, BookingStatus.completed);
    expect(finalBooking.escrowStatus, 'released');
    debugPrint('   -> Reserva completada y pago liberado.');

    // 7. Cliente valora al cuidador
    debugPrint('7. Cliente envía valoración...');
    await DependencyInjection.reviews.addReview(targetCaregiver.id, Review(
      id: 'rev_1',
      caregiverId: targetCaregiver.id,
      clientId: clientUid,
      clientName: 'Cliente Prueba',
      rating: 5.0,
      comment: 'Excelente trabajo',
    ));
    
    debugPrint('=== SIMULACIÓN E2E FINALIZADA CON ÉXITO ===');
  });
}
