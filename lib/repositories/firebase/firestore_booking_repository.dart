import 'package:flutter/material.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreBookingRepository implements BookingRepository {
  final CollectionReference _collection = FirebaseFirestore.instance.collection('bookings');

  @override
  Stream<List<Booking>> streamBookings(String userId, String role, {int? limit}) async* {
    try {
      Query query = _collection;
      if (role == 'client') {
        query = query.where('clientId', isEqualTo: userId);
      } else if (role == 'caregiver') {
        query = query.where('caregiverId', isEqualTo: userId);
      }
      
      if (limit != null) {
        query = query.limit(limit);
      }
      
      await for (var snapshot in query.snapshots()) {
        final list = snapshot.docs.map((doc) => Booking.fromFirestore(doc)).toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        yield list;
      }
    } catch (e) {
      debugPrint('==================================================');
      debugPrint('⚠️ Error in streamBookings: $e');
      debugPrint('==================================================');
      yield* const Stream.empty();
    }
  }

  @override
  Future<String> createBooking(Booking booking) async {
    try {
      final docRef = await _collection.add(booking.toFirestore());
      return docRef.id;
    } catch (e) {
      debugPrint('⚠️ Error in createBooking: $e');
      rethrow;
    }
  }

  @override
  Future<void> updateBookingStatus(String bookingId, String status) async {
    try {
      await _collection.doc(bookingId).update({'status': status});
    } catch (e) {
      debugPrint('⚠️ Error in updateBookingStatus: $e');
      rethrow;
    }
  }

  @override
  Future<void> releaseEscrow(String bookingId) async {
    try {
      await _collection.doc(bookingId).update({
        'status': BookingStatus.completed.toString().split('.').last,
      });
    } catch (e) {
      debugPrint('⚠️ Error in releaseEscrow: $e');
      rethrow;
    }
  }

  @override
  Future<void> cancelBooking(String bookingId, String reason, bool isLate) async {
    try {
      await _collection.doc(bookingId).update({
        'status': isLate ? BookingStatus.cancelledLate.toString().split('.').last : BookingStatus.cancelled.toString().split('.').last,
        'cancellationReason': reason,
      });
    } catch (e) {
      debugPrint('Error in cancelBooking: $e');
      rethrow;
    }
  }

  @override
  Future<void> deleteBooking(String bookingId) async {
    try {
      await _collection.doc(bookingId).delete();
    } catch (e) {
      debugPrint('⚠️ Error in deleteBooking: $e');
      // Do not rethrow - rollback best-effort, don't block the user
    }
  }
}
