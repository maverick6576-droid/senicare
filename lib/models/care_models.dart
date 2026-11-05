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

/// Represents the Patient's Medical, Access & Emergency Sheet visible during active care.
class PatientMedicalSheet {
  final String patientName;
  final String conditions;
  final String allergies;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final String homeAccessInstructions;
  final String insurancePolicyNumber;

  const PatientMedicalSheet({
    this.patientName = 'Manuel Vila (82 años)',
    this.conditions = 'Movilidad con andador, hipertensión controlada, deterioro cognitivo leve.',
    this.allergies = 'Alergia a Penicilina • Dieta baja en sal',
    this.emergencyContactName = 'Laura Vila (Hija)',
    this.emergencyContactPhone = '+34 600 11 22 33',
    this.homeAccessInstructions = 'Calle Goya 42, 3º B • Portero automático 3B',
    this.insurancePolicyNumber = 'Póliza RC SeniCare #SC-2026-88412 (Cobertura 300.000 €)',
  });
}

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
  double rating;
  int reviewsCount;
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

/// Represents a commission calculation quote aligned 1:1 with Firebase Cloud Functions (`calculateCaregiverPayout`).
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
  int durationHours;
  int extendedHours;
  BookingStatus status;
  double cost;
  double appCommission;
  double totalPaid;
  final int commissionRatePercent;
  final String commissionTier;
  final bool isRecurringWeekly;
  final String keyCustodyMethod;
  final String checkInPin;
  final DateTime createdAt;
  DateTime? serviceEndTime;
  bool isEscrowReleased;
  bool isRefunded;
  bool isGpsCheckedIn;
  DateTime? checkInTime;
  DateTime? checkOutTime;
  bool isDisputed;
  String? disputeReason;
  double refundedAmount;
  double caregiverCompensation;
  int? reviewRating;
  String? reviewComment;
  final List<CareLogEntry> careLogs;

  Booking({
    required this.id,
    this.clientId = 'client_demo_1',
    required this.caregiverId,
    required this.caregiverName,
    required this.day,
    required this.slot,
    this.durationHours = 2,
    this.extendedHours = 0,
    this.status = BookingStatus.PendingApproval,
    required this.cost,
    required this.appCommission,
    required this.totalPaid,
    this.commissionRatePercent = 18,
    this.commissionTier = '18% (Primer servicio con la familia)',
    this.isRecurringWeekly = false,
    this.keyCustodyMethod = 'Portería / Conserje',
    this.checkInPin = '4829',
    DateTime? createdAt,
    this.serviceEndTime,
    this.isEscrowReleased = false,
    this.isRefunded = false,
    this.isGpsCheckedIn = false,
    this.checkInTime,
    this.checkOutTime,
    this.isDisputed = false,
    this.disputeReason,
    double? refundedAmount,
    this.caregiverCompensation = 0.0,
    this.reviewRating,
    this.reviewComment,
    List<CareLogEntry>? careLogs,
  })  : createdAt = createdAt ?? DateTime.now(),
        refundedAmount = refundedAmount ?? 0.0,
        careLogs = careLogs ?? [];

  /// Net amount released or scheduled to be released to the caregiver's connected bank account.
  /// Matches 1:1 with `calculateCaregiverPayout` in `functions/index.js`.
  double get caregiverNetEarnings =>
      double.parse((cost * (1.0 - (commissionRatePercent / 100.0))).toStringAsFixed(2));
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
