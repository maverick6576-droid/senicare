import 'package:flutter_test/flutter_test.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/repositories/repositories.dart';

class MockStatsRepository implements FirestoreStatsRepository {
  @override
  Future<void> addCompletedHours(String clientId, String caregiverId, int hours) async {}
  @override
  Future<int> getAccumulatedHours(String clientId, String caregiverId) async { return 10; }
  @override
  Future<List<Map<String, dynamic>>> getCaregiverClientStats(String caregiverId) async { return []; }
}

void main() {
  group('Motor de Reservas, Calendarios y Cancelaciones (SeniCare)', () {
    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      DependencyInjection.caregivers = MockCaregiverRepository();
      DependencyInjection.bookings = MockBookingRepository();
      DependencyInjection.stats = MockStatsRepository();
    });

    test('1. [Calendario] El cuidador puede obtener y actualizar sus franjas horarias', () async {
      final repo = DependencyInjection.caregivers;
      const caregiverId = 'mock_caregiver_123';
      const dateStr = '2026-07-01';

      // 1. Fetch inicial genera slots por defecto
      final slots = await repo.fetchTimeSlots(caregiverId, dateStr);
      expect(slots.isNotEmpty, true, reason: 'Deberían generarse slots por defecto');
      
      // 2. Modificar un slot (bloquearlo)
      final slotToModify = slots.first;
      expect(slotToModify.isAvailable, true);
      
      slotToModify.isAvailable = false;
      await repo.updateTimeSlot(caregiverId, dateStr, slotToModify);

      // 3. Volver a recuperar y verificar el cambio
      final updatedSlots = await repo.fetchTimeSlots(caregiverId, dateStr);
      final updatedSlot = updatedSlots.firstWhere((s) => s.id == slotToModify.id);
      expect(updatedSlot.isAvailable, false, reason: 'El slot debería haberse guardado como ocupado (false)');
    });

    test('2. [Reservas] Crear una reserva atómica con escrow', () async {
      final repo = DependencyInjection.bookings;
      final bookingId = 'book_1';

      final booking = Booking(
        id: bookingId,
        clientId: 'client_1',
        caregiverId: 'caregiver_1',
        caregiverName: 'María García',
        day: '2024-05-15',
        slot: '10:00',
        cost: 30,
        clientFee: 0.9,
        caregiverCommissionRate: 0.18,
        caregiverCommissionAmount: 5.4,
        caregiverPayout: 24.6,
        totalPaid: 30.9,
      );

      // 1. Crear reserva
      await repo.createBooking(booking);

      // 2. Comprobar que está en la base de datos (escuchando el stream)
      final bookingsStream = repo.streamBookings('client_1', 'client');
      final currentBookings = await bookingsStream.first;
      
      expect(currentBookings.length, 1);
      expect(currentBookings.first.id, bookingId);
      expect(currentBookings.first.status, BookingStatus.pending);
      expect(currentBookings.first.escrowStatus, 'held', reason: 'El dinero debe estar retenido inicialmente');
    });

    test('3. [Pagos] Liberar escrow marca el estado como completado y released', () async {
      final repo = DependencyInjection.bookings;
      final bookingId = 'book_2';

      await repo.createBooking(Booking(
        id: bookingId,
        clientId: 'client_1',
        caregiverId: 'caregiver_1',
        caregiverName: 'María García',
        day: '2026-07-01',
        slot: '10:00',
        cost: 30.0,
        clientFee: 0.9,
        caregiverCommissionRate: 0.18,
        caregiverCommissionAmount: 5.4,
        caregiverPayout: 24.6,
        totalPaid: 30.9,
        status: BookingStatus.confirmed, // Simulamos que fue confirmada
      ));

      // Liberar escrow
      await repo.releaseEscrow(bookingId);

      final bookingsStream = repo.streamBookings('client_1', 'client');
      final currentBookings = await bookingsStream.first;
      
      final updatedBooking = currentBookings.firstWhere((b) => b.id == bookingId);
      expect(updatedBooking.status, BookingStatus.completed, reason: 'El estado debe cambiar a completado');
      expect(updatedBooking.escrowStatus, 'released', reason: 'Los fondos deben marcarse como liberados');
    });

    test('4. [Cancelaciones] Cancelación gratuita (> 24h) cambia a cancelled y refunded', () async {
      final repo = DependencyInjection.bookings;
      final bookingId = 'book_3';

      await repo.createBooking(Booking(
        id: bookingId,
        clientId: 'client_1',
        caregiverId: 'caregiver_1',
        caregiverName: 'María García',
        day: '2026-07-05', // Fecha futura
        slot: '10:00',
        cost: 30.0,
        clientFee: 0.9,
        caregiverCommissionRate: 0.18,
        caregiverCommissionAmount: 5.4,
        caregiverPayout: 24.6,
        totalPaid: 30.9,
      ));

      // Cancelar como cliente (temprano)
      await repo.cancelBooking(bookingId, 'Cancelado temprano', false);

      final bookingsStream = repo.streamBookings('client_1', 'client');
      final currentBookings = await bookingsStream.first;
      
      final updatedBooking = currentBookings.firstWhere((b) => b.id == bookingId);
      expect(updatedBooking.status, BookingStatus.cancelled);
      expect(updatedBooking.escrowStatus, 'refunded', reason: 'El escrow debe reembolsarse');
      expect(updatedBooking.cancellationReason, 'Cancelado temprano');
    });

    test('5. [Cancelaciones] Cancelación tardía (< 24h) aplica penalización (cancelledLate / held)', () async {
      final repo = DependencyInjection.bookings;
      final bookingId = 'book_4';

      await repo.createBooking(Booking(
        id: bookingId,
        clientId: 'client_1',
        caregiverId: 'caregiver_1',
        caregiverName: 'María García',
        day: '2026-07-01',
        slot: '10:00',
        cost: 30.0,
        clientFee: 0.9,
        caregiverCommissionRate: 0.18,
        caregiverCommissionAmount: 5.4,
        caregiverPayout: 24.6,
        totalPaid: 30.9,
      ));

      // Cancelar como cliente (tarde) -> isLate = true
      await repo.cancelBooking(bookingId, 'Cancelado tarde', true);

      final bookingsStream = repo.streamBookings('client_1', 'client');
      final currentBookings = await bookingsStream.first;
      
      final updatedBooking = currentBookings.firstWhere((b) => b.id == bookingId);
      expect(updatedBooking.status, BookingStatus.cancelledLate, reason: 'El estado debe ser cancelledLate por penalización');
      expect(updatedBooking.escrowStatus, 'held', reason: 'Los fondos deben mantenerse retenidos por la plataforma');
      expect(updatedBooking.cancellationReason, 'Cancelado tarde');
    });
  });
}
