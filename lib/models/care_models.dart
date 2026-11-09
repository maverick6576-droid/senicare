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

/// Represents the Patient's Medical, Access, Dependency Triage (Barthel) & Emergency Sheet.
class PatientMedicalSheet {
  final String patientName;
  final String conditions;
  final String allergies;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final String homeAccessInstructions;
  final String insurancePolicyNumber;
  int dependencyGrade; // 1: Grado I (Moderada), 2: Grado II (Severa), 3: Grado III (Gran Dependencia)
  bool requiresCraneTransfer; // Si requiere grúa / movilización de encamado
  String cognitiveStatus; // 'Lúcido', 'Deterioro Leve', 'Alzheimer / Demencia'
  bool rgpdArt9ConsentSigned; // Consentimiento expreso RGPD Art. 9 en 1 toque
  DateTime? rgpdConsentTimestamp;

  PatientMedicalSheet({
    this.patientName = 'Manuel Vila (82 años)',
    this.conditions = 'Movilidad con andador, hipertensión controlada, deterioro cognitivo leve.',
    this.allergies = 'Alergia a Penicilina • Dieta baja en sal',
    this.emergencyContactName = 'Laura Vila (Hija)',
    this.emergencyContactPhone = '+34 600 11 22 33',
    this.homeAccessInstructions = 'Calle Goya 42, 3º B • Portero automático 3B',
    this.insurancePolicyNumber = 'Póliza RC SeniCare #SC-2026-88412 (Cobertura 300.000 €)',
    this.dependencyGrade = 1,
    this.requiresCraneTransfer = false,
    this.cognitiveStatus = 'Deterioro Leve',
    this.rgpdArt9ConsentSigned = true,
    DateTime? rgpdConsentTimestamp,
  }) : rgpdConsentTimestamp = rgpdConsentTimestamp ?? DateTime(2026, 1, 15, 10, 30);

  String get dependencyGradeLabel {
    switch (dependencyGrade) {
      case 3:
        return 'Grado III (Gran Dependencia / Encamado)';
      case 2:
        return 'Grado II (Dependencia Severa)';
      default:
        return 'Grado I (Autonomía Parcial / Andador)';
    }
  }
}

/// Structured Shift Hand-off Report ("Informe de Cierre de Turno") inspired by Rover / Birdie.
class ShiftHandoffReport {
  final bool medicationGiven;
  final String mealIntake; // 'Completa', 'Parcial', 'Nula'
  final String seniorMood; // 'Tranquilo y animado', 'Estable', 'Agitado / Cansado'
  final bool keysReturnedAndLocked;
  final String summaryNote;
  final DateTime completedAt;

  const ShiftHandoffReport({
    required this.medicationGiven,
    required this.mealIntake,
    required this.seniorMood,
    this.keysReturnedAndLocked = true,
    required this.summaryNote,
    required this.completedAt,
  });
}

/// Represents a member of the shared "Círculo Familiar" (Family Circle) for multi-child coordination.
class FamilyCircleMember {
  final String id;
  final String name;
  final String relation;
  final String roleLabel; // 'Titular / Pagador', 'Familiar Supervisor', 'Médico / Coordinador'
  final bool receivesSosAlerts;
  final bool canApprovePayments;

  const FamilyCircleMember({
    required this.id,
    required this.name,
    required this.relation,
    required this.roleLabel,
    this.receivesSosAlerts = true,
    this.canApprovePayments = false,
  });
}

/// Represents an official Spanish tax/dependency invoice (Ley 39/2006 de Dependencia, IRPF & VeriFactu AEAT).
class OfficialCareInvoice {
  final String invoiceNumber;
  final String bookingId;
  final DateTime issueDate;
  final String familyFullName;
  final String familyNif;
  final String caregiverName;
  final String patientName;
  final String dependencyGradeLabel;
  final int durationHours;
  final double baseTaxableEur;
  final int vatRatePercent; // 4% IVA superreducido servicios de dependencia
  final double vatAmountEur;
  final double totalPaidEur;
  final String verifactuHash; // Huella digital encadenada SHA-256 (Reglamento VeriFactu AEAT)
  final String aeatVerificationQrUrl; // URL de cotejo en sede electrónica AEAT

