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
  bool isUrgent;
  double urgencyBonusRate;
  final double clientFeeRate;
  int applicationsCount;
  String? paymentIntentId;
  String? transferGroup;
  final DateTime createdAt;

  DateTime get effectiveStartDateTime {
    if (isRecurring &&
        recurringStartTime.contains(':') &&
        startDate.hour == 0 &&
        startDate.minute == 0) {
      final parts = recurringStartTime.split(':');
      final h = int.tryParse(parts[0]) ?? 0;
      final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
      return DateTime(startDate.year, startDate.month, startDate.day, h, m);
    }
    return startDate;
  }

  bool get isExpired =>
      status == JobOfferStatus.open &&
      !effectiveStartDateTime.isAfter(DateTime.now());

  bool get isBookingTimePassed =>
      !effectiveStartDateTime.isAfter(DateTime.now());

  bool get isActiveForClient {
    if (status == JobOfferStatus.open) return !isExpired;
    if (status == JobOfferStatus.inProgress) return !isBookingTimePassed;
    return false;
  }

  bool effectiveUrgency({bool? hasApplications, DateTime? now}) {
    if (isUrgent) return true;
    if (status != JobOfferStatus.open) return false;
    final refNow = now ?? DateTime.now();
    if (!effectiveStartDateTime.isAfter(refNow)) return false;
    final noApps = hasApplications != null ? !hasApplications : (applicationsCount == 0);
    if (!noApps) return false;
    final elapsedSinceCreated = refNow.difference(createdAt);
    final timeUntilStart = effectiveStartDateTime.difference(refNow);
    return elapsedSinceCreated >= const Duration(hours: 24) ||
        timeUntilStart < const Duration(hours: 24);
  }

  double effectiveUrgencyBonusRate({bool? hasApplications, DateTime? now}) {
    if (urgencyBonusRate > 0) return urgencyBonusRate;
    return effectiveUrgency(hasApplications: hasApplications, now: now) ? 0.10 : 0.0;
  }

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
    this.applicationsCount = 0,
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

    final createdAt = _parseDate(data['createdAt']) ?? DateTime.now();

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
      startDate: _parseDate(data['startDate']) ??
          _parseDate(data['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
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
      applicationsCount: _parseInt(data['applicationsCount']),
      paymentIntentId: data['paymentIntentId']?.toString(),
      transferGroup: data['transferGroup']?.toString(),
      createdAt: createdAt,
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
      'applicationsCount': applicationsCount,
      'paymentIntentId': paymentIntentId,
      'transferGroup': transferGroup,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
