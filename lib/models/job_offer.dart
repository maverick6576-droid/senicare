import 'package:cloud_firestore/cloud_firestore.dart';

enum JobOfferStatus { open, inProgress, completed, cancelled }

class JobOffer {
  final String id;
  final String clientId;
  final String clientName;
  final double clientLatitude;
  final double clientLongitude;
  final String title;
  final String description;
  final double pricePerHour;
  final int totalHours;
  final bool isRecurring;
  final List<int> recurringDaysOfWeek; // 1 (Mon) - 7 (Sun)
  final int recurringHoursPerDay;
  final int recurringWeeks;
  final String recurringStartTime;
  final DateTime startDate;
  final DateTime? endDate;
  JobOfferStatus status;
  String? acceptedCaregiverId;
  String? acceptedApplicationId;
  final bool isUrgent;
  final double urgencyBonusRate;
  final double clientFeeRate;
  String? paymentIntentId;
  String? transferGroup;
  final DateTime createdAt;

  bool get isExpired => status == JobOfferStatus.open && startDate.isBefore(DateTime.now());

  JobOffer({
    required this.id,
    required this.clientId,
    required this.clientName,
    required this.clientLatitude,
    required this.clientLongitude,
    required this.title,
    required this.description,
    required this.pricePerHour,
    required this.totalHours,
    required this.isRecurring,
    this.recurringDaysOfWeek = const [],
    this.recurringHoursPerDay = 0,
    this.recurringWeeks = 0,
    this.recurringStartTime = '',
    required this.startDate,
    this.endDate,
    this.status = JobOfferStatus.open,
    this.acceptedCaregiverId,
    this.acceptedApplicationId,
    required this.isUrgent,
    required this.urgencyBonusRate,
    this.clientFeeRate = 0.05,
    this.paymentIntentId,
    this.transferGroup,
    required this.createdAt,
  });

  factory JobOffer.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return JobOffer(
      id: doc.id,
      clientId: data['clientId'] ?? '',
      clientName: data['clientName'] ?? '',
      clientLatitude: (data['clientLatitude'] ?? 0.0).toDouble(),
      clientLongitude: (data['clientLongitude'] ?? 0.0).toDouble(),
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      pricePerHour: (data['pricePerHour'] ?? 0.0).toDouble(),
      totalHours: data['totalHours'] ?? 0,
      isRecurring: data['isRecurring'] ?? false,
      recurringDaysOfWeek: List<int>.from(data['recurringDaysOfWeek'] ?? []),
      recurringHoursPerDay: data['recurringHoursPerDay'] ?? 0,
      recurringWeeks: data['recurringWeeks'] ?? 0,
      recurringStartTime: data['recurringStartTime'] ?? '',
      startDate: (data['startDate'] as Timestamp).toDate(),
      endDate: data['endDate'] != null ? (data['endDate'] as Timestamp).toDate() : null,
      status: JobOfferStatus.values.firstWhere(
        (e) => e.toString().split('.').last == data['status'],
        orElse: () => JobOfferStatus.open,
      ),
      acceptedCaregiverId: data['acceptedCaregiverId'],
      acceptedApplicationId: data['acceptedApplicationId'],
      isUrgent: data['isUrgent'] ?? false,
      urgencyBonusRate: (data['urgencyBonusRate'] ?? 0.0).toDouble(),
      clientFeeRate: (data['clientFeeRate'] ?? 0.05).toDouble(),
      paymentIntentId: data['paymentIntentId'],
      transferGroup: data['transferGroup'],
      createdAt: data['createdAt'] != null ? (data['createdAt'] as Timestamp).toDate() : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'clientId': clientId,
      'clientName': clientName,
      'clientLatitude': clientLatitude,
      'clientLongitude': clientLongitude,
      'title': title,
      'description': description,
      'pricePerHour': pricePerHour,
      'totalHours': totalHours,
      'isRecurring': isRecurring,
      'recurringDaysOfWeek': recurringDaysOfWeek,
      'recurringHoursPerDay': recurringHoursPerDay,
      'recurringWeeks': recurringWeeks,
      'recurringStartTime': recurringStartTime,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
      'status': status.toString().split('.').last,
      'acceptedCaregiverId': acceptedCaregiverId,
      'acceptedApplicationId': acceptedApplicationId,
      'isUrgent': isUrgent,
      'urgencyBonusRate': urgencyBonusRate,
      'clientFeeRate': clientFeeRate,
      'paymentIntentId': paymentIntentId,
      'transferGroup': transferGroup,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