  const OfficialCareInvoice({
    required this.invoiceNumber,
    required this.bookingId,
    required this.issueDate,
    required this.familyFullName,
    required this.familyNif,
    required this.caregiverName,
    required this.patientName,
    required this.dependencyGradeLabel,
    required this.durationHours,
    required this.baseTaxableEur,
    this.vatRatePercent = 4,
    required this.vatAmountEur,
    required this.totalPaidEur,
    this.verifactuHash = 'VF-SHA256-9A8F7C6B5E4D3C2B',
    this.aeatVerificationQrUrl = 'https://www2.agenciatributaria.gob.es/wlpl/TIKE-CONT/ValidarQR',
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
  final int maxDependencyGrade; // 1 (Grado I), 2 (Grado II), 3 (Grado III)
  final bool certifiedForCraneTransfer;
  bool hasStripeConnectedAccount;
  String maskedIban;
  String bankName;
  String stripePayoutStatus; // 'active', 'pending_verification', 'bank_rejected'
  DateTime? lastPayoutDate;
  final double latitude;
  final double longitude;
  bool instantBookEnabled; // Reserva Inmediata estilo Airbnb sin espera manual
  final int responseTimeMinutes;
  String dac7TaxNif;
  String sexualOffensesCertCsv; // Código Seguro de Verificación del Ministerio de Justicia
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
    this.maxDependencyGrade = 3,
    this.certifiedForCraneTransfer = true,
    this.hasStripeConnectedAccount = true,
    this.maskedIban = 'ES91 •••• •••• 4821',
    this.bankName = 'CaixaBank',
    this.stripePayoutStatus = 'active',
    this.lastPayoutDate,
    this.latitude = 40.4256,
    this.longitude = -3.6768,
    this.instantBookEnabled = true,
    this.responseTimeMinutes = 8,
    this.dac7TaxNif = '51894021-K',
    this.sexualOffensesCertCsv = 'CSV-MJUST-2026-884192',
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
  String caregiverId;
  String caregiverName;
  String? originalCaregiverName;
  bool wasSubstituted;
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
  final bool paidWithHourBundle;
  final String keyCustodyMethod;
  final String checkInPin;
  final DateTime createdAt;
  final DateTime bookingDate; // Exact scheduled start date/time for accurate 24h cancellation window
  DateTime? serviceEndTime;
  String escrowStatus; // 'held', 'pending_caregiver_connect', 'pending_settlement_transfer', 'pending_network_retry', 'cancelled_pending_caregiver_compensation', 'released', 'rejected_refunded', 'cancelled_settled', 'bank_chargeback'
  bool isEscrowReleased;
  bool isRefunded;
  bool isGpsCheckedIn;
  DateTime? checkInTime;
  DateTime? checkOutTime;
  ShiftHandoffReport? handoffReport;
  bool isDisputed;
  String? disputeReason;
  double refundedAmount;
  double caregiverCompensation;
  int? reviewRating;
  String? reviewComment;
  int? clientReviewRating; // Caregiver's 1-5 evaluation of the family/home environment
  String? clientReviewComment;
  OfficialCareInvoice? officialInvoice;
  final List<String> extensionPaymentIds;
  final List<CareLogEntry> careLogs;

  Booking({
    required this.id,
    this.clientId = 'client_demo_1',
    required this.caregiverId,
    required this.caregiverName,
    this.originalCaregiverName,
    this.wasSubstituted = false,
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
    this.paidWithHourBundle = false,
    this.keyCustodyMethod = 'Portería / Conserje',
    this.checkInPin = '4829',
    DateTime? createdAt,
    DateTime? bookingDate,
    this.serviceEndTime,
    this.escrowStatus = 'held',
    this.isEscrowReleased = false,
    this.isRefunded = false,
    this.isGpsCheckedIn = false,
    this.checkInTime,
    this.checkOutTime,
    this.handoffReport,
    this.isDisputed = false,
    this.disputeReason,
    double? refundedAmount,
    this.caregiverCompensation = 0.0,
    this.reviewRating,
    this.reviewComment,
    this.clientReviewRating,
    this.clientReviewComment,
    this.officialInvoice,
    List<String>? extensionPaymentIds,
    List<CareLogEntry>? careLogs,
  })  : createdAt = createdAt ?? DateTime.now(),
        bookingDate = bookingDate ?? computeNextBookingDate(day, slot, from: createdAt),
        refundedAmount = refundedAmount ?? 0.0,
        extensionPaymentIds = extensionPaymentIds ?? [],
        careLogs = careLogs ?? [];

  /// Computes the next calendar occurrence of a Spanish weekday (`Lunes`..`Domingo`) and `HH:mm` slot.
  static DateTime computeNextBookingDate(String day, String slot, {DateTime? from}) {
    final base = from ?? DateTime.now();
    const weekdayMap = <String, int>{
      'Lunes': DateTime.monday,
      'Martes': DateTime.tuesday,
      'Miércoles': DateTime.wednesday,
      'Jueves': DateTime.thursday,
      'Viernes': DateTime.friday,
      'Sábado': DateTime.saturday,
      'Domingo': DateTime.sunday,
    };
    final targetWeekday = weekdayMap[day] ?? base.weekday;
    int daysAhead = (targetWeekday - base.weekday) % 7;
    if (daysAhead <= 0) {
      daysAhead += 7; // Default to next occurrence so new bookings are >= 24h ahead unless specified
    }
    final parts = slot.split(':');
    final hour = parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 9) : 9;
    final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    final targetDate = base.add(Duration(days: daysAhead));
    return DateTime(targetDate.year, targetDate.month, targetDate.day, hour, minute);
  }

  /// Net amount released or scheduled to be released to the caregiver's connected bank account.
  /// Matches 1:1 with `calculateCaregiverPayout` in `functions/index.js`.
  double get caregiverNetEarnings =>
      double.parse((cost * (1.0 - (commissionRatePercent / 100.0))).toStringAsFixed(2));

  /// Blind Bidirectional Review status (inspired by Airbnb/TaskRabbit):
  /// Publicly visible once both Family and Caregiver have submitted their evaluation.
  bool get isBidirectionalReviewPublished =>
      reviewRating != null && clientReviewRating != null;
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
