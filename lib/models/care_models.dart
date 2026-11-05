// ignore_for_file: constant_identifier_names

/// Defines the lifecycle stages of a Booking transaction in the SeniCare Escrow system.
enum BookingStatus {
  PendingApproval,
  Confirmed,
  InProgress,
  Completed,
  Cancelled,
  Disputed,
}

/// Identifies the sender in the chat interface.
enum ChatSender { Client, Caregiver, System }

/// Represents a medication item in the Senior Accessible Mode checklist.
class MedicationReminder {
  final String id;
  final String name;
  final String dosage;
  final String scheduledTime;
  bool isTaken;

  MedicationReminder({
    required this.id,
    required this.name,
    required this.dosage,
    required this.scheduledTime,
    this.isTaken = false,
  });
}

/// Represents an entry in the Daily Care Log ("Cuaderno de Cuidados") for family peace of mind.
class CareLogEntry {
  final String category; // 'Medicación', 'Alimentación', 'Paseo / Actividad', 'Estado de Ánimo'
  final String note;
  final DateTime timestamp;

  CareLogEntry({
    required this.category,
    required this.note,
    required this.timestamp,
  });
}

/// Core data model representing a Caretaker's profile in the marketplace.
class CaregiverProfile {
  final String id;
  final String name;
  final String title;
  final String bio;
  final double pricePerHour;
  final double rating;
  final int reviewsCount;
  final String distance;
  final String imageUrl;
  final List<String> specialties;
  final bool verified;
  final String verificationBadge;
  final int yearsExperience;
  final Map<String, List<String>> availableSlots;

  CaregiverProfile({
    required this.id,
    required this.name,
    required this.title,
    required this.bio,
    required this.pricePerHour,
    required this.rating,
    required this.reviewsCount,
    required this.distance,
    required this.imageUrl,
    required this.specialties,
    required this.verified,
    this.verificationBadge = 'DNI, Penales y Titulación Verificados',
    this.yearsExperience = 5,
    required this.availableSlots,
  });
}

/// Represents a commission calculation quote aligned with Firebase Cloud Functions (`calculateCaregiverPayout`).
class CommissionQuote {
  final double baseCost;
  final double commissionRate; // 0.18, 0.10, or 0.06
  final int commissionRatePercent; // 18, 10, or 6
  final String commissionTier;
  final double platformFee;
  final double caregiverNetPayout;
  final double totalClientPayable;

  const CommissionQuote({
    required this.baseCost,
    required this.commissionRate,
    required this.commissionRatePercent,
    required this.commissionTier,
    required this.platformFee,
    required this.caregiverNetPayout,
    required this.totalClientPayable,
  });
}

/// Represents a secure transaction and reservation with Escrow protection.
class Booking {
  final String id;
  final String clientId;
  final String caregiverId;
  final String caregiverName;
  final String day;
  final String slot;
  final int durationHours;
  BookingStatus status;
  final double cost;
  final double appCommission;
  final double totalPaid;
  final int commissionRatePercent;
  final String commissionTier;
  bool isEscrowReleased;
  bool isRefunded;
  bool isGpsCheckedIn;
  DateTime? checkInTime;
  DateTime? checkOutTime;
  bool isDisputed;
  String? disputeReason;
  double refundedAmount;
  double caregiverCompensation;
  final List<CareLogEntry> careLogs;

  Booking({
    required this.id,
    this.clientId = 'client_demo_1',
    required this.caregiverId,
    required this.caregiverName,
    required this.day,
    required this.slot,
    this.durationHours = 2,
    this.status = BookingStatus.PendingApproval,
    required this.cost,
    required this.appCommission,
    required this.totalPaid,
    this.commissionRatePercent = 18,
    this.commissionTier = '18% (Primer servicio con la familia)',
    this.isEscrowReleased = false,
    this.isRefunded = false,
    this.isGpsCheckedIn = false,
    this.checkInTime,
    this.checkOutTime,
    this.isDisputed = false,
    this.disputeReason,
    double? refundedAmount,
    this.caregiverCompensation = 0.0,
    List<CareLogEntry>? careLogs,
  })  : refundedAmount = refundedAmount ?? 0.0,
        careLogs = careLogs ?? [];

  /// Net amount released or scheduled to be released to the caregiver's connected bank account.
  double get caregiverNetEarnings => cost * (1.0 - (commissionRatePercent / 100.0));
}

/// A single message entity for the secured chat.
class ChatMessage {
  final ChatSender sender;
  final String text;
  final DateTime timestamp;
  final bool wasSanitized;

  ChatMessage({
    required this.sender,
    required this.text,
    required this.timestamp,
    this.wasSanitized = false,
  });
}
