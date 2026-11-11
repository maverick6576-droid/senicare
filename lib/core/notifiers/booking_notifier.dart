import 'dart:async';
import 'package:flutter/material.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/core/core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

class BookingNotifier extends ChangeNotifier {
  List<Booking> bookings = [];
  StreamSubscription? _bookingsSubscription;

  String? _currentUserId;
  String? _currentRole;
  int _limit = 15;
  bool _isLoadingMore = false;

  int get currentLimit => _limit;
  bool get hasMore => bookings.length >= _limit;
  bool get isLoadingMore => _isLoadingMore;

  void updateAuth(String? userId, String? role) {
    if (_currentUserId != userId || _currentRole != role) {
      _currentUserId = userId;
      _currentRole = role;
      _limit = 15;
      _isLoadingMore = false;
      _subscribeToBookings();
    }
  }

  Future<void> refreshBookings() async {
    _isLoadingMore = false;
    _subscribeToBookings(clearBookings: false);
    // Keep existing items rendered while the fresh snapshot arrives.
    await Future.delayed(const Duration(milliseconds: 350));
  }

  void loadMoreBookings() {
    if (!hasMore || _isLoadingMore) return;
    _isLoadingMore = true;
    _limit += 15;
    _subscribeToBookings(clearBookings: false);
  }

  void _subscribeToBookings({bool clearBookings = true}) {
    _bookingsSubscription?.cancel();
    if (clearBookings) bookings.clear();

    if (_currentUserId == null || _currentRole == null || _currentRole == 'admin') {
      _isLoadingMore = false;
      notifyListeners();
      return;
    }

    final roleToStream = _currentRole == 'client' ? 'client' : 'caregiver';
    _bookingsSubscription = DependencyInjection.bookings
        .streamBookings(_currentUserId!, roleToStream, limit: _limit)
        .listen(
      (data) {
        bookings = data;
        _isLoadingMore = false;
        notifyListeners();
      },
      onError: (_) {
        _isLoadingMore = false;
        notifyListeners();
      },
    );
  }

  Future<String> addBooking(Booking booking) async {
    return await DependencyInjection.bookings.createBooking(booking);
  }

  Future<void> confirmBooking(String bookingId) async {
    await DependencyInjection.bookings.updateBookingStatus(bookingId, BookingStatus.confirmed.toString().split('.').last);
    final b = bookings.where((b) => b.id == bookingId).firstOrNull;
    if (b != null) {
      b.status = BookingStatus.confirmed;
      notifyListeners();
    }
  }

