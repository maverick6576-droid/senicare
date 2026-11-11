import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

enum BookingStatus { pendingPayment, pending, confirmed, completed, cancelled, cancelledLate }

class CareChecklistItem {
  final String id;
  final String title;
  bool completed;
  String? completedAt;

  CareChecklistItem({
    required this.id,
    required this.title,
    this.completed = false,
    this.completedAt,
  });

  factory CareChecklistItem.fromMap(Map<String, dynamic> map) {
    return CareChecklistItem(
      id: map['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: map['title']?.toString() ?? '',
      completed: map['completed'] == true,
      completedAt: map['completedAt']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'completed': completed,
      if (completedAt != null) 'completedAt': completedAt,
    };
  }
}

class Booking {
  final String id;
  final String clientId;
  final String caregiverId;
  final String caregiverName;
  final String day;
  final String slot;
  final double? clientLatitude;
  final double? clientLongitude;
  final String? bookingPin;
  BookingStatus status;
  final double cost;
  final double clientFee;
  final double caregiverCommissionRate;
  final double caregiverCommissionAmount;
  final double caregiverPayout;
  final double totalPaid;
  final String? transferGroup;
  final String? paymentIntentId;
  String escrowStatus;
  final String cancellationReason;
  bool isReviewed;
  bool reviewPromptDismissed;
  final DateTime createdAt;
  DateTime? checkInTime;
  DateTime? checkOutTime;
  final bool? isPunctual;
  bool disputeRequested;
  bool disputeEscalated;
  double? disputeAmount;
  String? disputeReason;
  String? disputeDescription;
  List<CareChecklistItem> careChecklist;
  String careNotes;
  List<String> carePhotoUrls;
  String liveStatus;
  DateTime? onTheWayAt;
  double tipAmount;

  DateTime? get scheduledStartTime {
    try {
      DateTime dayDate;
      if (day.contains('/')) {
        dayDate = DateFormat('dd/MM/yyyy').parse(day);
      } else {
        dayDate = DateFormat('yyyy-MM-dd').parse(day);
      }
      final startStr = slot.contains('-') ? slot.split('-')[0].trim() : slot.trim();
      final timeParts = startStr.split(':');
      return DateTime(dayDate.year, dayDate.month, dayDate.day, int.parse(timeParts[0]), int.parse(timeParts[1]));
    } catch (_) {
      return null;
    }
  }

  DateTime? get scheduledEndTime {
    try {
      DateTime dayDate;
      if (day.contains('/')) {
        dayDate = DateFormat('dd/MM/yyyy').parse(day);
      } else {
        dayDate = DateFormat('yyyy-MM-dd').parse(day);
      }
      if (slot.contains('-')) {
        final endStr = slot.split('-')[1].trim();
        final timeParts = endStr.split(':');
        return DateTime(dayDate.year, dayDate.month, dayDate.day, int.parse(timeParts[0]), int.parse(timeParts[1]));
      } else {
        final timeParts = slot.trim().split(':');
        return DateTime(dayDate.year, dayDate.month, dayDate.day, int.parse(timeParts[0]) + 1, int.parse(timeParts[1]));
      }
    } catch (_) {
      return null;
    }
  }

  bool get isExpired {
    final end = scheduledEndTime;
    if (end == null) return false;
    return end.isBefore(DateTime.now());
  }

  bool get isEscrowSettled => const {
        'released',
        'released_manual',
        'released_auto',
        'resolved_partial',
        'refunded',
        'cancelled',
      }.contains(escrowStatus);

  bool get isInProgressAwaitingCheckOut =>
      status == BookingStatus.confirmed &&
      checkInTime != null &&
      liveStatus != 'completed' &&
      checkOutTime == null &&
      !isEscrowSettled &&
      escrowStatus != 'disputed';

  bool get isOpenDisputePendingAction =>
      escrowStatus == 'disputed' && !isEscrowSettled;

  bool get isActive {
    if (status != BookingStatus.pending && status != BookingStatus.confirmed) {
      return false;
    }
    if (isEscrowSettled) return false;
    if (isOpenDisputePendingAction) return true;
    if (isInProgressAwaitingCheckOut) return true;
    return !isExpired;
  }

