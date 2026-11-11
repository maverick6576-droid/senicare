import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';

void main() {
  late MockBookingRepository mockRepo;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    mockRepo = MockBookingRepository();
    DependencyInjection.bookings = mockRepo;
  });

  Booking makeBooking({
    String id = 'b1',
    DateTime? startDt,
    int durationHours = 2,
    BookingStatus status = BookingStatus.confirmed,
    String escrowStatus = 'held',
    String liveStatus = 'scheduled',
    DateTime? checkInTime,
    DateTime? checkOutTime,
    double cost = 40.0,
    double caregiverCommissionRate = 0.18,
    double caregiverCommissionAmount = 0.0,
    double caregiverPayout = 0.0,
    double? disputeAmount,
  }) {
    final start = startDt ?? DateTime.now().add(const Duration(hours: 3));
    final end = start.add(Duration(hours: durationHours));
    final dayStr = DateFormat('yyyy-MM-dd').format(start);
    final slotStr =
        '${DateFormat('HH:mm').format(start)}-${DateFormat('HH:mm').format(end)}';
    return Booking(
      id: id,
      clientId: 'client_1',
      caregiverId: 'cg_1',
      caregiverName: 'Laura Pérez',
      day: dayStr,
      slot: slotStr,
      status: status,
      cost: cost,
      clientFee: cost * 0.03,
      caregiverCommissionRate: caregiverCommissionRate,
      caregiverCommissionAmount: caregiverCommissionAmount,
      caregiverPayout: caregiverPayout,
      totalPaid: cost * 1.03,
      escrowStatus: escrowStatus,
      liveStatus: liveStatus,
      checkInTime: checkInTime,
      checkOutTime: checkOutTime,
      disputeAmount: disputeAmount,
    );
  }

  group('Booking caregiver lifecycle & active status', () {
    test('keeps checked-in uncompleted shift active even past scheduled end', () {
      final pastStart = DateTime.now().subtract(const Duration(hours: 4));
      final b = makeBooking(
        startDt: pastStart,
        durationHours: 2,
        status: BookingStatus.confirmed,
        liveStatus: 'in_progress',
        checkInTime: pastStart.add(const Duration(minutes: 2)),
      );

      expect(b.isExpired, isTrue);
      expect(b.isInProgressAwaitingCheckOut, isTrue);
      expect(b.isActive, isTrue);
    });

    test('moves checked-in shift to inactive once completed', () {
      final pastStart = DateTime.now().subtract(const Duration(hours: 4));
      final b = makeBooking(
        startDt: pastStart,
        durationHours: 2,
        status: BookingStatus.confirmed,
        liveStatus: 'completed',
        checkInTime: pastStart,
        checkOutTime: pastStart.add(const Duration(hours: 2)),
      );

      expect(b.isInProgressAwaitingCheckOut, isFalse);
      expect(b.isActive, isFalse);
    });

    test('keeps expired disputed booking active until settled', () {
      final pastStart = DateTime.now().subtract(const Duration(hours: 6));
      final disputed = makeBooking(
        startDt: pastStart,
        durationHours: 2,
        status: BookingStatus.confirmed,
        escrowStatus: 'disputed',
      );
      expect(disputed.isOpenDisputePendingAction, isTrue);
      expect(disputed.isActive, isTrue);

      for (final settled in [
        'released',
        'released_manual',
        'released_auto',
        'resolved_partial',
        'refunded',
      ]) {
        final b = makeBooking(
          escrowStatus: settled,
          status: BookingStatus.confirmed,
        );
        expect(b.isEscrowSettled, isTrue);
        expect(b.isActive, isFalse);
      }
    });
  });

  group('Booking caregiver net earnings calculation', () {
    test('uses explicit caregiverPayout when available', () {
      final b = makeBooking(
        cost: 100.0,
        caregiverCommissionRate: 0.18,
        caregiverPayout: 84.50,
      );
      expect(b.netPayoutForCaregiver, closeTo(84.50, 0.001));
    });

    test('falls back to rate or commission amount when payout is zero', () {
      final byRate = makeBooking(
        cost: 100.0,
        caregiverCommissionRate: 0.15,
        caregiverPayout: 0.0,
      );
      expect(byRate.netPayoutForCaregiver, closeTo(85.0, 0.001));

      final byAmount = makeBooking(
        cost: 100.0,
        caregiverCommissionRate: 0.0,
        caregiverCommissionAmount: 18.0,
        caregiverPayout: 0.0,
      );
      expect(byAmount.netPayoutForCaregiver, closeTo(82.0, 0.001));
    });

    test('estimates net remaining payout after dispute deduction', () {
      final b = makeBooking(
        cost: 100.0,
        caregiverCommissionRate: 0.20,
        caregiverPayout: 0.0,
        escrowStatus: 'resolved_partial',
        disputeAmount: 25.0,
      );
      expect(b.estimateNetAfterDispute(25.0), closeTo(60.0, 0.001));
      expect(b.netPayoutForCaregiver, closeTo(60.0, 0.001));
      expect(b.estimateNetAfterDispute(150.0), closeTo(0.0, 0.001));
    });
  });

  group('BookingNotifier pagination and refresh guards', () {
    test('does not increment limit when fewer bookings than limit exist', () async {
      await mockRepo.createBooking(makeBooking(id: 'b1'));
      final notifier = BookingNotifier();
      notifier.updateAuth('cg_1', 'caregiver');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(notifier.bookings.length, 1);
      expect(notifier.hasMore, isFalse);

      notifier.loadMoreBookings();
      expect(notifier.currentLimit, 15);
      notifier.dispose();
    });

    test('loads next page when limit reached and preserves items on refresh', () async {
      for (int i = 0; i < 18; i++) {
        await mockRepo.createBooking(makeBooking(id: 'b_$i'));
      }
      final notifier = BookingNotifier();
      notifier.updateAuth('cg_1', 'caregiver');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(notifier.bookings.length, 15);
      expect(notifier.hasMore, isTrue);

      notifier.loadMoreBookings();
      expect(notifier.currentLimit, 30);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(notifier.bookings.length, 18);
      expect(notifier.hasMore, isFalse);

      // Switching auth resets limit back to 15.
      notifier.updateAuth('cg_2', 'caregiver');
      expect(notifier.currentLimit, 15);

      // Refresh should not wipe loaded items before stream emits.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(notifier.bookings.length, 15);
      final refreshFuture = notifier.refreshBookings();
      expect(notifier.bookings.length, 15);
      await refreshFuture;

      notifier.dispose();
    });
  });
}
