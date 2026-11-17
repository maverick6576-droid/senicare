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

  String get familyLabel {
    final clean = clientName.trim();
    if (clean.isEmpty || clean.toLowerCase() == 'cliente') {
      return 'Familia cercana';
    }
    if (clean.toLowerCase().startsWith('familia')) {
      return clean;
    }
    final parts = clean.split(RegExp(r'\s+'));
    if (parts.length > 1) {
      return 'Familia ${parts.last}';
    }
    return 'Familia de $clean';
  }

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
    this.clientFeeRate = 0.03,
    this.paymentIntentId,
    this.transferGroup,
    required this.createdAt,
  });

  static DateTime? _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }

  static double _parseDouble(dynamic value, {double fallback = 0.0}) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  static int _parseInt(dynamic value, {int fallback = 0}) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  factory JobOffer.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final rawDays = data['recurringDaysOfWeek'] as List<dynamic>? ?? const [];
    final parsedDays = rawDays
        .map((e) => _parseInt(e, fallback: -1))
        .where((d) => d >= 1 && d <= 7)
        .toList();

    return JobOffer(
      id: doc.id,
      clientId: data['clientId']?.toString() ?? '',
      clientName: data['clientName']?.toString() ?? '',
      clientLatitude: _parseDouble(data['clientLatitude']),
      clientLongitude: _parseDouble(data['clientLongitude']),
      title: data['title']?.toString() ?? '',
      description: data['description']?.toString() ?? '',
      pricePerHour: _parseDouble(data['pricePerHour']),
      totalHours: _parseInt(data['totalHours']),
      isRecurring: data['isRecurring'] == true,
      recurringDaysOfWeek: parsedDays,
      recurringHoursPerDay: _parseInt(data['recurringHoursPerDay']),
      recurringWeeks: _parseInt(data['recurringWeeks']),
      recurringStartTime: data['recurringStartTime']?.toString() ?? '',
      startDate: _parseDate(data['startDate']) ?? DateTime.now(),
      endDate: _parseDate(data['endDate']),
      status: JobOfferStatus.values.firstWhere(
        (e) => e.toString().split('.').last == data['status']?.toString(),
        orElse: () => JobOfferStatus.open,
      ),
      acceptedCaregiverId: data['acceptedCaregiverId']?.toString(),
      acceptedApplicationId: data['acceptedApplicationId']?.toString(),
      isUrgent: data['isUrgent'] == true,
      urgencyBonusRate: _parseDouble(data['urgencyBonusRate']),
      clientFeeRate: _parseDouble(data['clientFeeRate'], fallback: 0.03),
      paymentIntentId: data['paymentIntentId']?.toString(),
      transferGroup: data['transferGroup']?.toString(),
      createdAt: _parseDate(data['createdAt']) ?? DateTime.now(),
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