  /// Estimated caregiver net earnings for the service (excluding voluntary tips).
  double get netPayoutForCaregiver {
    if (escrowStatus == 'resolved_partial' && caregiverPayout > 0) {
      return caregiverPayout;
    }
    if (escrowStatus == 'resolved_partial' && disputeAmount != null) {
      return estimateNetAfterDispute(disputeAmount!);
    }
    if (caregiverPayout > 0) return caregiverPayout;
    if (cost <= 0) return 0.0;
    if (caregiverCommissionAmount > 0) {
      return (cost - caregiverCommissionAmount).clamp(0.0, cost);
    }
    final rate = caregiverCommissionRate > 0 ? caregiverCommissionRate : 0.18;
    return cost * (1.0 - rate);
  }

  /// Estimated caregiver net payout if [refundAmount] is deducted from [cost].
  double estimateNetAfterDispute(double refundAmount) {
    if (cost <= 0) return 0.0;
    final remaining = (cost - refundAmount).clamp(0.0, cost);
    final rate = caregiverCommissionRate > 0
        ? caregiverCommissionRate
        : (caregiverCommissionAmount > 0
            ? (caregiverCommissionAmount / cost).clamp(0.0, 0.99)
            : 0.18);
    return remaining * (1.0 - rate);
  }

  Booking({
    required this.id,
    this.clientId = '',
    required this.caregiverId,
    required this.caregiverName,
    required this.day,
    required this.slot,
    this.clientLatitude,
    this.clientLongitude,
    this.bookingPin,
    this.status = BookingStatus.pending,
    required this.cost,
    required this.clientFee,
    required this.caregiverCommissionRate,
    required this.caregiverCommissionAmount,
    required this.caregiverPayout,
    required this.totalPaid,
    this.transferGroup,
    this.paymentIntentId,
    this.escrowStatus = 'held',
    this.cancellationReason = '',
    this.isReviewed = false,
    this.reviewPromptDismissed = false,
    DateTime? createdAt,
    this.checkInTime,
    this.checkOutTime,
    this.isPunctual,
    this.disputeRequested = false,
    this.disputeEscalated = false,
    this.disputeAmount,
    this.disputeReason,
    this.disputeDescription,
    List<CareChecklistItem>? careChecklist,
    this.careNotes = '',
    List<String>? carePhotoUrls,
    this.liveStatus = 'scheduled',
    this.onTheWayAt,
    this.tipAmount = 0.0,
  })  : createdAt = createdAt ?? DateTime.now(),
        careChecklist = careChecklist ?? [],
        carePhotoUrls = carePhotoUrls ?? [];

