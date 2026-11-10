import 'package:cloud_firestore/cloud_firestore.dart';

class Review {
  final String id;
  final String caregiverId;
  final String clientId;
  final String clientName;
  final double rating;
  final double punctualityRating;
  final double empathyRating;
  final double communicationRating;
  final double hygieneRating;
  final String comment;
  final DateTime createdAt;

  Review({
    required this.id,
    required this.caregiverId,
    required this.clientId,
    required this.clientName,
    required this.rating,
    double? punctualityRating,
    double? empathyRating,
    double? communicationRating,
    double? hygieneRating,
    required this.comment,
    DateTime? createdAt,
  })  : punctualityRating = punctualityRating ?? rating,
        empathyRating = empathyRating ?? rating,
        communicationRating = communicationRating ?? rating,
        hygieneRating = hygieneRating ?? rating,
        createdAt = createdAt ?? DateTime.now();

  factory Review.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>? ?? {};
    final baseRating = (data['rating'] as num? ?? 5.0).toDouble();
    return Review(
      id: doc.id,
      caregiverId: data['caregiverId']?.toString() ?? '',
      clientId: data['clientId']?.toString() ?? '',
      clientName: data['clientName']?.toString() ?? 'Anónimo',
      rating: baseRating,
      punctualityRating: (data['punctualityRating'] as num?)?.toDouble() ?? baseRating,
      empathyRating: (data['empathyRating'] as num?)?.toDouble() ?? baseRating,
      communicationRating: (data['communicationRating'] as num?)?.toDouble() ?? baseRating,
      hygieneRating: (data['hygieneRating'] as num?)?.toDouble() ?? baseRating,
      comment: data['comment']?.toString() ?? '',
      createdAt: (data['createdAt'] is Timestamp)
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'caregiverId': caregiverId,
      'clientId': clientId,
      'clientName': clientName,
      'rating': rating,
      'punctualityRating': punctualityRating,
      'empathyRating': empathyRating,
      'communicationRating': communicationRating,
      'hygieneRating': hygieneRating,
      'comment': comment,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
