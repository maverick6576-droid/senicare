import 'package:flutter/material.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreBookingRepository implements BookingRepository {
  final FirebaseFirestore _firestore;
  FirestoreBookingRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference get _collection => _firestore.collection('bookings');

  Query _buildRoleQuery(String userId, String role) {
    Query query = _collection;
    if (role == 'client') {
      query = query.where('clientId', isEqualTo: userId);
    } else if (role == 'caregiver') {
      query = query.where('caregiverId', isEqualTo: userId);
    }
    return query;
  }

  bool _isMissingIndexError(Object error) {
    if (error is FirebaseException && error.code == 'failed-precondition') {
      return true;
    }
    final msg = error.toString().toLowerCase();
    return msg.contains('failed-precondition') || msg.contains('requires an index');
  }

  List<Booking> _mapAndSortBookings(QuerySnapshot snapshot, {int? limit}) {
    final list = snapshot.docs.map((doc) => Booking.fromFirestore(doc)).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (limit != null && list.length > limit) {
      return list.take(limit).toList();
    }
    return list;
  }

  @override
  Stream<List<Booking>> streamBookings(String userId, String role, {int? limit}) async* {
    try {
      Query indexedQuery = _buildRoleQuery(userId, role).orderBy('createdAt', descending: true);
      if (limit != null) {
        indexedQuery = indexedQuery.limit(limit);
      }

      try {
        await for (final snapshot in indexedQuery.snapshots()) {
          yield _mapAndSortBookings(snapshot);
        }
      } catch (e) {
        if (!_isMissingIndexError(e)) rethrow;
        debugPrint('⚠️ streamBookings missing index ($e). Falling back to single-field query.');
        final fallbackQuery = _buildRoleQuery(userId, role);
        await for (final snapshot in fallbackQuery.snapshots()) {
          yield _mapAndSortBookings(snapshot, limit: limit);
        }
      }
    } catch (e) {
      debugPrint('==================================================');
      debugPrint('⚠️ Error in streamBookings: $e');
      debugPrint('==================================================');
      yield* Stream.error(e);
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