  factory Booking.fromFirestore(DocumentSnapshot doc) {
    try {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>? ?? {};
      final rawChecklist = data['careChecklist'] as List<dynamic>? ?? [];
      final parsedChecklist = rawChecklist
          .whereType<Map>()
          .map((m) => CareChecklistItem.fromMap(Map<String, dynamic>.from(m)))
          .toList();
      final rawPhotos = data['carePhotoUrls'] as List<dynamic>? ?? [];
      final parsedPhotos = rawPhotos.map((e) => e.toString()).toList();

      return Booking(
        id: doc.id,
        clientId: data['clientId']?.toString() ?? '',
        caregiverId: data['caregiverId']?.toString() ?? '',
        caregiverName: data['caregiverName']?.toString() ?? '',
        day: data['day']?.toString() ?? '',
        slot: data['slot']?.toString() ?? '',
        clientLatitude: data['clientLatitude'] != null ? (data['clientLatitude'] as num).toDouble() : null,
        clientLongitude: data['clientLongitude'] != null ? (data['clientLongitude'] as num).toDouble() : null,
        bookingPin: data['bookingPin']?.toString(),
        status: BookingStatus.values.firstWhere(
          (e) => e.toString().split('.').last.toLowerCase() == (data['status']?.toString().toLowerCase() ?? ''),
          orElse: () => BookingStatus.pending,
        ),
        cost: (data['cost'] ?? 0).toDouble(),
        clientFee: (data['clientFee'] ?? 0).toDouble(),
        caregiverCommissionRate: (data['caregiverCommissionRate'] ?? 0).toDouble(),
        caregiverCommissionAmount: (data['caregiverCommissionAmount'] ?? 0).toDouble(),
        caregiverPayout: (data['caregiverPayout'] ?? 0).toDouble(),
        totalPaid: (data['totalPaid'] ?? 0).toDouble(),
        transferGroup: data['transferGroup']?.toString(),
        paymentIntentId: data['paymentIntentId']?.toString(),
        escrowStatus: data['escrowStatus']?.toString() ?? 'held',
        cancellationReason: data['cancellationReason']?.toString() ?? '',
        isReviewed: data['isReviewed'] ?? false,
        reviewPromptDismissed: data['reviewPromptDismissed'] ?? false,
        createdAt: (data['createdAt'] is Timestamp)
            ? (data['createdAt'] as Timestamp).toDate()
            : DateTime.now(),
        checkInTime: (data['checkInTime'] != null && data['checkInTime'] is Timestamp)
            ? (data['checkInTime'] as Timestamp).toDate()
            : null,
        checkOutTime: (data['checkOutTime'] != null && data['checkOutTime'] is Timestamp)
            ? (data['checkOutTime'] as Timestamp).toDate()
            : null,
        isPunctual: data['isPunctual'] as bool?,
        disputeRequested: data['disputeRequested'] ?? false,
        disputeEscalated: data['disputeEscalated'] ?? false,
        disputeAmount: data['disputeAmount'] != null ? (data['disputeAmount'] as num).toDouble() : null,
        disputeReason: data['disputeReason']?.toString(),
        disputeDescription: data['disputeDescription']?.toString(),
        careChecklist: parsedChecklist,
        careNotes: data['careNotes']?.toString() ?? '',
        carePhotoUrls: parsedPhotos,
        liveStatus: data['liveStatus']?.toString() ?? (data['checkInTime'] != null ? 'in_progress' : 'scheduled'),
        onTheWayAt: (data['onTheWayAt'] != null && data['onTheWayAt'] is Timestamp)
            ? (data['onTheWayAt'] as Timestamp).toDate()
            : null,
        tipAmount: (data['tipAmount'] as num?)?.toDouble() ?? 0.0,
      );
    } catch (e) {
      debugPrint('Error parsing Booking ${doc.id}: $e');
      return Booking(
        id: doc.id,
        clientId: '',
        caregiverId: '',
        caregiverName: 'Error de lectura',
        day: '-',
        slot: '-',
        cost: 0,
        clientFee: 0,
        caregiverCommissionRate: 0,
        caregiverCommissionAmount: 0,
        caregiverPayout: 0,
        totalPaid: 0,
      );
    }
  }

  Map<String, dynamic> toFirestore() {
    return {
      'clientId': clientId,
      'caregiverId': caregiverId,
      'caregiverName': caregiverName,
      'day': day,
      'slot': slot,
      if (clientLatitude != null) 'clientLatitude': clientLatitude,
      if (clientLongitude != null) 'clientLongitude': clientLongitude,
      if (bookingPin != null) 'bookingPin': bookingPin,
      'status': status.toString().split('.').last,
      'cost': cost,
      'clientFee': clientFee,
      'caregiverCommissionRate': caregiverCommissionRate,
      'caregiverCommissionAmount': caregiverCommissionAmount,
      'caregiverPayout': caregiverPayout,
      'totalPaid': totalPaid,
      'transferGroup': transferGroup,
      'paymentIntentId': paymentIntentId,
      'escrowStatus': escrowStatus,
      'cancellationReason': cancellationReason,
      'isReviewed': isReviewed,
      'reviewPromptDismissed': reviewPromptDismissed,
      'createdAt': Timestamp.fromDate(createdAt),
      if (checkInTime != null) 'checkInTime': Timestamp.fromDate(checkInTime!),
      if (checkOutTime != null) 'checkOutTime': Timestamp.fromDate(checkOutTime!),
      if (isPunctual != null) 'isPunctual': isPunctual,
      'disputeRequested': disputeRequested,
      'disputeEscalated': disputeEscalated,
      if (disputeAmount != null) 'disputeAmount': disputeAmount,
      if (disputeReason != null) 'disputeReason': disputeReason,
      if (disputeDescription != null) 'disputeDescription': disputeDescription,
      'careChecklist': careChecklist.map((e) => e.toMap()).toList(),
      'careNotes': careNotes,
      'carePhotoUrls': carePhotoUrls,
      'liveStatus': liveStatus,
      if (onTheWayAt != null) 'onTheWayAt': Timestamp.fromDate(onTheWayAt!),
      if (tipAmount > 0) 'tipAmount': tipAmount,
    };
  }

