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
  bool _isLoadingBookings = false;
  String? _bookingError;
  Completer<void>? _refreshCompleter;

  int get currentLimit => _limit;
  bool get hasMore => bookings.length >= _limit;
  bool get isLoadingMore => _isLoadingMore;
  bool get isLoadingBookings => _isLoadingBookings;
  String? get bookingError => _bookingError;

  void _completeRefresh() {
    final completer = _refreshCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  void updateAuth(String? userId, String? role) {
    if (_currentUserId != userId || _currentRole != role) {
      _currentUserId = userId;
      _currentRole = role;
      _limit = 15;
      _isLoadingMore = false;
      _bookingError = null;
      _subscribeToBookings(notifyEmptySync: false);
    }
  }

  Future<void> refreshBookings() async {
    _completeRefresh();
    final completer = Completer<void>();
    _refreshCompleter = completer;
    _isLoadingMore = false;
    _bookingError = null;
    _subscribeToBookings(clearBookings: false);
    try {
      await completer.future.timeout(const Duration(seconds: 5));
    } catch (_) {
      // Avoid hanging pull-to-refresh if network/stream stays silent.
    } finally {
      if (identical(_refreshCompleter, completer)) {
        _refreshCompleter = null;
      }
    }
  }

  void retryBookings() {
    _subscribeToBookings(clearBookings: bookings.isEmpty);
  }

  void loadMoreBookings() {
    if (!hasMore || _isLoadingMore) return;
    _isLoadingMore = true;
    _limit += 15;
    _subscribeToBookings(clearBookings: false);
  }

  void _subscribeToBookings({
    bool clearBookings = true,
    bool notifyEmptySync = true,
  }) {
    _bookingsSubscription?.cancel();
    if (clearBookings) bookings.clear();

    if (_currentUserId == null || _currentRole == null || _currentRole == 'admin') {
      _isLoadingMore = false;
      _isLoadingBookings = false;
      _bookingError = null;
      _completeRefresh();
      if (notifyEmptySync) {
        notifyListeners();
      } else {
        Future.microtask(notifyListeners);
      }
      return;
    }

    _bookingError = null;
    if (bookings.isEmpty) {
      _isLoadingBookings = true;
    }

    final roleToStream = _currentRole == 'client' ? 'client' : 'caregiver';
    _bookingsSubscription = DependencyInjection.bookings
        .streamBookings(_currentUserId!, roleToStream, limit: _limit)
        .listen(
      (data) {
        bookings = data;
        _isLoadingMore = false;
        _isLoadingBookings = false;
        _bookingError = null;
        _completeRefresh();
        notifyListeners();
      },
      onError: (e) {
        debugPrint('Error in BookingNotifier stream: $e');
        _isLoadingMore = false;
        _isLoadingBookings = false;
        _bookingError =
            'No pudimos cargar tus reservas en este momento. Comprueba tu conexión e inténtalo de nuevo.';
        _completeRefresh();
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
      if (useFirebaseBackend && Firebase.apps.isNotEmpty) {
        final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
            .httpsCallable('caregiverRejectBooking');
        await callable.call({
          'bookingId': bookingId,
        });
      } else {
        await DependencyInjection.bookings
            .cancelBooking(bookingId, 'Rechazada por el cuidador', false);
      }
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

  Future<void> openDispute(
    String bookingId,
    double disputeAmount,
    String reason,
    String description,
  ) async {
    if (useFirebaseBackend && Firebase.apps.isNotEmpty) {
      await FirebaseFirestore.instance.collection('bookings').doc(bookingId).update({
        'escrowStatus': 'disputed',
        'disputeRequested': true,
        'disputeAmount': disputeAmount,
        'disputeReason': reason,
        'disputeDescription': description,
        'disputeOpenedAt': FieldValue.serverTimestamp(),
      });
    }

    final b = bookings.where((b) => b.id == bookingId).firstOrNull;
    if (b != null) {
      b.escrowStatus = 'disputed';
      b.disputeRequested = true;
      b.disputeAmount = disputeAmount;
      b.disputeReason = reason;
      b.disputeDescription = description;
      b.disputeEscalated = false;
      notifyListeners();
    }
  }

  Future<void> escalateDispute(String bookingId) async {
    if (useFirebaseBackend && Firebase.apps.isNotEmpty) {
      await FirebaseFirestore.instance.collection('bookings').doc(bookingId).update({
        'disputeEscalated': true,
      });
    }

    final b = bookings.where((b) => b.id == bookingId).firstOrNull;
    if (b != null) {
      b.disputeEscalated = true;
      notifyListeners();
    }
  }

  Future<void> acceptDisputeProposal(String bookingId) async {
    if (useFirebaseBackend && Firebase.apps.isNotEmpty) {
      final func = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('processResolutionAgreement');
      await func.call({'bookingId': bookingId});
    }

    final b = bookings.where((b) => b.id == bookingId).firstOrNull;
    if (b != null) {
      b.status = BookingStatus.completed;
      b.escrowStatus = 'resolved_partial';
      b.disputeRequested = false;
      notifyListeners();
    }
  }

  int _calculateRoundedHours(String slot) {
    if (!slot.contains('-')) return 1;
    try {
      final slotParts = slot.split('-');
      final startParts = slotParts[0].trim().split(':');
      final endParts = slotParts[1].trim().split(':');
      final startMins =
          int.parse(startParts[0]) * 60 + (startParts.length > 1 ? int.parse(startParts[1]) : 0);
      final endMins =
          int.parse(endParts[0]) * 60 + (endParts.length > 1 ? int.parse(endParts[1]) : 0);
      final diffHours = ((endMins - startMins).abs() / 60.0).round();
      return diffHours < 1 ? 1 : diffHours;
    } catch (e) {
      debugPrint('Error calculating hours for stats: $e');
      return 1;
    }
  }

  Future<void> releaseEscrow(String bookingId) async {
    final bool useCloud = useFirebaseBackend && Firebase.apps.isNotEmpty;
    if (useCloud) {
      final success = await StripeService.releaseEscrowPayment(
        bookingId: bookingId,
      );
      if (!success) {
        debugPrint('Stripe Transfer failed for booking $bookingId');
        throw Exception(
          'No se pudo liberar el pago al cuidador en este momento. Inténtalo de nuevo.',
        );
      }
    } else {
      await DependencyInjection.bookings.releaseEscrow(bookingId);
    }

    final b = bookings.where((b) => b.id == bookingId).firstOrNull;
    if (b != null) {
      b.status = BookingStatus.completed;
      b.escrowStatus = useCloud ? 'released_manual' : 'released';
      b.liveStatus = 'completed';

      final hours = _calculateRoundedHours(b.slot);
      await DependencyInjection.stats
          .addCompletedHours(b.clientId, b.caregiverId, hours);
      notifyListeners();
    }
  }

  Future<void> cancelBooking(String bookingId, String reason, bool isLate) async {
    try {
      if (useFirebaseBackend && Firebase.apps.isNotEmpty) {
        final HttpsCallable callable =
            FirebaseFunctions.instanceFor(region: 'europe-west1')
                .httpsCallable('cancelBookingProcess');
        await callable.call(<String, dynamic>{
          'bookingId': bookingId,
          'reason': reason,
          'isLate': isLate,
        });
      } else {
        await DependencyInjection.bookings
            .cancelBooking(bookingId, reason, isLate);
      }

      final idx = bookings.indexWhere((bk) => bk.id == bookingId);
      if (idx != -1) {
        bookings[idx] = bookings[idx].copyWith(
          status:
              isLate ? BookingStatus.cancelledLate : BookingStatus.cancelled,
          escrowStatus: isLate ? 'resolved_partial' : 'refunded',
          cancellationReason: reason,
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error cancelling booking: $e');
      rethrow;
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

  
  Future<void> dismissReviewPrompt(List<Booking> targetBookings) async {
    if (targetBookings.isEmpty) return;
    final ids = targetBookings.map((b) => b.id).toSet();
    for (final tb in targetBookings) {
      tb.reviewPromptDismissed = true;
    }
    for (final b in bookings) {
      if (ids.contains(b.id)) {
        b.reviewPromptDismissed = true;
      }
    }
    if (useFirebaseBackend && Firebase.apps.isNotEmpty) {
      final batch = FirebaseFirestore.instance.batch();
      for (final b in targetBookings) {
        final doc = FirebaseFirestore.instance.collection('bookings').doc(b.id);
        batch.update(doc, {'reviewPromptDismissed': true});
      }
      await batch.commit();
    }
    notifyListeners();
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
    _completeRefresh();
    super.dispose();
  }
}

