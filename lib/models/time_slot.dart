import 'package:cloud_firestore/cloud_firestore.dart';

class TimeSlot {
  final String id;
  final DateTime dateTime;
  final DateTime? endTime;
  bool isAvailable;

  TimeSlot({
    required this.id,
    required this.dateTime,
    this.endTime,
    this.isAvailable = true,
  });

  DateTime get effectiveEndTime =>
      endTime ?? dateTime.add(const Duration(hours: 1));

  int get durationMinutes {
    final mins = effectiveEndTime.difference(dateTime).inMinutes;
    return mins > 0 ? mins : 60;
  }

  factory TimeSlot.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>? ?? {};
    return TimeSlot(
      id: doc.id,
      dateTime: (data['dateTime'] is Timestamp)
          ? (data['dateTime'] as Timestamp).toDate()
          : DateTime.now(),
      endTime: (data['endTime'] is Timestamp)
          ? (data['endTime'] as Timestamp).toDate()
          : null,
      isAvailable: data['isAvailable'] ?? true,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'dateTime': Timestamp.fromDate(dateTime),
      if (endTime != null) 'endTime': Timestamp.fromDate(endTime!),
      'isAvailable': isAvailable,
    };
  }
}
