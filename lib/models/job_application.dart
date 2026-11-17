import 'package:cloud_firestore/cloud_firestore.dart';

enum JobApplicationStatus { pending, accepted, rejected }

class JobApplication {
  final String id;
  final String offerId;
  final String caregiverId;
  final String caregiverName;
  final String caregiverImageUrl;
  final double caregiverRating;
  final int caregiverReviewsCount;
  final String message;
  final double proposedPrice;
  JobApplicationStatus status;
  final DateTime appliedAt;

  JobApplication({
    required this.id,
    required this.offerId,
    required this.caregiverId,
    required this.caregiverName,
    required this.caregiverImageUrl,
    required this.caregiverRating,
    required this.caregiverReviewsCount,
    required this.message,
    required this.proposedPrice,
    this.status = JobApplicationStatus.pending,
    required this.appliedAt,
  });

  static DateTime _parseAppliedAt(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }

  factory JobApplication.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? const <String, dynamic>{};
    return JobApplication(
      id: doc.id,
      offerId: data['offerId']?.toString() ?? '',
      caregiverId: data['caregiverId']?.toString() ?? '',
      caregiverName: data['caregiverName']?.toString() ?? '',
      caregiverImageUrl: data['caregiverImageUrl']?.toString() ?? '',
      caregiverRating: (data['caregiverRating'] as num?)?.toDouble() ?? 0.0,
      caregiverReviewsCount: (data['caregiverReviewsCount'] as num?)?.toInt() ?? 0,
      message: data['message']?.toString() ?? '',
      proposedPrice: (data['proposedPrice'] as num?)?.toDouble() ?? 0.0,
      status: JobApplicationStatus.values.firstWhere(
        (e) => e.toString().split('.').last == data['status']?.toString(),
        orElse: () => JobApplicationStatus.pending,
      ),
      appliedAt: _parseAppliedAt(data['appliedAt']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'offerId': offerId,
      'caregiverId': caregiverId,
      'caregiverName': caregiverName,
      'caregiverImageUrl': caregiverImageUrl,
      'caregiverRating': caregiverRating,
      'caregiverReviewsCount': caregiverReviewsCount,
      'message': message,
      'proposedPrice': proposedPrice,
      'status': status.toString().split('.').last,
      'appliedAt': Timestamp.fromDate(appliedAt),
    };
  }
}