  Booking copyWith({
    String? id,
    String? clientId,
    String? caregiverId,
    String? caregiverName,
    String? day,
    String? slot,
    double? clientLatitude,
    double? clientLongitude,
    String? bookingPin,
    BookingStatus? status,
    double? cost,
    double? clientFee,
    double? caregiverCommissionRate,
    double? caregiverCommissionAmount,
    double? caregiverPayout,
    double? totalPaid,
    String? transferGroup,
    String? paymentIntentId,
    String? escrowStatus,
    String? cancellationReason,
    bool? isReviewed,
    bool? reviewPromptDismissed,
    DateTime? createdAt,
    DateTime? checkInTime,
    DateTime? checkOutTime,
    bool? isPunctual,
    bool? disputeRequested,
    bool? disputeEscalated,
    double? disputeAmount,
    String? disputeReason,
    String? disputeDescription,
    List<CareChecklistItem>? careChecklist,
    String? careNotes,
    List<String>? carePhotoUrls,
    String? liveStatus,
    DateTime? onTheWayAt,
    double? tipAmount,
  }) {
    return Booking(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      caregiverId: caregiverId ?? this.caregiverId,
      caregiverName: caregiverName ?? this.caregiverName,
      day: day ?? this.day,
      slot: slot ?? this.slot,
      clientLatitude: clientLatitude ?? this.clientLatitude,
      clientLongitude: clientLongitude ?? this.clientLongitude,
      bookingPin: bookingPin ?? this.bookingPin,
      status: status ?? this.status,
      cost: cost ?? this.cost,
      clientFee: clientFee ?? this.clientFee,
      caregiverCommissionRate:
          caregiverCommissionRate ?? this.caregiverCommissionRate,
      caregiverCommissionAmount:
          caregiverCommissionAmount ?? this.caregiverCommissionAmount,
      caregiverPayout: caregiverPayout ?? this.caregiverPayout,
      totalPaid: totalPaid ?? this.totalPaid,
      transferGroup: transferGroup ?? this.transferGroup,
      paymentIntentId: paymentIntentId ?? this.paymentIntentId,
      escrowStatus: escrowStatus ?? this.escrowStatus,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      isReviewed: isReviewed ?? this.isReviewed,
      reviewPromptDismissed:
          reviewPromptDismissed ?? this.reviewPromptDismissed,
      createdAt: createdAt ?? this.createdAt,
      checkInTime: checkInTime ?? this.checkInTime,
      checkOutTime: checkOutTime ?? this.checkOutTime,
      isPunctual: isPunctual ?? this.isPunctual,
      disputeRequested: disputeRequested ?? this.disputeRequested,
      disputeEscalated: disputeEscalated ?? this.disputeEscalated,
      disputeAmount: disputeAmount ?? this.disputeAmount,
      disputeReason: disputeReason ?? this.disputeReason,
      disputeDescription: disputeDescription ?? this.disputeDescription,
      careChecklist: careChecklist ?? List<CareChecklistItem>.from(this.careChecklist),
      careNotes: careNotes ?? this.careNotes,
      carePhotoUrls: carePhotoUrls ?? List<String>.from(this.carePhotoUrls),
      liveStatus: liveStatus ?? this.liveStatus,
      onTheWayAt: onTheWayAt ?? this.onTheWayAt,
      tipAmount: tipAmount ?? this.tipAmount,
    );
  }
}