  Future<void> rejectBooking(String bookingId) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1').httpsCallable('caregiverRejectBooking');
      await callable.call({
        'bookingId': bookingId,
      });
      final b = bookings.where((b) => b.id == bookingId).firstOrNull;
      if (b != null) {
        b.status = BookingStatus.cancelled;
        b.escrowStatus = 'refunded';
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error rejecting booking: $e');
      rethrow;
    }
  }

  
  Future<void> openDispute(String bookingId, double disputeAmount, String reason, String description) async {
    await FirebaseFirestore.instance.collection('bookings').doc(bookingId).update({
      'escrowStatus': 'disputed',
      'disputeRequested': true,
      'disputeAmount': disputeAmount,
      'disputeReason': reason,
      'disputeDescription': description,
      'disputeOpenedAt': FieldValue.serverTimestamp(),
    });
    
    final b = bookings.where((b) => b.id == bookingId).firstOrNull;
    if (b != null) {
      b.escrowStatus = 'disputed';
      b.disputeRequested = true;
      b.disputeAmount = disputeAmount;
      b.disputeEscalated = false;
      notifyListeners();
    }
  }

  Future<void> escalateDispute(String bookingId) async {
    await FirebaseFirestore.instance.collection('bookings').doc(bookingId).update({
      'disputeEscalated': true,
    });
    
    final b = bookings.where((b) => b.id == bookingId).firstOrNull;
    if (b != null) {
      b.disputeEscalated = true;
      notifyListeners();
    }
  }

  Future<void> acceptDisputeProposal(String bookingId) async {
    final func = FirebaseFunctions.instanceFor(region: 'europe-west1').httpsCallable('processResolutionAgreement');
    await func.call({'bookingId': bookingId});
    
    final b = bookings.where((b) => b.id == bookingId).firstOrNull;
    if (b != null) {
      b.status = BookingStatus.completed;
      b.escrowStatus = 'resolved_partial';
      notifyListeners();
    }
  }

  Future<void> releaseEscrow(String bookingId) async {
    final success = await StripeService.releaseEscrowPayment(
      bookingId: bookingId,
    );

    if (success) {
      final b = bookings.where((b) => b.id == bookingId).firstOrNull;
      if (b != null) {
        b.status = BookingStatus.completed;
        b.escrowStatus = 'released_manual';
        
        int hours = 1;
        if (b.slot.contains('-')) {
          try {
            final slotParts = b.slot.split('-');
            final startParts = slotParts[0].split(':');
            final endParts = slotParts[1].split(':');
            final startHour = int.parse(startParts[0]);
            final endHour = int.parse(endParts[0]);
            hours = (endHour - startHour).abs();
            if (hours == 0) hours = 1;
          } catch (e) {
            debugPrint('Error calculating hours for stats: $e');
          }
        }
        await DependencyInjection.stats.addCompletedHours(b.clientId, b.caregiverId, hours);
        notifyListeners();
      }
    } else {
      debugPrint('Stripe Transfer failed for booking $bookingId');
    }
  }

  Future<void> cancelBooking(String bookingId, String reason, bool isLate) async {
    try {
      final HttpsCallable callable = FirebaseFunctions.instanceFor(region: 'europe-west1').httpsCallable('cancelBookingProcess');
      await callable.call(<String, dynamic>{
        'bookingId': bookingId,
        'reason': reason,
        'isLate': isLate,
      });
      
      final b = bookings.where((b) => b.id == bookingId).firstOrNull;
      if (b != null) {
        b.status = isLate ? BookingStatus.cancelledLate : BookingStatus.cancelled;
        b.escrowStatus = isLate ? 'resolved_partial' : 'refunded';
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error calling cancelBookingProcess: $e");
      await DependencyInjection.bookings.cancelBooking(bookingId, reason, isLate);
    }
  }

  Future<void> checkInBooking(String bookingId) async {
    final b = bookings.where((b) => b.id == bookingId).firstOrNull;
    if (b == null) return;
    
    final checkInTime = DateTime.now();
    bool isPunctual = true;
    try {
      final parts = b.day.split('-');
      final String startTimeStr = b.slot.contains('-') ? b.slot.split('-')[0] : b.slot;
      final timeParts = startTimeStr.split(':');
      final expectedTime = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]), int.parse(timeParts[0]), int.parse(timeParts[1]));
      
      final diffMinutes = checkInTime.difference(expectedTime).inMinutes;
      isPunctual = diffMinutes <= 15;
    } catch (e) {
      debugPrint('Error calculating punctuality: $e');
    }

    b.liveStatus = 'in_progress';
    b.checkInTime = checkInTime;
    notifyListeners();

    if (useFirebaseBackend && Firebase.apps.isNotEmpty) {
      await FirebaseFirestore.instance.collection('bookings').doc(bookingId).update({
        'checkInTime': Timestamp.fromDate(checkInTime),
        'isPunctual': isPunctual,
        'liveStatus': 'in_progress',
      });
    }
  }

  Future<void> completeService(String bookingId) async {
    final b = bookings.where((b) => b.id == bookingId).firstOrNull;
    final now = DateTime.now();
    if (b != null) {
      b.liveStatus = 'completed';
      b.status = BookingStatus.completed;
      b.checkOutTime = now;
      notifyListeners();
    }
    if (useFirebaseBackend && Firebase.apps.isNotEmpty) {
      await FirebaseFirestore.instance.collection('bookings').doc(bookingId).update({
        'liveStatus': 'completed',
        'status': 'completed',
        'checkOutTime': Timestamp.fromDate(now),
      });
    }
  }

  Future<void> markOnTheWay(String bookingId) async {
    final b = bookings.where((b) => b.id == bookingId).firstOrNull;
    final now = DateTime.now();
    if (b != null) {
      b.liveStatus = 'on_the_way';
      b.onTheWayAt = now;
      notifyListeners();
    }
    if (useFirebaseBackend && Firebase.apps.isNotEmpty) {
      await FirebaseFirestore.instance.collection('bookings').doc(bookingId).update({
        'liveStatus': 'on_the_way',
        'onTheWayAt': Timestamp.fromDate(now),
      });
    }
  }

  Future<void> addChecklistTask(String bookingId, String taskTitle) async {
    final trimmed = taskTitle.trim();
    if (trimmed.isEmpty) return;
    final b = bookings.where((b) => b.id == bookingId).firstOrNull;
    if (b == null) return;

    final newItem = CareChecklistItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: trimmed,
      completed: false,
    );
    b.careChecklist.add(newItem);
    notifyListeners();

    if (useFirebaseBackend && Firebase.apps.isNotEmpty) {
      await FirebaseFirestore.instance.collection('bookings').doc(bookingId).update({
        'careChecklist': b.careChecklist.map((e) => e.toMap()).toList(),
      });
    }
  }

  Future<void> removeChecklistTask(String bookingId, String itemId) async {
    final b = bookings.where((b) => b.id == bookingId).firstOrNull;
    if (b == null) return;

    b.careChecklist.removeWhere((item) => item.id == itemId);
    notifyListeners();

    if (useFirebaseBackend && Firebase.apps.isNotEmpty) {
      await FirebaseFirestore.instance.collection('bookings').doc(bookingId).update({
        'careChecklist': b.careChecklist.map((e) => e.toMap()).toList(),
      });
    }
  }

  Future<void> toggleChecklistTask(String bookingId, String itemId) async {
    final b = bookings.where((b) => b.id == bookingId).firstOrNull;
    if (b == null) return;

    final item = b.careChecklist.where((i) => i.id == itemId).firstOrNull;
    if (item == null) return;

    item.completed = !item.completed;
    if (item.completed) {
      final now = DateTime.now();
      item.completedAt = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    } else {
      item.completedAt = null;
    }
    notifyListeners();

    if (useFirebaseBackend && Firebase.apps.isNotEmpty) {
      await FirebaseFirestore.instance.collection('bookings').doc(bookingId).update({
        'careChecklist': b.careChecklist.map((e) => e.toMap()).toList(),
      });
    }
  }

  Future<void> updateCareNotes(String bookingId, String notes) async {
    final b = bookings.where((b) => b.id == bookingId).firstOrNull;
    if (b != null) {
      b.careNotes = notes.trim();
      notifyListeners();
    }
    if (useFirebaseBackend && Firebase.apps.isNotEmpty) {
      await FirebaseFirestore.instance.collection('bookings').doc(bookingId).update({
        'careNotes': notes.trim(),
      });
    }
  }

  Future<void> addCarePhotoUrl(String bookingId, String photoUrl) async {
    final b = bookings.where((b) => b.id == bookingId).firstOrNull;
    if (b == null) return;

    b.carePhotoUrls.add(photoUrl);
    notifyListeners();

    if (useFirebaseBackend && Firebase.apps.isNotEmpty) {
      await FirebaseFirestore.instance.collection('bookings').doc(bookingId).update({
        'carePhotoUrls': b.carePhotoUrls,
      });
    }
  }

  Future<void> addTipToBooking(String bookingId, double tipAmount) async {
    if (tipAmount <= 0) return;
    final b = bookings.where((b) => b.id == bookingId).firstOrNull;
    if (b != null) {
      b.tipAmount += tipAmount;
      notifyListeners();
    }
    if (useFirebaseBackend && Firebase.apps.isNotEmpty) {
      await FirebaseFirestore.instance.collection('bookings').doc(bookingId).update({
        'tipAmount': FieldValue.increment(tipAmount),
      });
    }
  }

  Future<void> requestRefund(String bookingId, double amount, String reason) async {
    if (useFirebaseBackend && Firebase.apps.isNotEmpty) {
      await FirebaseFirestore.instance.collection('bookings').doc(bookingId).update({
        'disputeRequested': true,
        'disputeAmount': amount,
        'disputeReason': reason,
      });
    }
  }

  Future<void> acceptRefund(String bookingId) async {
    final b = bookings.where((b) => b.id == bookingId).firstOrNull;
    if (b == null) return;

    if (useFirebaseBackend && Firebase.apps.isNotEmpty) {
      try {
        final HttpsCallable callable = FirebaseFunctions.instanceFor(region: 'europe-west1').httpsCallable('processResolutionAgreement');
        await callable.call(<String, dynamic>{
          'bookingId': bookingId,
        });
        b.escrowStatus = 'resolved_partial';
        b.status = BookingStatus.completed;
        notifyListeners();
      } catch (e) {
        debugPrint("Error calling processResolutionAgreement: $e");
        rethrow;
      }
    }
  }

  
  Future<void> dismissReviewPrompt(List<Booking> bookings) async {
    final batch = FirebaseFirestore.instance.batch();
    for (var b in bookings) {
      final doc = FirebaseFirestore.instance.collection('bookings').doc(b.id);
      batch.update(doc, {'reviewPromptDismissed': true});
    }
    await batch.commit();
  }

  Future<void> submitReview(
    Booking booking,
    double rating,
    String comment,
    String? currentUserId, {
    double? punctualityRating,
    double? empathyRating,
    double? communicationRating,
    double? hygieneRating,
  }) async {
    await submitReviewForBookings(
      [booking],
      rating,
      comment,
      currentUserId,
      punctualityRating: punctualityRating,
      empathyRating: empathyRating,
      communicationRating: communicationRating,
      hygieneRating: hygieneRating,
    );
  }

  Future<void> submitReviewForBookings(
    List<Booking> bookings,
    double rating,
    String comment,
    String? currentUserId, {
    double? punctualityRating,
    double? empathyRating,
    double? communicationRating,
    double? hygieneRating,
    double tipAmount = 0.0,
  }) async {
    if (bookings.isEmpty) return;
    
    final firstBooking = bookings.first;
    String clientName = 'Familia';
    if (currentUserId != null && currentUserId.isNotEmpty) {
      try {
        final profile = await DependencyInjection.clients.getClient(currentUserId);
        if (profile != null && profile.name.trim().isNotEmpty) {
          final parts = profile.name.trim().split(RegExp(r'\s+'));
          clientName = parts.length > 1 ? 'Familia ${parts[1]}' : 'Familia ${parts[0]}';
        }
      } catch (_) {}
    } 
    
    final review = Review(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      caregiverId: firstBooking.caregiverId,
      clientId: firstBooking.clientId,
      clientName: clientName,
      rating: rating,
      punctualityRating: punctualityRating ?? rating,
      empathyRating: empathyRating ?? rating,
      communicationRating: communicationRating ?? rating,
      hygieneRating: hygieneRating ?? rating,
      comment: comment,
    );

    await DependencyInjection.reviews.addReview(firstBooking.caregiverId, review);

    if (tipAmount > 0) {
      firstBooking.tipAmount += tipAmount;
    }

    for (var b in bookings) {
      b.isReviewed = true;
      if (useFirebaseBackend && Firebase.apps.isNotEmpty) {
        final updateMap = <String, dynamic>{'isReviewed': true};
        if (b.id == firstBooking.id && tipAmount > 0) {
          updateMap['tipAmount'] = FieldValue.increment(tipAmount);
        }
        await FirebaseFirestore.instance.collection('bookings').doc(b.id).update(updateMap);
      }
    }
    notifyListeners();
  }

  Future<void> submitReport(String caregiverId, String bookingId, String reason, String description, String? currentUserId) async {
    final report = Report(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      reporterId: currentUserId ?? 'unknown',
      reportedId: caregiverId,
      bookingId: bookingId,
      reason: reason,
      description: description,
    );

    await DependencyInjection.reports.addReport(report);
  }

  @override
  void dispose() {
    _bookingsSubscription?.cancel();
    super.dispose();
  }
}

