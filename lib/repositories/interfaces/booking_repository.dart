import 'package:senicare/models/models.dart';

abstract class BookingRepository {
  Stream<List<Booking>> streamBookings(String userId, String role, {int? limit});
  /// Creates a booking and returns the Firestore-assigned document ID.
  Future<String> createBooking(Booking booking);
  Future<void> updateBookingStatus(String bookingId, String status);
  Future<void> releaseEscrow(String bookingId);
  Future<void> cancelBooking(String bookingId, String reason, bool isLate);
  /// Deletes a booking document completely (used for payment rollback).
  Future<void> deleteBooking(String bookingId);
}

