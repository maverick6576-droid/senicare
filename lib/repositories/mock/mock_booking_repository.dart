import 'dart:async';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';

class MockBookingRepository implements BookingRepository {
  MockBookingRepository({this.filterByUser = false});

  final bool filterByUser;
  final StreamController<List<Booking>> _controller = StreamController<List<Booking>>.broadcast();
  final List<Booking> _bookings = [];

  List<Booking> _filterAndSort(String userId, String role, int? limit,
      [List<Booking>? source]) {
    final items = (source ?? _bookings).where((b) {
      if (!filterByUser || userId.isEmpty) return true;
      if (role == 'caregiver') return b.caregiverId == userId;
      if (role == 'client') return b.clientId == userId;
      return true;
    }).toList();
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (limit != null && limit > 0 && items.length > limit) {
      return items.take(limit).toList();
    }
    return items;
  }

  @override
  Stream<List<Booking>> streamBookings(String userId, String role, {int? limit}) async* {
    yield _filterAndSort(userId, role, limit);
    yield* _controller.stream.map((list) => _filterAndSort(userId, role, limit, list));
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
      final normalized = status.toLowerCase();
      _bookings[idx].status = BookingStatus.values.firstWhere(
        (e) => e.name.toLowerCase() == normalized,
        orElse: () => BookingStatus.values.firstWhere((e) => e.toString().contains(status)),
      );
      _controller.add(List.from(_bookings));
    }
  }

  @override
  Future<void> releaseEscrow(String bookingId) async {
    final idx = _bookings.indexWhere((b) => b.id == bookingId);
    if (idx != -1) {
      _bookings[idx] = _bookings[idx].copyWith(
        status: BookingStatus.completed,
        escrowStatus: 'released',
        liveStatus: 'completed',
      );
      _controller.add(List.from(_bookings));
    }
  }

  @override
  Future<void> cancelBooking(String bookingId, String reason, bool isLate) async {
    final idx = _bookings.indexWhere((b) => b.id == bookingId);
    if (idx != -1) {
      _bookings[idx] = _bookings[idx].copyWith(
        status: isLate ? BookingStatus.cancelledLate : BookingStatus.cancelled,
        escrowStatus: isLate ? 'held' : 'refunded',
        cancellationReason: reason,
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
