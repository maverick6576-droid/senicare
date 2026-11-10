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
  final DateTime? checkInTime;
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

  bool get isExpired {
    try {
      DateTime dayDate;
      if (day.contains('/')) {
        dayDate = DateFormat('dd/MM/yyyy').parse(day);
      } else {
        dayDate = DateFormat('yyyy-MM-dd').parse(day);
      }
      DateTime slotEndTime;
      if (slot.contains('-')) {
        final endStr = slot.split('-')[1];
        final timeParts = endStr.split(':');
        slotEndTime = DateTime(dayDate.year, dayDate.month, dayDate.day, int.parse(timeParts[0]), int.parse(timeParts[1]));
      } else {
        final timeParts = slot.split(':');
        slotEndTime = DateTime(dayDate.year, dayDate.month, dayDate.day, int.parse(timeParts[0]) + 1, int.parse(timeParts[1]));
      }
      return slotEndTime.isBefore(DateTime.now());
    } catch (e) {
      return false;
    }
  }

  bool get isActive =>
      (status == BookingStatus.pending || status == BookingStatus.confirmed) &&
      status != BookingStatus.cancelled &&
      status != BookingStatus.cancelledLate &&
      escrowStatus != 'released' &&
      escrowStatus != 'resolved_partial' &&
      !isExpired;

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
    };
  }
}
