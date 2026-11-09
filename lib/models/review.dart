import 'package:cloud_firestore/cloud_firestore.dart';

class Review {
  final String id;
  final String caregiverId;
  final String clientId;
  final String clientName;
  final double rating;
  final String comment;
  final DateTime createdAt;

  Review({
    required this.id,
    required this.caregiverId,
    required this.clientId,
    required this.clientName,
    required this.rating,
    required this.comment,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory Review.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>? ?? {};
    return Review(
      id: doc.id,
      caregiverId: data['caregiverId']?.toString() ?? '',
      clientId: data['clientId']?.toString() ?? '',
      clientName: data['clientName']?.toString() ?? 'Anónimo',
      rating: (data['rating'] ?? 0).toDouble(),
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
      'comment': comment,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
