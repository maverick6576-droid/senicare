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

  factory JobApplication.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return JobApplication(
      id: doc.id,
      offerId: data['offerId'] ?? '',
      caregiverId: data['caregiverId'] ?? '',
      caregiverName: data['caregiverName'] ?? '',
      caregiverImageUrl: data['caregiverImageUrl'] ?? '',
      caregiverRating: (data['caregiverRating'] ?? 0.0).toDouble(),
      caregiverReviewsCount: data['caregiverReviewsCount'] ?? 0,
      message: data['message'] ?? '',
      proposedPrice: (data['proposedPrice'] ?? 0.0).toDouble(),
      status: JobApplicationStatus.values.firstWhere(
        (e) => e.toString().split('.').last == data['status'],
        orElse: () => JobApplicationStatus.pending,
      ),
      appliedAt: data['appliedAt'] != null ? (data['appliedAt'] as Timestamp).toDate() : DateTime.now(),
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
