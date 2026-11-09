import 'package:cloud_firestore/cloud_firestore.dart';

class Report {
  final String id;
  final String reporterId;
  final String reportedId;
  final String bookingId;
  final String reason;
  final String description;
  final String status;
  final DateTime createdAt;

  Report({
    required this.id,
    required this.reporterId,
    required this.reportedId,
    required this.bookingId,
    required this.reason,
    required this.description,
    this.status = 'open',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory Report.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>? ?? {};
    return Report(
      id: doc.id,
      reporterId: data['reporterId']?.toString() ?? '',
      reportedId: data['reportedId']?.toString() ?? '',
      bookingId: data['bookingId']?.toString() ?? '',
      reason: data['reason']?.toString() ?? 'Otro',
      description: data['description']?.toString() ?? '',
      status: data['status']?.toString() ?? 'open',
      createdAt: (data['createdAt'] is Timestamp)
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'reporterId': reporterId,
      'reportedId': reportedId,
      'bookingId': bookingId,
      'reason': reason,
      'description': description,
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
