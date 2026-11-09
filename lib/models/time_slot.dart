import 'package:cloud_firestore/cloud_firestore.dart';

class TimeSlot {
  final String id;
  final DateTime dateTime;
  bool isAvailable;

  TimeSlot({
    required this.id,
    required this.dateTime,
    this.isAvailable = true,
  });

  factory TimeSlot.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>? ?? {};
    return TimeSlot(
      id: doc.id,
      dateTime: (data['dateTime'] is Timestamp) ? (data['dateTime'] as Timestamp).toDate() : DateTime.now(),
      isAvailable: data['isAvailable'] ?? true,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'dateTime': Timestamp.fromDate(dateTime),
      'isAvailable': isAvailable,
    };
  }
}
