import 'dart:async';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';

class MockBookingRepository implements BookingRepository {
  final StreamController<List<Booking>> _controller = StreamController<List<Booking>>.broadcast();
  final List<Booking> _bookings = [];

  @override
  Stream<List<Booking>> streamBookings(String userId, String role, {int? limit}) async* {
    yield List.from(limit != null ? _bookings.take(limit) : _bookings);
    yield* _controller.stream.map((list) => List.from(limit != null ? list.take(limit) : list));
  }

  @override
  Future<String> createBooking(Booking booking) async {
    _bookings.add(booking);
    _controller.add(List.from(_bookings));
    return booking.id;
  }

  @override
  Future<void> updateBookingStatus(String bookingId, String status) async {
    final idx = _bookings.indexWhere((b) => b.id == bookingId);
    if (idx != -1) {
      _bookings[idx].status = BookingStatus.values.firstWhere((e) => e.toString().contains(status));
      _controller.add(List.from(_bookings));
    }
  }

  @override
  Future<void> releaseEscrow(String bookingId) async {
    final idx = _bookings.indexWhere((b) => b.id == bookingId);
    if (idx != -1) {
      final old = _bookings[idx];
      _bookings[idx] = Booking(
        id: old.id,
        clientId: old.clientId,
        caregiverId: old.caregiverId,
        caregiverName: old.caregiverName,
        day: old.day,
        slot: old.slot,
        status: BookingStatus.completed,
        cost: old.cost,
        clientFee: old.clientFee,
        caregiverCommissionRate: old.caregiverCommissionRate,
        caregiverCommissionAmount: old.caregiverCommissionAmount,
        caregiverPayout: old.caregiverPayout,
        totalPaid: old.totalPaid,
        escrowStatus: 'released',
        cancellationReason: old.cancellationReason,
        createdAt: old.createdAt,
      );
      _controller.add(List.from(_bookings));
    }
  }

  @override
  Future<void> cancelBooking(String bookingId, String reason, bool isLate) async {
    final idx = _bookings.indexWhere((b) => b.id == bookingId);
    if (idx != -1) {
      final old = _bookings[idx];
      _bookings[idx] = Booking(
        id: old.id,
        clientId: old.clientId,
        caregiverId: old.caregiverId,
        caregiverName: old.caregiverName,
        day: old.day,
        slot: old.slot,
        status: isLate ? BookingStatus.cancelledLate : BookingStatus.cancelled,
        cost: old.cost,
        clientFee: old.clientFee,
        caregiverCommissionRate: old.caregiverCommissionRate,
        caregiverCommissionAmount: old.caregiverCommissionAmount,
        caregiverPayout: old.caregiverPayout,
        totalPaid: old.totalPaid,
        escrowStatus: isLate ? 'held' : 'refunded',
        cancellationReason: reason,
        createdAt: old.createdAt,
      );
      _controller.add(List.from(_bookings));
    }
  }

  @override
  Future<void> deleteBooking(String bookingId) async {
    _bookings.removeWhere((b) => b.id == bookingId);
    _controller.add(List.from(_bookings));
  }
}
