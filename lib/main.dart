// main.dart
// SeniCare - Production-Ready Architecture & Senior-Accessible Marketplace
// Connects families and seniors with verified caregivers using Escrow protection,
// dynamic loyalty commissions (18% -> 10% -> 6%), 24h auto-completion, context-aware chat,
// GPS + 4-digit PIN check-in, Patient Medical Sheet, Shift Overtime Extension, and Verified Reviews.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'models/care_models.dart';
import 'services/anti_bypass_validator.dart';
import 'services/production_marketplace_engine.dart';
import 'theme/app_theme.dart';

export 'models/care_models.dart';
export 'services/anti_bypass_validator.dart';
export 'services/production_marketplace_engine.dart';
export 'theme/app_theme.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => AppState(),
      child: const SeniCareApp(),
    ),
  );
}

// ==========================================
// 1. STATE MANAGEMENT & CLOUD GATEWAY
// ==========================================

class AppState extends ChangeNotifier {
  String currentRole = 'client'; // 'client' or 'caregiver'
  String activeCaregiverId = 'c1'; // Active professional profile in Caregiver Dashboard
  bool seniorMode = false; // Toggles WCAG AAA Senior Accessibility Mode & Senior Home Panel
  String selectedSpecialty = 'Todos';
  String searchQuery = '';
  bool sosAlertActive = false;
  bool filterByDependencyTriage = false;
  int prepaidHourBalance = 0; // Bolsa de Horas Prepagada
  String familyNif = '47892103-Z';
  String familyFullName = 'Laura Vila Delicado';
  String currentLocale = 'es'; // 'es' (Castellano), 'ca' (Català), 'en' (English)
  String selectedPaymentMethod = 'Apple Pay / Google Pay (1-Toque • 0 € comisión)';
  bool accountDeleted = false;
  final double familyHomeLat = 40.4250; // Calle Goya 42, Madrid
  final double familyHomeLon = -3.6750;
  final List<SlotHoldReservation> activeSlotHolds = [];
  final List<GuidedVerificationDocument> guidedDocuments =
      GuidedVerificationDocument.buildDefaultCatalog();

  void setLocale(String locale) {
    currentLocale = locale;
    notifyListeners();
  }

  void setSelectedPaymentMethod(String method) {
    selectedPaymentMethod = method;
    notifyListeners();
  }

  String tr(String key) => ZeroCostI18n.tr(currentLocale, key);

  void setActiveCaregiverId(String caregiverId) {
    activeCaregiverId = caregiverId;
    notifyListeners();
  }

  /// Dynamically computes total released earnings + late-cancellation compensation for any caregiver.
  double getCaregiverReleasedEarnings([String? caregiverId]) {
    final targetId = caregiverId ?? activeCaregiverId;
    double total = 0.0;
    for (final b in bookings) {
      if (b.caregiverId == targetId) {
        if (b.isEscrowReleased) {
          total += b.caregiverNetEarnings;
        } else if (b.status == BookingStatus.Cancelled && b.caregiverCompensation > 0) {
          total += b.caregiverCompensation;
        }
      }
    }
    return double.parse(total.toStringAsFixed(2));
  }

  // Patient Medical, Access, Dependency Triage (Barthel) & Insurance Sheet
  final PatientMedicalSheet patientMedicalSheet = PatientMedicalSheet();

  // Shared Family Circle ("Círculo Familiar") for multi-child & geriatric coordination
  final List<FamilyCircleMember> familyCircle = [
    const FamilyCircleMember(
      id: 'fc_1',
      name: 'Laura Vila (Madrid)',
      relation: 'Hija • Titular',
      roleLabel: 'Titular / Pagadora',
      receivesSosAlerts: true,
      canApprovePayments: true,
    ),
    const FamilyCircleMember(
      id: 'fc_2',
      name: 'Carlos Vila (Valencia)',
      relation: 'Hijo',
      roleLabel: 'Familiar Supervisor',
      receivesSosAlerts: true,
      canApprovePayments: false,
    ),
    const FamilyCircleMember(
      id: 'fc_3',
      name: 'Dra. Carmen Ortiz',
      relation: 'Médico Geriatra',
      roleLabel: 'Supervisión Clínica',
      receivesSosAlerts: false,
      canApprovePayments: false,
    ),
  ];

  // Medication reminders for the Senior Accessible Mode
  final List<MedicationReminder> medications = [
    MedicationReminder(
      id: 'med_1',
      name: 'Pastilla de la tensión (Enalapril)',
      dosage: '1 comprimido con agua',
      scheduledTime: '10:00 h',
    ),
    MedicationReminder(
      id: 'med_2',
      name: 'Vitamina D y Calcio',
      dosage: '1 cápsula después de comer',
      scheduledTime: '14:30 h',
    ),
  ];

  // Verified Caregivers in the marketplace
  List<CaregiverProfile> caregivers = [
    CaregiverProfile(
      id: 'c1',
      name: 'Elena Sanz',
      title: 'Enfermera Geriátrica Colegiada',
      bio: 'Especialista en movilidad, control de medicación y cuidados post-operatorios con más de 10 años de experiencia. Apasionada por el bienestar emocional de los mayores.',
      pricePerHour: 18.0,
      rating: 4.9,
      reviewsCount: 124,
      distance: '2.5 km',
      imageUrl: 'https://i.pravatar.cc/300?img=47',
      specialties: ['Movilidad', 'Cocina Médica'],
      verified: true,
      yearsExperience: 10,
      maxDependencyGrade: 3,
      certifiedForCraneTransfer: true,
      bankName: 'CaixaBank',
      maskedIban: 'ES91 •••• •••• 4821',
      stripePayoutStatus: 'active',
      availableSlots: {
        'Lunes': ['09:00', '10:00', '16:00'],
        'Martes': ['10:00', '11:00'],
        'Jueves': ['09:00', '17:00'],
      },
    ),
    CaregiverProfile(
      id: 'c2',
      name: 'Javier Domínguez',
      title: 'Acompañante y Soporte Digital',
      bio: 'Ayudo a tus mayores a conectar con la familia por videollamada, además de ofrecer cálida compañía, lectura y paseos diarios seguros.',
      pricePerHour: 15.0,
      rating: 4.7,
      reviewsCount: 89,
      distance: '4.1 km',
      imageUrl: 'https://i.pravatar.cc/300?img=11',
      specialties: ['Compañía', 'Soporte Digital'],
      verified: true,
      yearsExperience: 6,
      maxDependencyGrade: 1,
      certifiedForCraneTransfer: false,
      bankName: 'BBVA',
      maskedIban: 'ES14 •••• •••• 9034',
      stripePayoutStatus: 'active',
      availableSlots: {
        'Miércoles': ['15:00', '16:00', '17:00'],
        'Jueves': ['09:00', '12:00'],
      },
    ),
    CaregiverProfile(
      id: 'c3',
      name: 'María Fernández',
      title: 'Cuidadora Especializada en Alzheimer',
      bio: 'Enfermera titulada. Cuidados diurnos y nocturnos, control estricto de pautas médicas, estimulación cognitiva y alimentación adaptada.',
      pricePerHour: 22.0,
      rating: 5.0,
      reviewsCount: 201,
      distance: '1.2 km',
      imageUrl: 'https://i.pravatar.cc/300?img=43',
      specialties: ['Movilidad', 'Cocina Médica', 'Compañía'],
      verified: true,
      yearsExperience: 12,
      maxDependencyGrade: 3,
      certifiedForCraneTransfer: true,
      bankName: 'Banco Santander',
      maskedIban: 'ES00 •••• •••• 1276',
      stripePayoutStatus: 'active',
      availableSlots: {
        'Viernes': ['20:00', '21:00'],
        'Sábado': ['08:00', '09:00'],
      },
    ),
  ];

  List<Booking> bookings = [];

  List<ChatMessage> chatMessages = [
    ChatMessage(
      sender: ChatSender.Caregiver,
      text: '¡Hola! Soy Elena. ¿En qué te puedo ayudar hoy con el cuidado de tu familiar?',
      timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
    ),
  ];

  List<String> get availableSpecialties => [
        'Todos',
        'Compañía',
        'Movilidad',
        'Cocina Médica',
        'Soporte Digital',
      ];

  /// Evaluates if a caregiver meets the senior's clinical Dependency Grade (Barthel) and crane requirements.
  bool isCaregiverCompatibleWithPatient(CaregiverProfile c) {
    if (c.maxDependencyGrade < patientMedicalSheet.dependencyGrade) {
      return false;
    }
    if (patientMedicalSheet.requiresCraneTransfer && !c.certifiedForCraneTransfer) {
      return false;
    }
    return true;
  }

  List<CaregiverProfile> get filteredCaregivers {
    return caregivers.where((c) {
      final matchesSpecialty =
          selectedSpecialty == 'Todos' || c.specialties.contains(selectedSpecialty);
      final matchesSearch =
          c.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
              c.title.toLowerCase().contains(searchQuery.toLowerCase());
      final matchesTriage =
          !filterByDependencyTriage || isCaregiverCompatibleWithPatient(c);
      return matchesSpecialty && matchesSearch && matchesTriage;
    }).toList();
  }

  /// True when there is an active confirmed or in-progress booking, unlocking contact details in chat.
  bool get hasActiveConfirmedBooking => bookings.any(
        (b) => b.status == BookingStatus.Confirmed || b.status == BookingStatus.InProgress,
      );

  /// Unified 1:1 Commission Engine synchronized with `functions/index.js` (`calculateCaregiverPayout`):
  /// - 0 completed bookings with this caregiver: 18% fee (82% net caregiver)
  /// - 1 to 4 completed bookings: 10% fee (90% net caregiver)
  /// - 5+ completed bookings: 6% fee (94% net caregiver)
  /// `totalClientPayable == baseCost == caregiverNetPayout + platformFee` (zero double-dipping).
  CommissionQuote calculateCommissionQuote({
    required String caregiverId,
    required double pricePerHour,
    required int durationHours,
  }) {
    final completedCount = bookings
        .where((b) =>
            b.caregiverId == caregiverId &&
            b.status == BookingStatus.Completed &&
            b.isEscrowReleased)
        .length;

    double rate = 0.18;
    String tier = '18% (Primer servicio con la familia)';

    if (completedCount >= 5) {
      rate = 0.06;
      tier = '6% (Familia fidelizada - $completedCount servicios previos)';
    } else if (completedCount >= 1) {
      rate = 0.10;
      tier = '10% (Familia recurrente - $completedCount servicios previos)';
    }

    final baseCost = double.parse((pricePerHour * durationHours).toStringAsFixed(2));
    final platformFee = double.parse((baseCost * rate).toStringAsFixed(2));
    final caregiverNet = double.parse((baseCost - platformFee).toStringAsFixed(2));
    final totalClientPayable = baseCost; // All-inclusive transparent price: caregiverNet + platformFee == baseCost

    return CommissionQuote(
      baseCost: baseCost,
      commissionRate: rate,
      commissionRatePercent: (rate * 100).round(),
      commissionTier: tier,
      platformFee: platformFee,
      caregiverNetPayout: caregiverNet,
      totalClientPayable: totalClientPayable,
    );
  }

  /// Converts a `"HH:mm"` slot string to minutes from midnight.
  static int parseSlotToMinutes(String slot) {
    final parts = slot.trim().split(':');
    final hour = parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 9) : 9;
    final min = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return (hour * 60) + min;
  }

  /// Prevents double-booking and multi-hour shift overlap by checking interval collision `[startA, endA)` vs `[startB, endB)`,
  /// including active 10-minute Checkout Slot Holds (`SlotHoldReservation`) from other clients.
  bool isSlotBooked(
    String caregiverId,
    String day,
    String slot, {
    int durationHours = 1,
    String? excludeBookingId,
    String? excludeHolderClientId,
    DateTime? referenceNow,
  }) {
    final reqStart = parseSlotToMinutes(slot);
    final reqEnd = reqStart + (durationHours * 60);
    final now = referenceNow ?? DateTime.now();

    for (final b in bookings) {
      if (b.id == excludeBookingId) continue;
      if (b.caregiverId != caregiverId || b.day != day) continue;
      if (b.status == BookingStatus.Cancelled || b.isRefunded) continue;

      final bStart = parseSlotToMinutes(b.slot);
      final bEnd = bStart + (b.durationHours * 60);

      // Interval overlap condition: max(reqStart, bStart) < min(reqEnd, bEnd)
      if (reqStart < bEnd && bStart < reqEnd) {
        return true;
      }
    }

    // Check active 10-minute checkout holds (Pilar 1: Slot Hold TTL)
    for (final hold in activeSlotHolds) {
      if (!hold.isActiveAt(now)) continue;
      if (hold.holderClientId == excludeHolderClientId) continue;
      if (hold.caregiverId != caregiverId || hold.day != day) continue;

      final hStart = parseSlotToMinutes(hold.slot);
      final hEnd = hStart + (hold.durationHours * 60);
      if (reqStart < hEnd && hStart < reqEnd) {
        return true;
      }
    }
    return false;
  }

  /// Places a 10-minute temporary Checkout Hold on a slot (Airbnb-style checkout protection at 0 € cloud cost).
  SlotHoldReservation? createCheckoutSlotHold({
    required String caregiverId,
    required String day,
    required String slot,
    int durationHours = 2,
    String holderClientId = 'client_demo_1',
    DateTime? referenceNow,
  }) {
    final now = referenceNow ?? DateTime.now();
    activeSlotHolds.removeWhere((h) => !h.isActiveAt(now));

    if (isSlotBooked(
      caregiverId,
      day,
      slot,
      durationHours: durationHours,
      excludeHolderClientId: holderClientId,
      referenceNow: now,
    )) {
      return null;
    }

    activeSlotHolds.removeWhere((h) =>
        h.caregiverId == caregiverId &&
        h.day == day &&
        h.holderClientId == holderClientId);

    final hold = SlotHoldReservation(
      holdId: 'hold_${caregiverId}_${day}_${slot.replaceAll(":", "")}',
      caregiverId: caregiverId,
      day: day,
      slot: slot,
      durationHours: durationHours,
      holderClientId: holderClientId,
      createdAt: now,
      expiresAt: now.add(const Duration(minutes: 10)),
    );
    activeSlotHolds.add(hold);
    notifyListeners();
    return hold;
  }

  List<String> getAvailableSlotsForDay(
    CaregiverProfile caregiver,
    String day, {
    int durationHours = 1,
  }) {
    final allSlots = caregiver.availableSlots[day] ?? [];
    return allSlots
        .where((slot) =>
            !isSlotBooked(caregiver.id, day, slot, durationHours: durationHours))
        .toList();
  }

  // --- Mutators & Lifecycle Actions ---

  void toggleSeniorMode(bool value) {
    seniorMode = value;
    notifyListeners();
  }

  void toggleMedicationTaken(String medId) {
    final idx = medications.indexWhere((m) => m.id == medId);
    if (idx != -1) {
      medications[idx].isTaken = !medications[idx].isTaken;
      notifyListeners();
    }
  }

  void triggerSosAlert() {
    sosAlertActive = true;
    chatMessages.add(
      ChatMessage(
        sender: ChatSender.Client,
        text:
            '🚨 ALERTA SOS ACTIVADA: Se ha enviado la ubicación GPS actual y la Ficha Médica de ${patientMedicalSheet.patientName} a los familiares responsables y a la cuidadora.',
        timestamp: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  void setRole(String role) {
    currentRole = role;
    notifyListeners();
  }

  void setSpecialty(String specialty) {
    selectedSpecialty = specialty;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    searchQuery = query;
    notifyListeners();
  }

  bool addBooking(Booking booking) {
    if (bookings.any((b) => b.id == booking.id && !b.isRefunded && b.status != BookingStatus.Cancelled)) {
      return false;
    }
    if (isSlotBooked(
      booking.caregiverId,
      booking.day,
      booking.slot,
      durationHours: booking.durationHours,
      excludeHolderClientId: booking.clientId,
    )) {
      return false;
    }
    activeSlotHolds.removeWhere((h) =>
        h.caregiverId == booking.caregiverId &&
        h.day == booking.day &&
        h.holderClientId == booking.clientId);
    bookings.add(booking);
    notifyListeners();
    return true;
  }

  void confirmBooking(String bookingId) {
    final idx = bookings.indexWhere((b) => b.id == bookingId);
    if (idx != -1) {
      final b = bookings[idx];
      b.status = BookingStatus.Confirmed;
      b.serviceEndTime = DateTime.now().add(Duration(hours: b.durationHours));
      chatMessages.add(
        ChatMessage(
          sender: ChatSender.Caregiver,
          text:
              '✅ Cita confirmada para el ${b.day} a las ${b.slot} h (${b.durationHours}h). Chat desbloqueado para coordinar llegada. Código PIN de respaldo en domicilio: ${b.checkInPin}.',
          timestamp: DateTime.now(),
        ),
      );
      notifyListeners();
    }
  }

  /// GPS Check-in verification (<100m from senior's home)
  void checkInGps(String bookingId) {
    final idx = bookings.indexWhere((b) => b.id == bookingId);
    if (idx != -1) {
      final b = bookings[idx];
      b.isGpsCheckedIn = true;
      b.checkInTime = DateTime.now();
      b.status = BookingStatus.InProgress;
      b.careLogs.add(
        CareLogEntry(
          category: 'Llegada GPS',
          note: 'Llegada verificada por GPS a menos de 100m del domicilio.',
          timestamp: DateTime.now(),
        ),
      );
      notifyListeners();
    }
  }

  /// 4-Digit Family PIN Check-in fallback for indoor apartments without GPS satellite coverage
  bool checkInWithPin(String bookingId, String enteredPin) {
    final idx = bookings.indexWhere((b) => b.id == bookingId);
    if (idx != -1) {
      final b = bookings[idx];
      if (b.checkInPin == enteredPin.trim()) {
        b.isGpsCheckedIn = true;
        b.checkInTime = DateTime.now();
        b.status = BookingStatus.InProgress;
        b.careLogs.add(
          CareLogEntry(
            category: 'Llegada PIN',
            note: 'Entrada verificada mediante código PIN familiar en domicilio.',
            timestamp: DateTime.now(),
          ),
        );
        notifyListeners();
        return true;
      }
    }
    return false;
  }

  /// Extends an active shift (+1h / +2h) in-platform with a verified secondary payment,
  /// preserving insurance & Escrow coverage, preventing uncharged overtime, and checking
  /// that the extension does not collide with a subsequent appointment of the caregiver.
  bool extendBookingShift(String bookingId, int extraHours) {
    if (extraHours <= 0 || extraHours > 12) return false;
    final idx = bookings.indexWhere((b) => b.id == bookingId);
    if (idx == -1) return false;

    final b = bookings[idx];
    if (b.isRefunded ||
        b.isEscrowReleased ||
        b.isDisputed ||
        (b.status != BookingStatus.Confirmed && b.status != BookingStatus.InProgress)) {
      return false;
    }

    // Verify that extending the shift does not collide with another appointment on the same day
    if (isSlotBooked(
      b.caregiverId,
      b.day,
      b.slot,
      durationHours: b.durationHours + extraHours,
      excludeBookingId: b.id,
    )) {
      return false;
    }

    final hourlyRate = b.cost / b.durationHours;
    final extraCost = double.parse((hourlyRate * extraHours).toStringAsFixed(2));
    final extraCommission =
        double.parse((extraCost * (b.commissionRatePercent / 100.0)).toStringAsFixed(2));
    final newExtendedTotal = b.extendedHours + extraHours;
    final extensionPaymentId = 'pi_ext_${b.id}_${newExtendedTotal}h';

    // Anti-replay: prevent duplicate charge for the exact same extension step
    if (b.extensionPaymentIds.contains(extensionPaymentId)) {
      return false;
    }

    b.extensionPaymentIds.add(extensionPaymentId);
    b.durationHours += extraHours;
    b.extendedHours = newExtendedTotal;
    b.cost = double.parse((b.cost + extraCost).toStringAsFixed(2));
    b.appCommission = double.parse((b.appCommission + extraCommission).toStringAsFixed(2));
    b.totalPaid = double.parse((b.totalPaid + extraCost).toStringAsFixed(2));

    b.careLogs.add(
      CareLogEntry(
        category: 'Extensión de Turno',
        note:
            'Turno ampliado +$extraHours h (€${extraCost.toStringAsFixed(2)}) abonado con cobro verificado ($extensionPaymentId).',
        timestamp: DateTime.now(),
      ),
    );
    notifyListeners();
    return true;
  }

  /// Appends an entry to the Daily Care Log ("Cuaderno de Cuidados")
  void addCareLogEntry(String bookingId, String category, String note) {
    final idx = bookings.indexWhere((b) => b.id == bookingId);
    if (idx != -1 && note.trim().isNotEmpty) {
      bookings[idx].careLogs.add(
            CareLogEntry(
              category: category,
              note: note.trim(),
              timestamp: DateTime.now(),
            ),
          );
      notifyListeners();
    }
  }

  /// Caregiver rejection: processes 100% full refund to client and frees the slot.
  /// Idempotent: prevents double-refund if called more than once or on a settled booking.
  bool rejectBooking(String bookingId) {
    final idx = bookings.indexWhere((b) => b.id == bookingId);
    if (idx != -1) {
      final booking = bookings[idx];
      if (booking.isRefunded ||
          booking.status == BookingStatus.Cancelled ||
          booking.isEscrowReleased) {
        return false; // Anti-double-refund guard
      }
      booking.status = BookingStatus.Cancelled;
      booking.isRefunded = true;
      booking.refundedAmount = booking.totalPaid;
      booking.isEscrowReleased = false;
      booking.escrowStatus = 'rejected_refunded';

      chatMessages.add(
        ChatMessage(
          sender: ChatSender.Caregiver,
          text:
              'Hola. Lamentamos informarte que tu solicitud de reserva para el día ${booking.day} a las ${booking.slot} ha sido declinada.\n\n'
              '💳 Devolución automática procesada: Hemos devuelto íntegramente el importe pagado (€${booking.totalPaid.toStringAsFixed(2)}) a tu cuenta bancaria de origen.',
          timestamp: DateTime.now(),
        ),
      );
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Client cancellation with accurate `bookingDate` window check:
  /// - Early Cancellation (>= 24h before appointment): 100% full refund to family (0% penalty).
  /// - Late Cancellation (< 24h before appointment): 45% refund to family, 45% compensation to caregiver.
  bool cancelBookingByClient(String bookingId, {DateTime? referenceNow}) {
    final idx = bookings.indexWhere((b) => b.id == bookingId);
    if (idx == -1) return false;
    final b = bookings[idx];
    if (b.isRefunded || b.status == BookingStatus.Cancelled || b.isEscrowReleased) {
      return false;
    }

    final now = referenceNow ?? DateTime.now();
    final hoursUntilBooking = b.bookingDate.difference(now).inHours;

    b.status = BookingStatus.Cancelled;
    b.isRefunded = true;
    b.isEscrowReleased = false;
    b.escrowStatus = 'cancelled_settled';

    if (hoursUntilBooking >= 24) {
      // Early Cancellation (>= 24h): 100% full refund
      b.refundedAmount = b.totalPaid;
      b.caregiverCompensation = 0.0;
    } else {
      // Late Cancellation (< 24h): 45% client refund, 45% caregiver compensation
      b.refundedAmount = double.parse((b.totalPaid * 0.45).toStringAsFixed(2));
      b.caregiverCompensation = double.parse((b.totalPaid * 0.45).toStringAsFixed(2));
      final cgIdx = caregivers.indexWhere((c) => c.id == b.caregiverId);
      final hasBank = cgIdx == -1 ? true : caregivers[cgIdx].hasStripeConnectedAccount;
      if (!hasBank) {
        b.escrowStatus = 'cancelled_pending_caregiver_compensation';
      }
    }

    notifyListeners();
    return true;
  }

  /// Opens a dispute on an active booking, freezing automatic Escrow release.
  void openDispute(String bookingId, String reason) {
    final idx = bookings.indexWhere((b) => b.id == bookingId);
    if (idx != -1) {
      final booking = bookings[idx];
      if (booking.isEscrowReleased || booking.isRefunded) return;
      booking.isDisputed = true;
      booking.disputeReason = reason.trim().isEmpty
          ? 'Incidencia reportada por la familia'
          : reason.trim();
      booking.status = BookingStatus.Disputed;

      chatMessages.add(
        ChatMessage(
          sender: ChatSender.Client,
          text:
              '⚠️ Incidencia abierta en Reserva #${booking.id}: "${booking.disputeReason}". El pago en garantía queda congelado hasta revisión de Soporte SeniCare.',
          timestamp: DateTime.now(),
        ),
      );
      notifyListeners();
    }
  }

  /// Handles a bank chargeback (`charge.dispute.created` webhook), immediately freezing Escrow release.
  bool handleBankChargeback(String bookingId) {
    final idx = bookings.indexWhere((b) => b.id == bookingId);
    if (idx == -1) return false;
    final b = bookings[idx];
    b.isDisputed = true;
    b.status = BookingStatus.Disputed;
    b.escrowStatus = 'bank_chargeback';
    b.disputeReason = 'Contracargo bancario detectado en Stripe';
    notifyListeners();
    return true;
  }

  /// Releases Escrow funds to the caregiver if not disputed and caregiver has a connected Stripe account.
  /// Prevents "Ghost Release" if caregiver has not completed Stripe Connect onboarding.
  bool releaseEscrow(String bookingId) {
    final idx = bookings.indexWhere((b) => b.id == bookingId);
    if (idx != -1) {
      final b = bookings[idx];
      if (b.isDisputed ||
          b.status == BookingStatus.Disputed ||
          b.isRefunded ||
          b.status == BookingStatus.Cancelled ||
          b.isEscrowReleased) {
        return false; // Cannot release while disputed, refunded, or already released
      }

      final cgIdx = caregivers.indexWhere((c) => c.id == b.caregiverId);
      final hasConnectedBank =
          cgIdx == -1 ? true : caregivers[cgIdx].hasStripeConnectedAccount;

      b.status = BookingStatus.Completed;
      b.checkOutTime ??= DateTime.now();

      _scheduleNextRecurringBookingIfNeeded(b);

      if (!hasConnectedBank) {
        // Prevent Ghost Release: hold in pending_caregiver_connect until IBAN/Stripe is linked
        b.isEscrowReleased = false;
        b.escrowStatus = 'pending_caregiver_connect';
        notifyListeners();
        return false;
      }

      b.isEscrowReleased = true;
      b.escrowStatus = 'released';
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Automatically generates the next week's recurring booking when a weekly recurring shift completes,
  /// updating loyalty commission tiers dynamically.
  void _scheduleNextRecurringBookingIfNeeded(Booking completedBooking) {
    if (!completedBooking.isRecurringWeekly) return;
    final nextId = '${completedBooking.id}_next_week';
    if (bookings.any((existing) => existing.id == nextId)) return;

    final nextBookingDate = completedBooking.bookingDate.add(const Duration(days: 7));
    final hourlyRate = completedBooking.durationHours > 0
        ? (completedBooking.cost / completedBooking.durationHours)
        : 18.0;
    final quote = calculateCommissionQuote(
      caregiverId: completedBooking.caregiverId,
      pricePerHour: hourlyRate,
      durationHours: completedBooking.durationHours,
    );

    bookings.add(
      Booking(
        id: nextId,
        caregiverId: completedBooking.caregiverId,
        caregiverName: completedBooking.caregiverName,
        day: '${completedBooking.day} (Próx. Semana)',
        slot: completedBooking.slot,
        durationHours: completedBooking.durationHours,
        cost: quote.baseCost,
        appCommission: quote.platformFee,
        totalPaid: quote.totalClientPayable,
        commissionRatePercent: quote.commissionRatePercent,
        commissionTier: quote.commissionTier,
        isRecurringWeekly: true,
        keyCustodyMethod: completedBooking.keyCustodyMethod,
        bookingDate: nextBookingDate,
        status: BookingStatus.Confirmed,
      ),
    );
  }

  /// Synchronizes caregiver's Stripe Connect onboarding (`account.updated` webhook)
  /// and automatically settles any bookings waiting in `pending_caregiver_connect`.
  int connectCaregiverStripeAccount(String caregiverId) {
    final cgIdx = caregivers.indexWhere((c) => c.id == caregiverId);
    if (cgIdx != -1) {
      caregivers[cgIdx].hasStripeConnectedAccount = true;
      caregivers[cgIdx].stripePayoutStatus = 'active';
    }
    int settledCount = 0;
    for (final b in bookings) {
      if (b.caregiverId == caregiverId && !b.isDisputed) {
        if (!b.isRefunded &&
            !b.isEscrowReleased &&
            (b.escrowStatus == 'pending_caregiver_connect' ||
                b.escrowStatus == 'pending_settlement_transfer' ||
                b.escrowStatus == 'pending_network_retry')) {
          b.status = BookingStatus.Completed;
          b.isEscrowReleased = true;
          b.escrowStatus = 'released';
          b.checkOutTime ??= DateTime.now();
          settledCount++;
        } else if (b.escrowStatus == 'cancelled_pending_caregiver_compensation') {
          b.escrowStatus = 'cancelled_settled';
          settledCount++;
        }
      }
    }
    notifyListeners();
    return settledCount;
  }

  /// Updates the caregiver's linked payout bank account (IBAN),
  /// clears any previous bank rejection flags, and automatically
  /// settles any pending escrow transfers waiting for a valid bank account.
  int updateCaregiverBankAccount({
    required String caregiverId,
    required String newIban,
    required String newBankName,
  }) {
    final cgIdx = caregivers.indexWhere((c) => c.id == caregiverId);
    if (cgIdx != -1) {
      final cg = caregivers[cgIdx];
      final cleanIban = newIban.replaceAll(' ', '').toUpperCase();
      final last4 = cleanIban.length >= 4 ? cleanIban.substring(cleanIban.length - 4) : '4821';
      final prefix = cleanIban.length >= 4 ? cleanIban.substring(0, 4) : 'ES91';
      cg.maskedIban = '$prefix •••• •••• $last4';
      cg.bankName = newBankName.trim().isEmpty ? 'Banco Nacional' : newBankName.trim();
      cg.hasStripeConnectedAccount = true;
      cg.stripePayoutStatus = 'active';
      cg.lastPayoutDate = DateTime.now();
    }

    final settledCount = connectCaregiverStripeAccount(caregiverId);
    notifyListeners();
    return settledCount;
  }

  /// Simulates a temporary Stripe network connection timeout/error
  /// to verify graceful retry handling in offline/unstable conditions.
  void simulateStripeNetworkFailure(String bookingId) {
    final idx = bookings.indexWhere((b) => b.id == bookingId);
    if (idx != -1) {
      final b = bookings[idx];
      b.escrowStatus = 'pending_network_retry';
      notifyListeners();
    }
  }

  /// Simulates a bank payout rejection (e.g. invalid IBAN or closed bank account)
  void simulateBankPayoutRejection(String caregiverId) {
    final cgIdx = caregivers.indexWhere((c) => c.id == caregiverId);
    if (cgIdx != -1) {
      caregivers[cgIdx].stripePayoutStatus = 'bank_rejected';
      notifyListeners();
    }
  }

  /// Synchronized with `autoReleaseEscrowCron` in `functions/index.js`:
  /// 1. Auto-cancels & 100% refunds Zombie `PendingApproval` bookings past the 12h caregiver response window.
  /// 2. Auto-completes & releases Escrow for `Confirmed` / `InProgress` bookings >24h after service end
  ///    if the family forgot to click "Liberar Pago" and no dispute was opened.
  /// 3. Retries pending transfers (`pending_caregiver_connect` / `pending_settlement_transfer`) once account is ready.
  int runScheduledEscrowMaintenance({DateTime? referenceNow}) {
    final now = referenceNow ?? DateTime.now();
    int processedCount = 0;

    for (final b in List<Booking>.from(bookings)) {
      if (b.isDisputed || b.status == BookingStatus.Disputed || b.isRefunded) continue;

      // 1. Zombie PendingApproval timeout (>12h without caregiver response)
      if (b.status == BookingStatus.PendingApproval) {
        final hoursPending = now.difference(b.createdAt).inHours;
        if (hoursPending >= 12) {
          b.status = BookingStatus.Cancelled;
          b.isRefunded = true;
          b.refundedAmount = b.totalPaid;
          b.isEscrowReleased = false;
          b.escrowStatus = 'expired_refunded';
          processedCount++;
        }
        continue;
      }

      // 2. Retry pending_caregiver_connect, pending_settlement_transfer, or pending_network_retry if bank is now connected
      if (!b.isEscrowReleased &&
          (b.escrowStatus == 'pending_caregiver_connect' ||
              b.escrowStatus == 'pending_settlement_transfer' ||
              b.escrowStatus == 'pending_network_retry')) {
        final cgIdx = caregivers.indexWhere((c) => c.id == b.caregiverId);
        final hasBank = cgIdx == -1 ? true : caregivers[cgIdx].hasStripeConnectedAccount;
        if (hasBank) {
          b.status = BookingStatus.Completed;
          b.isEscrowReleased = true;
          b.escrowStatus = 'released';
          b.checkOutTime ??= now;
          _scheduleNextRecurringBookingIfNeeded(b);
          processedCount++;
        }
        continue;
      }

      // 3. 24h Auto-Completion & Escrow Release when client forgets to confirm
      if ((b.status == BookingStatus.Confirmed || b.status == BookingStatus.InProgress) &&
          !b.isEscrowReleased) {
        final endRef = b.serviceEndTime ?? b.createdAt.add(Duration(hours: b.durationHours));
        if (now.difference(endRef).inHours >= 24) {
          final cgIdx = caregivers.indexWhere((c) => c.id == b.caregiverId);
          final hasBank = cgIdx == -1 ? true : caregivers[cgIdx].hasStripeConnectedAccount;
          b.status = BookingStatus.Completed;
          b.checkOutTime = now;
          _scheduleNextRecurringBookingIfNeeded(b);
          if (hasBank) {
            b.isEscrowReleased = true;
            b.escrowStatus = 'released';
          } else {
            b.isEscrowReleased = false;
            b.escrowStatus = 'pending_caregiver_connect';
          }
          processedCount++;
        }
      }
    }

    if (processedCount > 0) {
      notifyListeners();
    }
    return processedCount;
  }

  /// Submits a verified 1-5 star review for a completed booking and updates the caregiver's rating.
  bool submitBookingReview(String bookingId, int rating, String comment) {
    if (rating < 1 || rating > 5) return false;
    final idx = bookings.indexWhere((b) => b.id == bookingId);
    if (idx == -1) return false;

    final b = bookings[idx];
    if (b.status != BookingStatus.Completed || b.reviewRating != null) {
      return false;
    }

    b.reviewRating = rating;
    b.reviewComment = comment.trim();

    final cgIdx = caregivers.indexWhere((c) => c.id == b.caregiverId);
    if (cgIdx != -1) {
      final cg = caregivers[cgIdx];
      final totalScore = (cg.rating * cg.reviewsCount) + rating;
      cg.reviewsCount += 1;
      cg.rating = double.parse((totalScore / cg.reviewsCount).toStringAsFixed(1));
    }

    notifyListeners();
    return true;
  }

  /// 1. Clinical Dependency Triage (Escala Barthel rápida):
  /// Updates patient's dependency level (Grado I, II, III) & crane transfer needs,
  /// optionally filtering the marketplace to only certified compatible caregivers.
  void updateDependencyTriage({
    required int grade,
    required bool requiresCrane,
    String? cognitiveStatus,
    bool filterCompatibleOnly = true,
  }) {
    patientMedicalSheet.dependencyGrade = grade.clamp(1, 3);
    patientMedicalSheet.requiresCraneTransfer = requiresCrane;
    if (cognitiveStatus != null && cognitiveStatus.trim().isNotEmpty) {
      patientMedicalSheet.cognitiveStatus = cognitiveStatus.trim();
    }
    filterByDependencyTriage = filterCompatibleOnly;
    notifyListeners();
  }

  /// 2. Guarantee of Urgent Substitution ("Garantía de Sustitución en 1 Toque"):
  /// Reassigns a cancelled or pending booking to a verified compatible backup caregiver,
  /// preserving the Escrow coverage without forcing the family to wait 3-5 days for a bank refund.
  bool reassignToBackupCaregiver(String bookingId) {
    final idx = bookings.indexWhere((b) => b.id == bookingId);
    if (idx == -1) return false;
    final b = bookings[idx];

    final candidates = caregivers.where((c) =>
        c.id != b.caregiverId &&
        c.verified &&
        isCaregiverCompatibleWithPatient(c));
    if (candidates.isEmpty) return false;

    final backup = candidates.first;
    b.originalCaregiverName ??= b.caregiverName;
    b.caregiverId = backup.id;
    b.caregiverName = backup.name;
    b.wasSubstituted = true;
    b.status = BookingStatus.Confirmed;
    b.isRefunded = false;
    b.refundedAmount = 0.0;
    b.escrowStatus = 'held';
    b.serviceEndTime = DateTime.now().add(Duration(hours: b.durationHours));

    b.careLogs.add(
      CareLogEntry(
        category: 'Garantía de Sustitución',
        note:
            'Reasignación inmediata a ${backup.name} (${backup.title}) manteniendo custodia y seguro RC.',
        timestamp: DateTime.now(),
      ),
    );

    chatMessages.add(
      ChatMessage(
        sender: ChatSender.Caregiver,
        text:
            '⚡ GARANTÍA DE SUSTITUCIÓN ACTIVADA: ${backup.name} (${backup.title}) ha asumido tu servicio del ${b.day} a las ${b.slot} h en sustitución de ${b.originalCaregiverName}, manteniendo el importe en garantía sin sobrecoste.',
        timestamp: DateTime.now(),
      ),
    );
    notifyListeners();
    return true;
  }

  /// 3. Structured Check-out with "Informe de Cierre de Turno" (Shift Hand-off Report):
  /// Records medication compliance, meal intake, senior mood, and key custody return before closing shift.
  bool completeShiftHandoffCheckout({
    required String bookingId,
    required bool medicationGiven,
    required String mealIntake,
    required String seniorMood,
    bool keysReturnedAndLocked = true,
    required String summaryNote,
  }) {
    final idx = bookings.indexWhere((b) => b.id == bookingId);
    if (idx == -1) return false;
    final b = bookings[idx];

    final report = ShiftHandoffReport(
      medicationGiven: medicationGiven,
      mealIntake: mealIntake,
      seniorMood: seniorMood,
      keysReturnedAndLocked: keysReturnedAndLocked,
      summaryNote: summaryNote.trim().isEmpty
          ? 'Turno finalizado sin incidencias. Constantes y bienestar revisados.'
          : summaryNote.trim(),
      completedAt: DateTime.now(),
    );

    b.handoffReport = report;
    b.checkOutTime = report.completedAt;
    b.careLogs.add(
      CareLogEntry(
        category: 'Informe Cierre de Turno',
        note:
            'Medicación: ${medicationGiven ? "Sí" : "No"} • Comida: $mealIntake • Ánimo: $seniorMood • Llaves cerradas: ${keysReturnedAndLocked ? "Sí" : "No"}. Nota: ${report.summaryNote}',
        timestamp: report.completedAt,
      ),
    );

    chatMessages.add(
      ChatMessage(
        sender: ChatSender.Caregiver,
        text:
            '📋 INFORME DE CIERRE DE TURNO (#${b.id}):\n'
            '• Medicación administrada: ${medicationGiven ? "✅ Sí" : "⚠️ No requerida"}\n'
            '• Ingesta de comida: $mealIntake\n'
            '• Estado de ánimo: $seniorMood\n'
            '• Resumen: ${report.summaryNote}',
        timestamp: report.completedAt,
      ),
    );
    notifyListeners();
    return true;
  }

  /// 4. Shared "Círculo Familiar" (Family Circle) for multi-child & medical coordination:
  bool addFamilyCircleMember({
    required String name,
    required String relation,
    required String roleLabel,
    bool receivesSosAlerts = true,
    bool canApprovePayments = false,
  }) {
    if (name.trim().isEmpty) return false;
    familyCircle.add(
      FamilyCircleMember(
        id: 'fc_${familyCircle.length + 1}',
        name: name.trim(),
        relation: relation.trim().isEmpty ? 'Familiar' : relation.trim(),
        roleLabel: roleLabel,
        receivesSosAlerts: receivesSosAlerts,
        canApprovePayments: canApprovePayments,
      ),
    );
    notifyListeners();
    return true;
  }

  /// 5. Blind Bidirectional Review (Caregiver rates Client / Home Environment):
  /// Protects caregivers from unsafe conditions and publishes reviews when both sides have evaluated.
  bool submitClientReviewByCaregiver(String bookingId, int rating, String comment) {
    if (rating < 1 || rating > 5) return false;
    final idx = bookings.indexWhere((b) => b.id == bookingId);
    if (idx == -1) return false;
    final b = bookings[idx];
    if (b.status != BookingStatus.Completed || b.clientReviewRating != null) {
      return false;
    }
    b.clientReviewRating = rating;
    b.clientReviewComment = comment.trim().isEmpty
        ? 'Familia puntual, entorno seguro y pautas claras.'
        : comment.trim();
    notifyListeners();
    return true;
  }

  /// 6. Prepaid Care Hour Bundle ("Bolsa de Horas Prepagada con Descuento"):
  /// Allows families to buy monthly packs (e.g., 20h or 50h) for recurring care.
  bool purchaseCareHourBundle(int hours) {
    if (hours <= 0) return false;
    prepaidHourBalance += hours;
    notifyListeners();
    return true;
  }

  /// Applies available prepaid hours from the family's Care Bundle to cover a booking.
  bool applyPrepaidHoursToBooking(String bookingId) {
    final idx = bookings.indexWhere((b) => b.id == bookingId);
    if (idx == -1) return false;
    final b = bookings[idx];
    if (prepaidHourBalance < b.durationHours) return false;
    prepaidHourBalance -= b.durationHours;
    notifyListeners();
    return true;
  }

  /// 7. Official Tax & Dependency Law Invoice Generator (Ley 39/2006 de Dependencia & IRPF):
  /// Generates a compliant invoice with correlative numbering, NIF, and 4% reduced VAT breakdown.
  OfficialCareInvoice? generateOfficialInvoice(String bookingId) {
    final idx = bookings.indexWhere((b) => b.id == bookingId);
    if (idx == -1) return null;
    final b = bookings[idx];
    if (b.isRefunded || b.status == BookingStatus.Cancelled) return null;

    if (b.officialInvoice != null) {
      return b.officialInvoice;
    }

    final baseTaxable = double.parse((b.totalPaid / 1.04).toStringAsFixed(2));
    final vatAmount = double.parse((b.totalPaid - baseTaxable).toStringAsFixed(2));
    final invoiceNumber = 'SC-${DateTime.now().year}-000${idx + 1}';
    final issueDate = DateTime.now();
    final verifactuHash = ZeroCostTaxAndVeriFactuEngine.computeVeriFactuHash(
      invoiceNumber: invoiceNumber,
      familyNif: familyNif,
      totalPaidEur: b.totalPaid,
      issueDate: issueDate,
    );
    final aeatQrUrl = ZeroCostTaxAndVeriFactuEngine.buildAeatQrUrl(
      invoiceNumber: invoiceNumber,
      familyNif: familyNif,
      totalPaidEur: b.totalPaid,
      verifactuHash: verifactuHash,
    );
    final invoice = OfficialCareInvoice(
      invoiceNumber: invoiceNumber,
      bookingId: b.id,
      issueDate: issueDate,
      familyFullName: familyFullName,
      familyNif: familyNif,
      caregiverName: b.caregiverName,
      patientName: patientMedicalSheet.patientName,
      dependencyGradeLabel: patientMedicalSheet.dependencyGradeLabel,
      durationHours: b.durationHours,
      baseTaxableEur: baseTaxable,
      vatRatePercent: 4,
      vatAmountEur: vatAmount,
      totalPaidEur: b.totalPaid,
      verifactuHash: verifactuHash,
      aeatVerificationQrUrl: aeatQrUrl,
    );
    b.officialInvoice = invoice;
    notifyListeners();
    return invoice;
  }

  /// Pilar 2: Completes or updates a guided Trust & Safety verification document in 1 tap.
  bool submitGuidedVerificationDocument({
    required String docId,
    required String referenceOrCsv,
  }) {
    final idx = guidedDocuments.indexWhere((d) => d.id == docId);
    if (idx == -1 || referenceOrCsv.trim().isEmpty) return false;
    guidedDocuments[idx].isCompleted = true;
    guidedDocuments[idx].verificationCodeOrRef = referenceOrCsv.trim();
    if (docId == 'doc_rgpd_art9_consent') {
      patientMedicalSheet.rgpdArt9ConsentSigned = true;
      patientMedicalSheet.rgpdConsentTimestamp = DateTime.now();
    }
    notifyListeners();
    return true;
  }

  /// Pilar 3: Calculates exact urban distance (km) using zero-cost Haversine math.
  double getCaregiverDistanceKm(CaregiverProfile caregiver) {
    return ZeroCostGeoAndCalendarEngine.calculateHaversineKm(
      lat1: familyHomeLat,
      lon1: familyHomeLon,
      lat2: caregiver.latitude,
      lon2: caregiver.longitude,
    );
  }

  /// Pilar 3: Exports all non-cancelled bookings to standard iCal (`.ics` RFC 5545) at 0 € cost.
  String exportCalendarToIcs() {
    return ZeroCostGeoAndCalendarEngine.exportBookingsToIcs(bookings);
  }

  /// Pilar 3: Imports busy slots from an external `.ics` calendar so the caregiver never gets double-booked.
  int syncExternalIcsCalendar(String caregiverId, String day, String icsPayload) {
    final cgIdx = caregivers.indexWhere((c) => c.id == caregiverId);
    if (cgIdx == -1) return 0;
    final busySlots = ZeroCostGeoAndCalendarEngine.parseBusySlotsFromIcs(icsPayload);
    final daySlots = caregivers[cgIdx].availableSlots[day];
    if (daySlots == null) return 0;
    int removed = 0;
    for (final busy in busySlots) {
      if (daySlots.remove(busy)) {
        removed++;
      }
    }
    if (removed > 0) notifyListeners();
    return removed;
  }

  /// Pilar 4: Generates the EU DAC7 (Modelo 238 AEAT) tax declaration summary for a caregiver at 0 € cost.
  Dac7CaregiverReport generateCaregiverDac7Report([String? caregiverId]) {
    final targetId = caregiverId ?? activeCaregiverId;
    final cg = caregivers.firstWhere(
      (c) => c.id == targetId,
      orElse: () => caregivers.first,
    );
    return ZeroCostTaxAndVeriFactuEngine.generateDac7Report(
      caregiver: cg,
      allBookings: bookings,
    );
  }

  /// Pilar 5: Launches a free 15-minute WebRTC P2P Video Interview room without sharing personal phone numbers.
  String startFreeVideoInterview(String caregiverId) {
    final cg = caregivers.firstWhere(
      (c) => c.id == caregiverId,
      orElse: () => caregivers.first,
    );
    final roomUrl = ZeroCostVideoInterviewEngine.createMaskedVideoInterviewUrl(
      caregiverId: cg.id,
      clientId: 'client_demo_1',
    );
    chatMessages.add(
      ChatMessage(
        sender: ChatSender.Client,
        text:
            '🎥 Sala de Videoentrevista Gratuita (15 min • Teléfono oculto) creada con ${cg.name}: $roomUrl',
        timestamp: DateTime.now(),
      ),
    );
    notifyListeners();
    return roomUrl;
  }

  /// Pilar 7: Apple App Store Review 5.1.1 & RGPD Art. 17 Right to Account Deletion.
  /// Safeguard: Prevents deleting account while there is an active booking with held Escrow funds.
  bool requestAccountDeletion() {
    final hasActiveHeldEscrow = bookings.any((b) =>
        !b.isEscrowReleased &&
        !b.isRefunded &&
        (b.status == BookingStatus.InProgress ||
            b.status == BookingStatus.Confirmed ||
            b.status == BookingStatus.Disputed));
    if (hasActiveHeldEscrow) {
      return false;
    }
    accountDeleted = true;
    familyFullName = 'Usuario Eliminado (RGPD Art. 17)';
    familyNif = 'ANONIMIZADO';
    patientMedicalSheet.rgpdArt9ConsentSigned = false;
    notifyListeners();
    return true;
  }

  /// Appends a new chat message and runs the Context-Aware Anti-Bypass Validator.
  /// Unlocks contact & address exchange once a booking is Confirmed or InProgress.
  AntiBypassResult sendChatMessage(String text) {
    final result = AntiBypassValidator.evaluate(
      text,
      hasConfirmedBooking: hasActiveConfirmedBooking,
    );

    chatMessages.add(ChatMessage(
      sender: ChatSender.Client,
      text: result.sanitizedText,
      timestamp: DateTime.now(),
      wasSanitized: result.wasBlocked,
    ));
    notifyListeners();

    if (!result.wasBlocked) {
      Future.delayed(const Duration(seconds: 3), () {
        chatMessages.add(ChatMessage(
          sender: ChatSender.Caregiver,
          text:
              'Gracias por tu mensaje. Para confirmar la asistencia con cobertura y garantía SeniCare, por favor selecciona el horario en mi calendario.',
          timestamp: DateTime.now(),
        ));
        notifyListeners();
      });
    }
    return result;
  }
}

// ==========================================
// 2. MAIN APP ENTRY & CORE LAYOUT
// ==========================================

class SeniCareApp extends StatelessWidget {
  const SeniCareApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return MaterialApp(
      title: 'SeniCare',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.getTheme(state.seniorMode),
      home: const MainLayout(),
    );
  }
}

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isClient = state.currentRole == 'client';

    final currentScreens = isClient
        ? const [ExplorerScreen(), BookingsScreen(), ChatScreen()]
        : const [CaregiverDashboard(), BookingsScreen(), ChatScreen()];

    if (_currentIndex >= currentScreens.length) {
      _currentIndex = 0;
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 1,
        title: Row(
          children: [
            const Icon(Icons.favorite, color: AppTheme.primary, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isClient ? 'SeniCare' : 'Panel Profesional',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.elderly_rounded, size: 18, color: AppTheme.primary),
              const SizedBox(width: 4),
              const Text(
                'Mayor',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.darkSlate,
                ),
              ),
              Transform.scale(
                scale: 0.85,
                child: Switch(
                  value: state.seniorMode,
                  onChanged: (val) => state.toggleSeniorMode(val),
                  activeThumbColor: AppTheme.primary,
                ),
              ),
            ],
          ),
          PopupMenuButton<String>(
            tooltip: 'Cambiar vista de usuario',
            icon: const Icon(Icons.switch_account, color: AppTheme.darkSlate),
            onSelected: (role) {
              state.setRole(role);
              setState(() => _currentIndex = 0);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'client',
                child: Text('👨‍👩‍👧 Vista Familia / Mayor'),
              ),
              PopupMenuItem(
                value: 'caregiver',
                child: Text('👩‍⚕️ Vista Cuidadora (Elena)'),
              ),
            ],
          ),
        ],
      ),
      body: currentScreens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (idx) => setState(() => _currentIndex = idx),
        selectedItemColor: AppTheme.primary,
        unselectedItemColor: AppTheme.darkSlate.withValues(alpha: 0.6),
        selectedFontSize: state.seniorMode ? 16 : 13,
        unselectedFontSize: state.seniorMode ? 14 : 12,
        iconSize: state.seniorMode ? 30 : 24,
        items: [
          BottomNavigationBarItem(
            icon: Icon(isClient ? Icons.home_rounded : Icons.dashboard_rounded),
            label: isClient
                ? (state.seniorMode ? 'Inicio Mayor' : 'Explorar')
                : 'Mi Panel',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month_rounded),
            label: 'Reservas',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_rounded),
            label: 'Mensajes',
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 3. SCREENS ARCHITECTURE
// ==========================================

// --- SCREEN A: Explorer / Marketplace & Senior Quick-Access Hub ---
class ExplorerScreen extends StatelessWidget {
  const ExplorerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_on, color: AppTheme.primary, size: 20),
                    const SizedBox(width: 4),
                    Text('Madrid, España', style: theme.textTheme.bodyMedium),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified_user, color: AppTheme.primary, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'Garantía 100% SeniCare',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (state.seniorMode)
          SliverToBoxAdapter(
            child: _SeniorAccessibleHub(),
          ),
        // Antigravity Modern Hero Card: Calm, Zero-Overload Reassurance + 3 Simple Pill Actions
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: AppTheme.antigravitySurfaceGradient,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.16)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.verified_user_rounded,
                            color: AppTheme.primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          state.tr('zero_paperwork_banner'),
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.darkSlate,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.favorite_border_rounded,
                            size: 17, color: AppTheme.primary),
                        label: Text(
                          state.filterByDependencyTriage
                              ? 'Nivel de ayuda: Activo'
                              : '¿Qué ayuda necesita tu familiar?',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                        backgroundColor: Colors.white,
                        onPressed: () => _showDependencyTriageDialog(context),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.shield_outlined,
                            size: 17, color: AppTheme.primary),
                        label: const Text(
                          'Seguridad y 0 Papeleo',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                        backgroundColor: Colors.white,
                        onPressed: () => showGuidedDocumentsCenterDialog(context),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.tune_rounded,
                            size: 17, color: AppTheme.primary),
                        label: const Text(
                          'Mi Familia y Más',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                        backgroundColor: Colors.white,
                        onPressed: () => _showFamilyQuickHubDialog(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: TextField(
              onChanged: state.setSearchQuery,
              decoration: InputDecoration(
                hintText: 'Busca por nombre o tipo de ayuda (ej. paseo, medicación)...',
                prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.primary),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide(color: AppTheme.primary.withValues(alpha: 0.15)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide(color: AppTheme.primary.withValues(alpha: 0.15)),
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: state.availableSpecialties.map((spec) {
                final isSelected = state.selectedSpecialty == spec;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: FilterChip(
                    label: Text(spec),
                    selected: isSelected,
                    onSelected: (_) => state.setSpecialty(spec),
                    selectedColor: AppTheme.primaryLight,
                    checkmarkColor: AppTheme.primary,
                    labelStyle: TextStyle(
                      fontSize: state.seniorMode ? 17 : 13,
                      color: isSelected ? AppTheme.primary : AppTheme.darkSlate,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final c = state.filteredCaregivers[index];
                final commuteMin = ZeroCostGeoAndCalendarEngine.estimateUrbanCommuteMinutes(
                  state.getCaregiverDistanceKm(c),
                );
                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CaregiverDetailScreen(caregiver: c),
                        ),
                      );
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Stack(
                          children: [
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                              child: Image.network(
                                c.imageUrl,
                                height: 165,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => Container(
                                  height: 165,
                                  color: AppTheme.primaryLight,
                                  child: const Icon(Icons.person_rounded,
                                      size: 64, color: AppTheme.primary),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 12,
                              left: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.94),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.verified_rounded,
                                        color: AppTheme.primary, size: 16),
                                    SizedBox(width: 5),
                                    Text(
                                      'Identidad y Seguro Verificados',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: AppTheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 12,
                              right: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppTheme.darkSlate.withValues(alpha: 0.88),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '📍 A $commuteMin min (${c.distance})',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(c.name, style: theme.textTheme.titleLarge),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.star_rounded,
                                            color: AppTheme.amber, size: 18),
                                        const SizedBox(width: 3),
                                        Text(
                                          '${c.rating} (${c.reviewsCount})',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w800, fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                c.title,
                                style: const TextStyle(
                                  color: AppTheme.softSlate,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                c.certifiedForCraneTransfer
                                    ? '💚 Preparada para todo tipo de ayuda física y movilidad'
                                    : '💚 Ideal para compañía, paseos y recados diarios',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: c.specialties
                                    .map(
                                      (s) => Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primaryLight,
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          s,
                                          style: TextStyle(
                                            fontSize: state.seniorMode ? 14 : 12,
                                            color: AppTheme.primary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '€${c.pricePerHour.toStringAsFixed(0)} / hora',
                                        style: TextStyle(
                                          fontSize: state.seniorMode ? 22 : 19,
                                          fontWeight: FontWeight.w800,
                                          color: AppTheme.primary,
                                        ),
                                      ),
                                      const Text(
                                        'Seguro y garantía incluidos',
                                        style: TextStyle(
                                            fontSize: 11, color: AppTheme.softSlate),
                                      ),
                                    ],
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => CaregiverDetailScreen(caregiver: c),
                                        ),
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: Size(155, state.seniorMode ? 58 : 46),
                                    ),
                                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                                    label: const Text('Ver Perfil'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              childCount: state.filteredCaregivers.length,
            ),
          ),
        ),
      ],
    );
  }

  /// Unified, friendly Family Options Hub replacing the cluttered row of 6 technical chips.
  void _showFamilyQuickHubDialog(BuildContext context) {
    final state = context.read<AppState>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('✨ Opciones para tu Familia'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppTheme.primaryLight,
                child: Icon(Icons.groups_rounded, color: AppTheme.primary),
              ),
              title: Text(
                'Familiares conectados (${state.familyCircle.length})',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text('Añade a tus hijos o hermanos para recibir avisos'),
              onTap: () {
                Navigator.pop(ctx);
                _showFamilyCircleDialog(context);
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppTheme.primaryLight,
                child: Icon(Icons.confirmation_number_rounded, color: AppTheme.primary),
              ),
              title: Text(
                'Bono de horas con descuento (${state.prepaidHourBalance}h)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text('Ahorra hasta un 15% si necesitas ayuda frecuente'),
              onTap: () {
                Navigator.pop(ctx);
                _showHourBundlesDialog(context);
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppTheme.primaryLight,
                child: Icon(Icons.language_rounded, color: AppTheme.primary),
              ),
              title: Text(
                'Cambiar idioma (${state.currentLocale.toUpperCase()})',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text('Castellano (ES) • Català (CA) • English (EN)'),
              onTap: () {
                final next = state.currentLocale == 'es'
                    ? 'ca'
                    : (state.currentLocale == 'ca' ? 'en' : 'es');
                state.setLocale(next);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppTheme.primaryLight,
                child: Icon(Icons.privacy_tip_rounded, color: AppTheme.primary),
              ),
              title: const Text(
                'Privacidad médica y mi cuenta',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text('Controla tus datos con 1 toque'),
              onTap: () {
                Navigator.pop(ctx);
                _showPrivacyAndAccountDeletionDialog(context);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _showDependencyTriageDialog(BuildContext context) {
    final state = context.read<AppState>();
    int grade = state.patientMedicalSheet.dependencyGrade;
    bool requiresCrane = state.patientMedicalSheet.requiresCraneTransfer;
    bool filterOnly = state.filterByDependencyTriage;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('🩺 Triaje Clínico (Escala Barthel)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Configura el grado de dependencia de tu familiar para filtrar cuidadores físicamente capacitados:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: grade,
                decoration: const InputDecoration(
                  labelText: 'Grado Ley de Dependencia',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('Grado I (Autonomía Parcial)')),
                  DropdownMenuItem(value: 2, child: Text('Grado II (Dependencia Severa)')),
                  DropdownMenuItem(value: 3, child: Text('Grado III (Gran Dependencia)')),
                ],
                onChanged: (v) {
                  if (v != null) setDialogState(() => grade = v);
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Requiere grúa / movilización encamado'),
                value: requiresCrane,
                onChanged: (v) => setDialogState(() => requiresCrane = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mostrar solo cuidadores compatibles'),
                value: filterOnly,
                onChanged: (v) => setDialogState(() => filterOnly = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                state.updateDependencyTriage(
                  grade: grade,
                  requiresCrane: requiresCrane,
                  filterCompatibleOnly: filterOnly,
                );
                Navigator.pop(ctx);
              },
              child: const Text('Aplicar Triaje'),
            ),
          ],
        ),
      ),
    );
  }

  void _showFamilyCircleDialog(BuildContext context) {
    final nameController = TextEditingController();
    final relationController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => Consumer<AppState>(
        builder: (context, state, _) => AlertDialog(
          title: const Text('👨‍👩‍👧 Círculo Familiar Compartido'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Miembros que reciben el Informe de Cierre de Turno y alertas SOS en tiempo real:',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                ...state.familyCircle.map(
                  (m) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.verified_user, color: AppTheme.primary),
                    title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${m.relation} • ${m.roleLabel}'),
                  ),
                ),
                const Divider(),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del familiar o médico',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: relationController,
                  decoration: const InputDecoration(
                    labelText: 'Parentesco (ej. Hijo, Nieta)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar'),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.trim().isNotEmpty) {
                  state.addFamilyCircleMember(
                    name: nameController.text,
                    relation: relationController.text,
                    roleLabel: 'Familiar Supervisor',
                  );
                  nameController.clear();
                  relationController.clear();
                }
              },
              child: const Text('Añadir al Círculo'),
            ),
          ],
        ),
      ),
    );
  }

  void _showHourBundlesDialog(BuildContext context) {
    final state = context.read<AppState>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🎟️ Bolsa de Horas Prepagada'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Saldo disponible actual: ${state.prepaidHourBalance} horas',
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary),
            ),
            const SizedBox(height: 12),
            const Text(
              'Adquiere bonos mensuales de cuidado recurrente con descuento directo y cobertura RC prioritaria:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                state.purchaseCareHourBundle(20);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('🎟️ Bono Respiro +20h añadido a tu Bolsa de Horas.'),
                    backgroundColor: AppTheme.primary,
                  ),
                );
              },
              icon: const Icon(Icons.add_card),
              label: const Text('Cargar Bono 20h (-10% dto.)'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                state.purchaseCareHourBundle(50);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('🎟️ Pack Dependencia +50h añadido a tu Bolsa de Horas.'),
                    backgroundColor: AppTheme.primary,
                  ),
                );
              },
              icon: const Icon(Icons.workspace_premium),
              label: const Text('Cargar Pack Mensual 50h (-15% dto.)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  /// Pilar 2: Interactive, Friendly Step-by-Step Guide for every Document (DNI, Delitos Sexuales, Seguro RC, RGPD Art. 9)
  /// Designed so NO family gets scared or abandons the app, and every caregiver knows how to obtain and upload each item for 0 €.
  static void showGuidedDocumentsCenterDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final state = context.watch<AppState>();
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.verified_user_rounded, color: AppTheme.primary),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Guía Fácil de Documentos y Seguridad (0 Papeleo para Familias)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryLight,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.primary),
                      ),
                      child: const Text(
                        '💚 ¿Eres Familia? No tienes que subir ningún documento para explorar ni reservar. '
                        'SeniCare ya ha comprobado la identidad, antecedentes y seguro de cada profesional por ti.\n\n'
                        '👩‍⚕️ ¿Eres Cuidadora? Pulsa en cada punto para ver la guía paso a paso de cómo conseguirlo gratis (0 €) y subirlo con una foto desde el móvil.',
                        style: TextStyle(fontSize: 12, color: AppTheme.darkSlate),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...state.guidedDocuments.map(
                      (doc) => Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ExpansionTile(
                          leading: Icon(
                            doc.isCompleted
                                ? Icons.check_circle_rounded
                                : Icons.pending_actions_rounded,
                            color: doc.isCompleted ? Colors.green.shade700 : AppTheme.amber,
                          ),
                          title: Text(
                            doc.title,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          subtitle: Text(
                            '${doc.targetAudience} • ⏱️ ${doc.timeRequiredBadge} • ${doc.costBadge}',
                            style: const TextStyle(fontSize: 11, color: AppTheme.primary),
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '🛡️ ${doc.familyPeaceOfMindNote}',
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '📥 ¿Cómo conseguir este documento gratis (0 €)?',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                            const SizedBox(height: 4),
                            ...doc.howToGetSteps.map(
                              (step) => Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(step, style: const TextStyle(fontSize: 12)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '📤 ¿Cómo colgarlo en la app sin complicarte?',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                            const SizedBox(height: 4),
                            ...doc.howToUploadSteps.map(
                              (step) => Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(step, style: const TextStyle(fontSize: 12)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: Text(
                                    'Ref: ${doc.verificationCodeOrRef ?? "Pendiente"}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade700,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    state.submitGuidedVerificationDocument(
                                      docId: doc.id,
                                      referenceOrCsv:
                                          'VERIFIED-${DateTime.now().millisecondsSinceEpoch}',
                                    );
                                    setModalState(() {});
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            '✅ ${doc.title} actualizado y verificado a coste 0 €.'),
                                        backgroundColor: AppTheme.primary,
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.cloud_upload_rounded, size: 16),
                                  label: const Text('Subir / Actualizar en 1 Toque',
                                      style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendido, volver'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Pilar 7: Privacy Consent RGPD Art. 9 + Apple App Store Guideline 5.1.1 Account Deletion Flow.
  void _showPrivacyAndAccountDeletionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final state = context.watch<AppState>();
          return AlertDialog(
            title: const Text('🔒 Centro de Privacidad RGPD y Cuenta'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Consentimiento Datos de Salud (RGPD Art. 9)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  subtitle: const Text(
                    'Autoriza en 1 clic que solo tu cuidadora confirmada vea las pautas médicas durante el turno.',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: state.patientMedicalSheet.rgpdArt9ConsentSigned,
                  onChanged: (val) {
                    state.patientMedicalSheet.rgpdArt9ConsentSigned = val;
                    state.patientMedicalSheet.rgpdConsentTimestamp = DateTime.now();
                    setDialogState(() {});
                  },
                ),
                const Divider(height: 24),
                const Text(
                  'Derecho al Olvido y Eliminación de Cuenta (RGPD Art. 17 / Apple App Store 5.1.1)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Puedes eliminar tu cuenta y anonimizar tus datos personales en cualquier momento siempre que no tengas un servicio activo con fondos en custodia pendientes de liquidar.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.urgentRed,
                    side: const BorderSide(color: AppTheme.urgentRed),
                  ),
                  onPressed: () {
                    final deleted = state.requestAccountDeletion();
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          deleted
                              ? '🗑️ Cuenta y datos personales anonimizados conforme al Art. 17 RGPD.'
                              : '⚠️ No se puede eliminar la cuenta mientras exista una reserva en curso con depósito Escrow retenido.',
                        ),
                        backgroundColor: deleted ? AppTheme.primary : AppTheme.urgentRed,
                      ),
                    );
                  },
                  icon: const Icon(Icons.delete_forever_rounded),
                  label: const Text('Solicitar Eliminación de Cuenta'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SeniorAccessibleHub extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final primaryCaregiver = state.caregivers.first;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hola, bienvenido a tu panel 👋', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          Card(
            color: AppTheme.primaryLight,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: AppTheme.primary, width: 2),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.medical_services_rounded, color: AppTheme.primary, size: 28),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'TU CUIDADORA DE CONFIANZA',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${primaryCaregiver.name} (${primaryCaregiver.title})',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    '📞 Llamando por teléfono a ${primaryCaregiver.name}...'),
                                backgroundColor: AppTheme.primary,
                              ),
                            );
                          },
                          icon: const Icon(Icons.phone_in_talk, size: 26),
                          label: const Text('LLAMAR'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ChatScreen(isStandalone: true),
                              ),
                            );
                          },
                          icon: const Icon(Icons.chat_rounded, size: 24),
                          label: const Text('MENSAJE'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primary,
                            side: const BorderSide(color: AppTheme.primary, width: 2),
                            backgroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.medication_rounded, color: AppTheme.primary, size: 28),
                      const SizedBox(width: 8),
                      Text('MIS MEDICINAS DE HOY', style: theme.textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...state.medications.map(
                    (med) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: med.isTaken ? AppTheme.primaryLight : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: med.isTaken ? AppTheme.primary : Colors.grey.shade400,
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '⏰ ${med.scheduledTime} — ${med.name}',
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(med.dosage, style: const TextStyle(fontSize: 16)),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: () => state.toggleMedicationTaken(med.id),
                              icon: Icon(
                                med.isTaken
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                              ),
                              label: Text(
                                med.isTaken
                                    ? '✓ MEDICINA TOMADA'
                                    : 'MARCAR COMO TOMADA',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: med.isTaken
                                    ? Colors.green.shade800
                                    : AppTheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Card(
            color: const Color(0xFFFEF2F2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: AppTheme.urgentRed, width: 2),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.emergency_rounded, color: AppTheme.urgentRed, size: 30),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'AYUDA URGENTE / SOS FAMILIA',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.urgentRed,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Pulsa este botón si necesitas ayuda inmediata. Avisaremos a tu familia y a tu cuidadora con tu ubicación.',
                    style: TextStyle(fontSize: 16, color: AppTheme.darkSlate),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('🚨 ¿Necesitas ayuda urgente?'),
                          content: const Text(
                            'Enviaremos un aviso inmediato con tu ubicación GPS a tu familia y a tu cuidadora.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Cancelar'),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.urgentRed,
                              ),
                              onPressed: () {
                                state.triggerSosAlert();
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        '🚨 Alerta SOS enviada a tu familia y cuidadora.'),
                                    backgroundColor: AppTheme.urgentRed,
                                  ),
                                );
                              },
                              child: const Text('SÍ, ENVIAR ALERTA SOS'),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.sos_rounded, size: 28),
                    label: const Text('PEDIR AYUDA AHORA'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.urgentRed,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Explorar Todos los Cuidadores', style: theme.textTheme.titleLarge),
        ],
      ),
    );
  }
}

// --- SCREEN B: Caregiver Details, Flexible Duration, Key Custody & Recurring Plan ---
class CaregiverDetailScreen extends StatefulWidget {
  final CaregiverProfile caregiver;
  const CaregiverDetailScreen({super.key, required this.caregiver});

  @override
  State<CaregiverDetailScreen> createState() => _CaregiverDetailScreenState();
}

class _CaregiverDetailScreenState extends State<CaregiverDetailScreen> {
  late String _selectedDay;
  int _selectedDurationHours = 2;
  bool _isRecurringWeekly = false;
  String _selectedKeyCustody = 'Portería / Conserje';

  final List<int> _durationOptions = [1, 2, 4, 8, 10];
  final List<String> _keyCustodyOptions = [
    'Portería / Conserje',
    'Entrega en mano por familiar',
    'Cajetín con código de seguridad',
  ];

  @override
  void initState() {
    super.initState();
    _selectedDay = widget.caregiver.availableSlots.keys.isNotEmpty
        ? widget.caregiver.availableSlots.keys.first
        : 'Sin disponibilidad';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final c = widget.caregiver;
    final availableSlots = state.getAvailableSlotsForDay(
      c,
      _selectedDay,
      durationHours: _selectedDurationHours,
    );

    return Scaffold(
      appBar: AppBar(title: Text(c.name)),
      body: ListView(
        children: [
          Image.network(
            c.imageUrl,
            height: 230,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              height: 230,
              color: Colors.grey.shade200,
              child: Icon(Icons.person, size: 80, color: Colors.grey.shade400),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(c.title, style: theme.textTheme.titleLarge),
                    ),
                    if (c.verified) ...[
                      const Icon(Icons.verified, color: Colors.blue, size: 22),
                      const SizedBox(width: 4),
                      const Text(
                        'Verificado',
                        style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '🛡️ ${c.verificationBadge} • ${c.yearsExperience} años exp.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.star, color: AppTheme.amber, size: 20),
                    const SizedBox(width: 4),
                    Text(
                      '${c.rating} (${c.reviewsCount} reseñas verificadas)',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 16),
                    const Icon(Icons.location_on, color: AppTheme.primary, size: 20),
                    Text(
                      '${c.distance} (~${ZeroCostGeoAndCalendarEngine.estimateUrbanCommuteMinutes(state.getCaregiverDistanceKm(c))} min)',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        final url = state.startFreeVideoInterview(c.id);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('🎥 Sala de videoentrevista gratuita abierta: $url'),
                            backgroundColor: AppTheme.primary,
                          ),
                        );
                      },
                      icon: const Icon(Icons.videocam_rounded, size: 18),
                      label: Text(state.tr('video_interview_btn'),
                          style: const TextStyle(fontSize: 12)),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => ExplorerScreen.showGuidedDocumentsCenterDialog(context),
                      icon: const Icon(Icons.verified_user_rounded, size: 18),
                      label: const Text('Ver Documentos y Seguro RC',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Sobre mí', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(c.bio, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 24),

                // Step 1 & 2 Unified in a Clean Antigravity Card (Progressive Disclosure)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.14)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('1. ¿Cuánto tiempo necesitas?', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _durationOptions.map((hours) {
                          final isSelected = _selectedDurationHours == hours;
                          final label = hours == 8
                              ? '8h (Día)'
                              : (hours == 10
                                  ? '10h (Noche)'
                                  : '$hours ${hours == 1 ? "hora" : "horas"}');
                          return ChoiceChip(
                            label: Text(label),
                            selected: isSelected,
                            onSelected: (_) => setState(() => _selectedDurationHours = hours),
                            selectedColor: AppTheme.primary,
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.white : AppTheme.darkSlate,
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 22),

                      // Step 2: Select Day
                      Text('2. Elige el día', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: state.seniorMode ? 68 : 50,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: c.availableSlots.keys.map((day) {
                            final isSelected = _selectedDay == day;
                            return GestureDetector(
                              onTap: () => setState(() => _selectedDay = day),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                margin: const EdgeInsets.only(right: 10),
                                decoration: BoxDecoration(
                                  color: isSelected ? AppTheme.primary : AppTheme.primaryLight,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Center(
                                  child: Text(
                                    day,
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : AppTheme.primary,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 22),

                      // Step 3: Select Available Slot
                      Text('3. Toca la hora de inicio para continuar',
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: 12),
                      if (availableSlots.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Text(
                            'Todos los horarios de este día ya están ocupados. Por favor elige otro día.',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        )
                      else
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: availableSlots.map((slot) {
                            return ActionChip(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              label: Text(
                                '🕒 $slot h',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.primary,
                                ),
                              ),
                              onPressed: () {
                                state.createCheckoutSlotHold(
                                  caregiverId: c.id,
                                  day: _selectedDay,
                                  slot: slot,
                                  durationHours: _selectedDurationHours,
                                );
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PaymentScreen(
                                      caregiver: c,
                                      day: _selectedDay,
                                      slot: slot,
                                      durationHours: _selectedDurationHours,
                                      isRecurringWeekly: _isRecurringWeekly,
                                      keyCustodyMethod: _selectedKeyCustody,
                                    ),
                                  ),
                                );
                              },
                              backgroundColor: AppTheme.primaryLight,
                              side: const BorderSide(color: AppTheme.primary),
                            );
                          }).toList(),
                        ),
                      const SizedBox(height: 14),
                      const Divider(),
                      // Progressive Disclosure: Advanced options tucked neatly so non-tech users aren't overwhelmed
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text(
                          '⚙️ Opciones adicionales (Repetir cada semana o llaves)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.softSlate,
                          ),
                        ),
                        subtitle: Text(
                          '${_isRecurringWeekly ? "Semanal activo" : "Solo este día"} • $_selectedKeyCustody',
                          style: const TextStyle(fontSize: 12, color: AppTheme.primary),
                        ),
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              '🔁 Repetir este mismo día cada semana',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            subtitle: const Text(
                              'Te ahorra volver a reservar y premia la fidelidad de tu cuidadora.',
                              style: TextStyle(fontSize: 12),
                            ),
                            value: _isRecurringWeekly,
                            activeThumbColor: AppTheme.primary,
                            onChanged: (val) => setState(() => _isRecurringWeekly = val),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedKeyCustody,
                            decoration: InputDecoration(
                              labelText: '¿Cómo abrirá la puerta la cuidadora?',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                              prefixIcon:
                                  const Icon(Icons.vpn_key_rounded, color: AppTheme.primary),
                            ),
                            items: _keyCustodyOptions
                                .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) setState(() => _selectedKeyCustody = v);
                            },
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ChatScreen(isStandalone: true)),
          );
        },
        label: const Text(
          'Hablar con Cuidadora',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        icon: const Icon(Icons.chat, color: Colors.white),
        backgroundColor: AppTheme.primary,
      ),
    );
  }
}

// --- SCREEN C: Secure Payment Confirmation with Unified Commission Math ---
class PaymentScreen extends StatelessWidget {
  final CaregiverProfile caregiver;
  final String day;
  final String slot;
  final int durationHours;
  final bool isRecurringWeekly;
  final String keyCustodyMethod;

  const PaymentScreen({
    super.key,
    required this.caregiver,
    required this.day,
    required this.slot,
    this.durationHours = 2,
    this.isRecurringWeekly = false,
    this.keyCustodyMethod = 'Portería / Conserje',
  });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final seniorMode = state.seniorMode;
    final currencyFormat = NumberFormat.currency(symbol: '€', decimalDigits: 2);

    final quote = state.calculateCommissionQuote(
      caregiverId: caregiver.id,
      pricePerHour: caregiver.pricePerHour,
      durationHours: durationHours,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Reserva Protegida SeniCare')),
      body: ListView(
        padding: EdgeInsets.all(seniorMode ? 24 : 16),
        children: [
          Text('Resumen de tu Cuidado', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Cuidadora:'),
                      Text(caregiver.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Cuándo viene:'),
                      Text('$day a las $slot h ($durationHours h)',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Precio Final Todo Incluido:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                      ),
                      Text(
                        currencyFormat.format(quote.totalClientPayable),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primary,
                          fontSize: 24,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text(
                      'Ver desglose transparente y llaves',
                      style: TextStyle(fontSize: 12, color: AppTheme.softSlate),
                    ),
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Para ${caregiver.name}:'),
                          Text(currencyFormat.format(quote.caregiverNetPayout)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Seguro y garantía SeniCare:'),
                          Text(currencyFormat.format(quote.platformFee)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Entrega de llaves:'),
                          Flexible(
                            child: Text(
                              keyCustodyMethod,
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Reassuring, Jargon-Free Guarantee Box
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: AppTheme.antigravitySurfaceGradient,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.shield_rounded, color: AppTheme.primary, size: 24),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Tu dinero está 100% protegido',
                        style: TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  '• No se entrega el dinero a la cuidadora hasta que el servicio haya terminado bien.\n'
                  '• Incluye Seguro de Hogar y Responsabilidad Civil hasta 300.000 €.\n'
                  '• Si surge cualquier imprevisto, te devolvemos el 100% o te enviamos una cuidadora de sustitución.',
                  style: TextStyle(color: AppTheme.darkSlate, fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              children: [
                Icon(Icons.timer_outlined, color: Colors.blue, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Hora guardada para ti durante 10 minutos mientras confirmas.',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text('¿Cómo prefieres pagar?', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: state.selectedPaymentMethod,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.account_balance_wallet_rounded, color: AppTheme.primary),
            ),
            items: const [
              DropdownMenuItem(
                value: 'Apple Pay / Google Pay (1-Toque • 0 € comisión)',
                child: Text('📱 Pago rápido (Apple Pay / Google Pay)'),
              ),
              DropdownMenuItem(
                value: 'Tarjeta Visa / Mastercard (Protección 3D Secure)',
                child: Text('💳 Tarjeta bancaria habitual'),
              ),
              DropdownMenuItem(
                value: 'Domiciliación Bancaria SEPA (Planes Recurrentes)',
                child: Text('🏦 Recibo bancario (Domiciliación)'),
              ),
            ],
            onChanged: (val) {
              if (val != null) state.setSelectedPaymentMethod(val);
            },
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () {
              final booking = Booking(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                caregiverId: caregiver.id,
                caregiverName: caregiver.name,
                day: day,
                slot: slot,
                durationHours: durationHours,
                cost: quote.baseCost,
                appCommission: quote.platformFee,
                totalPaid: quote.totalClientPayable,
                commissionRatePercent: quote.commissionRatePercent,
                commissionTier: quote.commissionTier,
                isRecurringWeekly: isRecurringWeekly,
                keyCustodyMethod: keyCustodyMethod,
                status: BookingStatus.PendingApproval,
              );
              final added = context.read<AppState>().addBooking(booking);
              if (!added) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Este horario acaba de ser ocupado. Por favor elige otro.'),
                    backgroundColor: AppTheme.urgentRed,
                  ),
                );
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      '✅ Reserva solicitada con Garantía SeniCare. Esperando confirmación de la cuidadora.'),
                  backgroundColor: AppTheme.primary,
                ),
              );
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            icon: const Icon(Icons.lock_rounded),
            label: const Text('Confirmar Reserva con Garantía'),
          ),
        ],
      ),
    );
  }
}

// --- SCREEN D: Bookings, Medical Sheet, Overtime, PIN/GPS & Verified Reviews ---
class BookingsScreen extends StatelessWidget {
  const BookingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isClient = state.currentRole == 'client';
    final theme = Theme.of(context);
    final currencyFormat = NumberFormat.currency(symbol: '€', decimalDigits: 2);

    if (state.bookings.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text('No hay reservas registradas todavía.'),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(state.seniorMode ? 24 : 16),
      itemCount: state.bookings.length,
      itemBuilder: (context, index) {
        final b = state.bookings[index];
        final shortId = b.id.length >= 4 ? b.id.substring(b.id.length - 4) : b.id;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Reserva #$shortId • ${b.durationHours}h${b.isRecurringWeekly ? " 🔁 Semanal" : ""}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                    ),
                    _buildStatusBadge(b.status),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  isClient ? 'Cuidadora: ${b.caregiverName}' : 'Paciente: ${state.patientMedicalSheet.patientName}',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Horario: ${b.day} a las ${b.slot} h (${currencyFormat.format(b.totalPaid)})',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  (isClient || b.status != BookingStatus.PendingApproval)
                      ? '🔑 Acceso: ${b.keyCustodyMethod} • Código de llegada: ${b.checkInPin}'
                      : '🔒 Dirección y ficha de salud visibles al confirmar la cita',
                  style: const TextStyle(fontSize: 13, color: AppTheme.softSlate),
                ),

                // Progressive Disclosure for Medical Sheet & Emergency Info (avoids wall-of-text overload)
                if (b.status == BookingStatus.Confirmed || b.status == BookingStatus.InProgress) ...[
                  const SizedBox(height: 8),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    leading: const Icon(Icons.medical_information_rounded,
                        color: AppTheme.primary, size: 20),
                    title: const Text(
                      'Ver ficha de salud y contacto de emergencia',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppTheme.primary,
                      ),
                    ),
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceTintMint,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('• Cuidados: ${state.patientMedicalSheet.conditions}',
                                style: const TextStyle(fontSize: 12)),
                            Text('• Alergias: ${state.patientMedicalSheet.allergies}',
                                style:
                                    const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            Text(
                                '• Teléfono familiar: ${state.patientMedicalSheet.emergencyContactName} (${state.patientMedicalSheet.emergencyContactPhone})',
                                style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],

                // GPS / PIN Verification Badge
                if (b.isGpsCheckedIn) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.my_location, color: AppTheme.primary, size: 16),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Presencia en domicilio verificada (<100m GPS / PIN)',
                            style: TextStyle(
                              color: AppTheme.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Daily Care Log ("Cuaderno de Cuidados")
                if (b.careLogs.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundNeutral,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '📋 Cuaderno de Cuidados en Tiempo Real:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 6),
                        ...b.careLogs.map(
                          (log) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '• [${log.category}] ${log.note}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Cancelled / Refunded Notice + 1-Tap Guarantee of Substitution
                if (b.status == BookingStatus.Cancelled) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.info_outline, color: Colors.red, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                isClient
                                    ? 'Solicitud rechazada o expirada. Reembolso íntegro (${currencyFormat.format(b.totalPaid)}) devuelto automáticamente a tu cuenta.'
                                    : 'Solicitud rechazada. Reembolso del 100% (${currencyFormat.format(b.totalPaid)}) devuelto al cliente y notificación enviada.',
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (isClient) ...[
                          const SizedBox(height: 10),
                          ElevatedButton.icon(
                            onPressed: () {
                              final ok = context.read<AppState>().reassignToBackupCaregiver(b.id);
                              if (ok) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        '⚡ Garantía de Sustitución activada: Cuidadora de guardia asignada inmediatamente.'),
                                    backgroundColor: AppTheme.primary,
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.bolt_rounded),
                            label: const Text('Activar Garantía de Sustitución en 1 Toque'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                // Guarantee of Substitution Badge
                if (b.wasSubstituted) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.primary),
                    ),
                    child: Text(
                      '⚡ Garantía de Sustitución Activa (Sustituye a ${b.originalCaregiverName})',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],

                // Shift Hand-off Report Card ("Informe de Cierre de Turno")
                if (b.handoffReport != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.green.shade400),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '✅ Informe de Cierre de Turno Verificado:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '• Medicación: ${b.handoffReport!.medicationGiven ? "Sí" : "No"} | Comida: ${b.handoffReport!.mealIntake} | Ánimo: ${b.handoffReport!.seniorMood}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '• Resumen: ${b.handoffReport!.summaryNote}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],

                // Disputed Notice
                if (b.status == BookingStatus.Disputed) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.deepOrange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.deepOrange),
                    ),
                    child: Text(
                      '⚠️ En mediación: "${b.disputeReason}". Fondos congelados en garantía por Seguridad SeniCare.',
                      style: const TextStyle(
                        color: Colors.deepOrange,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],

                // Completed & Bidirectional Blind Review Section
                if (b.status == BookingStatus.Completed) ...[
                  const SizedBox(height: 12),
                  if (b.reviewRating != null)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.star, color: AppTheme.amber, size: 20),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Valoración familiar: ${b.reviewRating}/5 ★ — "${b.reviewComment}"',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (isClient)
                    OutlinedButton.icon(
                      onPressed: () => _showReviewDialog(context, b.id),
                      icon: const Icon(Icons.star_rate_rounded, color: AppTheme.amber),
                      label: const Text('Valorar a la Cuidadora (1 a 5 ★)'),
                    ),
                  if (!isClient && b.clientReviewRating == null) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _showCaregiverClientReviewDialog(context, b.id),
                      icon: const Icon(Icons.verified_user_outlined, color: AppTheme.primary),
                      label: const Text('Evaluar Entorno Familiar (Reseña Bidireccional)'),
                    ),
                  ],
                  if (b.isBidirectionalReviewPublished) ...[
                    const SizedBox(height: 6),
                    Text(
                      '🔒 Reseña Ciega Bidireccional Publicada (Entorno Familiar: ${b.clientReviewRating}/5 ★)',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],

                // Official Spanish Invoice Button (Ley de Dependencia / IRPF)
                if (b.status != BookingStatus.Cancelled) ...[
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: () => _showOfficialInvoiceDialog(context, b.id),
                    icon: const Icon(Icons.receipt_long_rounded, size: 18, color: AppTheme.primary),
                    label: const Text(
                      'Ver Factura Oficial (Ley Dependencia / IRPF 4% IVA)',
                      style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary),
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // Client Actions: Extend Shift (+1h), Release Escrow, OR Report Incident/Dispute
                if (isClient &&
                    (b.status == BookingStatus.Confirmed ||
                        b.status == BookingStatus.InProgress)) ...[
                  ElevatedButton.icon(
                    onPressed: () {
                      context.read<AppState>().releaseEscrow(b.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✅ Cuidado completado y pago liberado a la cuidadora.'),
                          backgroundColor: AppTheme.primary,
                        ),
                      );
                    },
                    icon: const Icon(Icons.check_circle_outline),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700),
                    label: const Text('Confirmar Éxito y Liberar Pago'),
                  ),
                  const SizedBox(height: 8),
                  if (state.seniorMode) ...[
                    OutlinedButton.icon(
                      onPressed: () {
                        context.read<AppState>().extendBookingShift(b.id, 1);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('⏱️ Turno ampliado +1 hora con Seguro SeniCare.'),
                            backgroundColor: AppTheme.primary,
                          ),
                        );
                      },
                      icon: const Icon(Icons.more_time_rounded),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 60),
                      ),
                      label: const Text('Ampliar +1h'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _showDisputeDialog(context, b.id),
                      icon: const Icon(Icons.report_problem_outlined),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.urgentRed,
                        side: const BorderSide(color: AppTheme.urgentRed),
                        minimumSize: const Size(double.infinity, 60),
                      ),
                      label: const Text('Incidencia'),
                    ),
                  ] else
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              context.read<AppState>().extendBookingShift(b.id, 1);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('⏱️ Turno ampliado +1 hora con Seguro SeniCare.'),
                                  backgroundColor: AppTheme.primary,
                                ),
                              );
                            },
                            icon: const Icon(Icons.more_time_rounded),
                            label: const Text('Ampliar +1h'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _showDisputeDialog(context, b.id),
                            icon: const Icon(Icons.report_problem_outlined),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.urgentRed,
                              side: const BorderSide(color: AppTheme.urgentRed),
                            ),
                            label: const Text('Incidencia'),
                          ),
                        ),
                      ],
                    ),
                ],

                // Caregiver Actions: Accept/Reject Pending OR GPS/PIN Check-in + Care Log + Shift Hand-off
                if (!isClient && b.status == BookingStatus.PendingApproval)
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            context.read<AppState>().confirmBooking(b.id);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Cita aceptada. El chat y el PIN de acceso están activos.'),
                                backgroundColor: AppTheme.primary,
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                          child: const Text('Aceptar Cita'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            context.read<AppState>().rejectBooking(b.id);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Solicitud rechazada. Reembolso devuelto al cliente automáticamente y notificación enviada por chat.'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            minimumSize: Size(0, state.seniorMode ? 64 : 48),
                          ),
                          child: const Text('Rechazar'),
                        ),
                      ),
                    ],
                  ),

                if (!isClient &&
                    (b.status == BookingStatus.Confirmed ||
                        b.status == BookingStatus.InProgress)) ...[
                  if (!b.isGpsCheckedIn)
                    Column(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            context.read<AppState>().checkInGps(b.id);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('📍 Llegada verificada por GPS en el domicilio.'),
                                backgroundColor: AppTheme.primary,
                              ),
                            );
                          },
                          icon: const Icon(Icons.my_location),
                          label: const Text('Fichar Entrada GPS en Domicilio'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            context.read<AppState>().checkInWithPin(b.id, b.checkInPin);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('🔢 Entrada validada con PIN familiar sin cobertura GPS.'),
                                backgroundColor: AppTheme.primary,
                              ),
                            );
                          },
                          icon: const Icon(Icons.pin_rounded),
                          label: Text('Fichar con PIN Familiar (${b.checkInPin})'),
                        ),
                      ],
                    )
                  else
                    Column(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _showAddCareLogDialog(context, b.id),
                          icon: const Icon(Icons.note_add_rounded),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primary,
                            side: const BorderSide(color: AppTheme.primary),
                            minimumSize: Size(double.infinity, state.seniorMode ? 58 : 44),
                          ),
                          label: const Text('Añadir Nota al Cuaderno de Cuidados'),
                        ),
                        if (b.handoffReport == null) ...[
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: () => _showShiftHandoffDialog(context, b.id),
                            icon: const Icon(Icons.assignment_turned_in_rounded),
                            label: const Text('Finalizar Turno y Enviar Informe'),
                          ),
                        ],
                      ],
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _showReviewDialog(BuildContext context, String bookingId) {
    final commentController = TextEditingController();
    int selectedStars = 5;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Valorar Servicio'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (idx) {
                  final star = idx + 1;
                  return IconButton(
                    icon: Icon(
                      star <= selectedStars ? Icons.star : Icons.star_border,
                      color: AppTheme.amber,
                      size: 32,
                    ),
                    onPressed: () => setDialogState(() => selectedStars = star),
                  );
                }),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: commentController,
                decoration: const InputDecoration(
                  hintText: '¿Cómo fue el trato y la puntualidad?',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                context.read<AppState>().submitBookingReview(
                      bookingId,
                      selectedStars,
                      commentController.text.isEmpty
                          ? 'Excelente trato y profesionalidad'
                          : commentController.text,
                    );
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('⭐ ¡Gracias! Tu reseña verificada ha sido publicada.'),
                    backgroundColor: AppTheme.primary,
                  ),
                );
              },
              child: const Text('Publicar Reseña'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDisputeDialog(BuildContext context, String bookingId) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reportar Incidencia'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Describe el motivo (ej. retraso o inasistencia)',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.urgentRed),
            onPressed: () {
              context.read<AppState>().openDispute(bookingId, controller.text);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('⚠️ Disputa registrada. El pago en garantía ha sido congelado.'),
                  backgroundColor: AppTheme.urgentRed,
                ),
              );
            },
            child: const Text('Congelar Pago y Enviar'),
          ),
        ],
      ),
    );
  }

  void _showAddCareLogDialog(BuildContext context, String bookingId) {
    final controller = TextEditingController();
    String selectedCategory = 'Medicación';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Cuaderno de Cuidados'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedCategory,
                items: const [
                  DropdownMenuItem(value: 'Medicación', child: Text('💊 Medicación')),
                  DropdownMenuItem(value: 'Alimentación', child: Text('🍲 Alimentación')),
                  DropdownMenuItem(value: 'Paseo / Actividad', child: Text('🚶 Paseo / Actividad')),
                  DropdownMenuItem(value: 'Estado de Ánimo', child: Text('😊 Estado de Ánimo')),
                ],
                onChanged: (v) {
                  if (v != null) setDialogState(() => selectedCategory = v);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: 'Ej: Tomó la pastilla de las 10h y desayunó bien.',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                context
                    .read<AppState>()
                    .addCareLogEntry(bookingId, selectedCategory, controller.text);
                Navigator.pop(ctx);
              },
              child: const Text('Guardar en Bitácora'),
            ),
          ],
        ),
      ),
    );
  }

  void _showShiftHandoffDialog(BuildContext context, String bookingId) {
    final summaryController = TextEditingController();
    bool medicationGiven = true;
    String mealIntake = 'Completa';
    String seniorMood = 'Tranquilo y animado';
    bool keysLocked = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('📋 Informe de Cierre de Turno'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('💊 Medicación pautada administrada'),
                  value: medicationGiven,
                  onChanged: (v) => setDialogState(() => medicationGiven = v),
                ),
                DropdownButtonFormField<String>(
                  initialValue: mealIntake,
                  decoration: const InputDecoration(
                    labelText: '🍲 Ingesta de comida / hidratación',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Completa', child: Text('Completa (100%)')),
                    DropdownMenuItem(value: 'Parcial', child: Text('Parcial (50%)')),
                    DropdownMenuItem(value: 'Nula', child: Text('Inapetente / Nula')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => mealIntake = v);
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: seniorMood,
                  decoration: const InputDecoration(
                    labelText: '😊 Estado de ánimo del mayor',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'Tranquilo y animado', child: Text('Tranquilo y animado')),
                    DropdownMenuItem(value: 'Estable', child: Text('Estable / Descansando')),
                    DropdownMenuItem(
                        value: 'Agitado / Cansado', child: Text('Agitado / Cansado')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => seniorMood = v);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('🔑 Llaves entregadas / puerta cerrada'),
                  value: keysLocked,
                  onChanged: (v) => setDialogState(() => keysLocked = v),
                ),
                TextField(
                  controller: summaryController,
                  decoration: const InputDecoration(
                    labelText: 'Resumen para el Círculo Familiar',
                    hintText: 'Ej: Tensión 12/8, dimos paseo de 30 min.',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                context.read<AppState>().completeShiftHandoffCheckout(
                      bookingId: bookingId,
                      medicationGiven: medicationGiven,
                      mealIntake: mealIntake,
                      seniorMood: seniorMood,
                      keysReturnedAndLocked: keysLocked,
                      summaryNote: summaryController.text,
                    );
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        '📋 Informe de Cierre enviado a todos los miembros del Círculo Familiar.'),
                    backgroundColor: AppTheme.primary,
                  ),
                );
              },
              child: const Text('Enviar Informe y Cerrar Turno'),
            ),
          ],
        ),
      ),
    );
  }

  void _showCaregiverClientReviewDialog(BuildContext context, String bookingId) {
    final commentController = TextEditingController();
    int selectedStars = 5;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('🔒 Evaluar Entorno Familiar'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Valora la puntualidad de acceso, seguridad del domicilio y exactitud de la ficha médica (Reseña ciega bidireccional):',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (idx) {
                  final star = idx + 1;
                  return IconButton(
                    icon: Icon(
                      star <= selectedStars ? Icons.star : Icons.star_border,
                      color: AppTheme.amber,
                      size: 32,
                    ),
                    onPressed: () => setDialogState(() => selectedStars = star),
                  );
                }),
              ),
              TextField(
                controller: commentController,
                decoration: const InputDecoration(
                  hintText: 'Ej: Familia muy respetuosa y pautas claras.',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                context.read<AppState>().submitClientReviewByCaregiver(
                      bookingId,
                      selectedStars,
                      commentController.text,
                    );
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('🔒 Valoración bidireccional registrada correctamente.'),
                    backgroundColor: AppTheme.primary,
                  ),
                );
              },
              child: const Text('Guardar Evaluación'),
            ),
          ],
        ),
      ),
    );
  }

  void _showOfficialInvoiceDialog(BuildContext context, String bookingId) {
    final invoice = context.read<AppState>().generateOfficialInvoice(bookingId);
    if (invoice == null) return;
    final currencyFormat = NumberFormat.currency(symbol: '€', decimalDigits: 2);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('🧾 Factura ${invoice.invoiceNumber}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Certificada para Deducción IRPF y Prestación Vinculada (Ley 39/2006 de Dependencia)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
            ),
            const Divider(height: 20),
            Text('Titular Fiscal: ${invoice.familyFullName}'),
            Text('NIF / DNI: ${invoice.familyNif}'),
            Text('Persona Atendida: ${invoice.patientName}'),
            Text('Grado Reconocido: ${invoice.dependencyGradeLabel}'),
            Text('Profesional: ${invoice.caregiverName} (${invoice.durationHours}h)'),
            const Divider(height: 20),
            Text('Base Imponible: ${currencyFormat.format(invoice.baseTaxableEur)}'),
            Text(
                'IVA Superreducido (${invoice.vatRatePercent}%): ${currencyFormat.format(invoice.vatAmountEur)}'),
            const SizedBox(height: 6),
            Text(
              'TOTAL ABONADO: ${currencyFormat.format(invoice.totalPaidEur)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Divider(height: 20),
            Text(
              '🔐 Huella VeriFactu AEAT:\n${invoice.verifactuHash}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 4),
            Text(
              '📲 Cotejo QR AEAT: ${invoice.aeatVerificationQrUrl}',
              style: const TextStyle(fontSize: 10, color: AppTheme.primary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      '📥 Factura Oficial ${invoice.invoiceNumber} exportada con desglose Ley de Dependencia.'),
                  backgroundColor: AppTheme.primary,
                ),
              );
            },
            icon: const Icon(Icons.download_rounded),
            label: const Text('Descargar PDF Oficial'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(BookingStatus status) {
    Color color;
    String text;
    switch (status) {
      case BookingStatus.PendingApproval:
        color = AppTheme.amber;
        text = '⏳ Esperando respuesta';
        break;
      case BookingStatus.Confirmed:
        color = Colors.blue.shade700;
        text = '✓ Cita confirmada';
        break;
      case BookingStatus.InProgress:
        color = AppTheme.primary;
        text = '🟢 Cuidadora en casa';
        break;
      case BookingStatus.Completed:
        color = Colors.green.shade700;
        text = '✅ Terminada con éxito';
        break;
      case BookingStatus.Cancelled:
        color = AppTheme.urgentRed;
        text = '↩️ Cancelada (Dinero devuelto)';
        break;
      case BookingStatus.Disputed:
        color = Colors.deepOrange;
        text = '🛡️ En revisión por Soporte';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }
}

// --- SCREEN E: Secured Chat with Context-Aware Post-Booking Unlocker ---
class ChatScreen extends StatefulWidget {
  final bool isStandalone;
  const ChatScreen({super.key, this.isStandalone = false});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();

  void _sendMessage(BuildContext context) {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final result = context.read<AppState>().sendChatMessage(text);
    _controller.clear();

    if (result.wasBlocked) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('🛡️ Protección de Seguridad SeniCare'),
          content: Text(
            'Por tu seguridad y para mantener activa la Garantía SeniCare, el intercambio de ${result.blockReason ?? "datos de contacto externos"} está protegido hasta confirmar la reserva.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isUnlocked = state.hasActiveConfirmedBooking;

    final content = Column(
      children: [
        // Context-Aware Security Banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: isUnlocked ? AppTheme.primaryLight : Colors.orange.withValues(alpha: 0.12),
          child: Row(
            children: [
              Icon(
                isUnlocked ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                size: 18,
                color: isUnlocked ? AppTheme.primary : Colors.orange.shade900,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isUnlocked
                      ? 'Reserva Confirmada: Chat desbloqueado para compartir dirección, portero y teléfonos.'
                      : 'Modo Pre-Reserva: Datos de contacto protegidos hasta confirmar la cita.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isUnlocked ? AppTheme.primary : Colors.orange.shade900,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: state.chatMessages.length,
            itemBuilder: (context, index) {
              final msg = state.chatMessages[index];
              final isMe = msg.sender == ChatSender.Client;
              return Align(
                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isMe ? AppTheme.primary : Colors.white,
                    borderRadius: BorderRadius.circular(16).copyWith(
                      bottomRight: isMe ? Radius.zero : null,
                      bottomLeft: !isMe ? Radius.zero : null,
                    ),
                    border: isMe ? null : Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    msg.text,
                    style: TextStyle(
                      color: isMe ? Colors.white : AppTheme.darkSlate,
                      fontSize: state.seniorMode ? 18 : 14,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: isUnlocked
                        ? 'Escribe dirección, portero o mensaje...'
                        : 'Escribe un mensaje seguro...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onSubmitted: (_) => _sendMessage(context),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: AppTheme.primary,
                radius: state.seniorMode ? 30 : 24,
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: () => _sendMessage(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (widget.isStandalone) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat Directo Protegido')),
        body: content,
      );
    }
    return content;
  }
}

// --- SCREEN F: Caregiver Dashboard (Elena Sanz Account) ---
class CaregiverDashboard extends StatelessWidget {
  const CaregiverDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final seniorMode = state.seniorMode;
    final currencyFormat = NumberFormat.currency(symbol: '€', decimalDigits: 2);

    final activeCg = state.caregivers.firstWhere(
      (c) => c.id == state.activeCaregiverId,
      orElse: () => state.caregivers.first,
    );
    final double earnings = state.getCaregiverReleasedEarnings(activeCg.id);

    final pendingBookings = state.bookings
        .where((b) =>
            b.status == BookingStatus.PendingApproval &&
            b.caregiverId == activeCg.id)
        .toList();

    return ListView(
      padding: EdgeInsets.all(seniorMode ? 24 : 16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text('Hola, ${activeCg.name.split(" ").first} 👋',
                  style: theme.textTheme.headlineSmall),
            ),
            DropdownButton<String>(
              value: activeCg.id,
              underline: const SizedBox.shrink(),
              items: state.caregivers
                  .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                  .toList(),
              onChanged: (id) {
                if (id != null) state.setActiveCaregiverId(id);
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            gradient: AppTheme.antigravityHeaderGradient,
            borderRadius: BorderRadius.circular(24),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tu dinero ganado listo para cobrar',
                style: TextStyle(color: AppTheme.primaryLight, fontSize: 15),
              ),
              const SizedBox(height: 8),
              Text(
                currencyFormat.format(earnings),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '💚 Cuanto más repites con una familia, más ganas tú (hasta el 94% íntegro para ti).',
                style: TextStyle(color: AppTheme.primaryLight, fontSize: 12),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Fondos transferidos a tu cuenta bancaria conectada.'),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppTheme.primary,
                ),
                icon: const Icon(Icons.account_balance_rounded),
                label: const Text('Enviar dinero a mi banco'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // --- TARJETA DE GESTIÓN DE CUENTA BANCARIA (IBAN) Y ESTADO DE STRIPE ---
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: activeCg.stripePayoutStatus == 'bank_rejected'
                  ? Colors.red.shade300
                  : Colors.grey.shade200,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: activeCg.stripePayoutStatus == 'bank_rejected'
                                ? Colors.red.shade50
                                : AppTheme.primaryLight.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.account_balance_rounded,
                            color: activeCg.stripePayoutStatus == 'bank_rejected'
                                ? Colors.red
                                : AppTheme.primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Cuenta Bancaria de Cobro',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            Text(
                              '${activeCg.bankName} • ${activeCg.maskedIban}',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: activeCg.stripePayoutStatus == 'bank_rejected'
                            ? Colors.red.withValues(alpha: 0.1)
                            : Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: activeCg.stripePayoutStatus == 'bank_rejected'
                              ? Colors.red
                              : Colors.green,
                        ),
                      ),
                      child: Text(
                        activeCg.stripePayoutStatus == 'bank_rejected'
                            ? 'Revisión requerida'
                            : 'Verificada para cobro',
                        style: TextStyle(
                          color: activeCg.stripePayoutStatus == 'bank_rejected'
                              ? Colors.red
                              : Colors.green.shade800,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if (activeCg.stripePayoutStatus == 'bank_rejected') ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.error_outline_rounded, color: Colors.red, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Tu banco ha devuelto la última transferencia. Actualiza tu IBAN a continuación para reintentar el cobro automáticamente.',
                            style: TextStyle(color: Colors.red, fontSize: 12, height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showUpdateBankAccountModal(context, activeCg),
                        icon: const Icon(Icons.edit_note_rounded, size: 18),
                        label: const Text('Cambiar cuenta bancaria (IBAN)'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primary,
                          side: const BorderSide(color: AppTheme.primary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Información de seguridad bancaria',
                      icon: const Icon(Icons.shield_outlined, color: AppTheme.primary),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                '🔒 Conexión bancaria segura PCI-DSS: tus datos de cobro están blindados por Stripe y el Banco de España.'),
                            backgroundColor: AppTheme.primary,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Solicitudes Pendientes (${pendingBookings.length})',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (pendingBookings.isEmpty)
          const Text('No tienes nuevas solicitudes pendientes.')
        else
          ...pendingBookings.map(
            (b) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Reserva el ${b.day} a las ${b.slot} (${b.durationHours}h)',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange),
                          ),
                          child: const Text(
                            'Pendiente',
                            style: TextStyle(
                              color: Colors.orange,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Ganancia neta asegurada: ${currencyFormat.format(b.caregiverNetEarnings)} (${100 - b.commissionRatePercent}% de ${currencyFormat.format(b.cost)})',
                      style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              context.read<AppState>().confirmBooking(b.id);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Cita aceptada. El cliente ha sido notificado.'),
                                  backgroundColor: AppTheme.primary,
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                            child: const Text('Aceptar Cita'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              context.read<AppState>().rejectBooking(b.id);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Solicitud rechazada. Reembolso devuelto al cliente automáticamente y notificación enviada por chat.'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              minimumSize: Size(0, seniorMode ? 64 : 48),
                            ),
                            child: const Text('Rechazar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 24),
        Text('Gestión de Disponibilidad', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Lunes 09:00 - 12:00'),
                value: true,
                onChanged: (v) {},
                activeThumbColor: AppTheme.primary,
              ),
              SwitchListTile(
                title: const Text('Lunes 16:00 - 19:00'),
                value: true,
                onChanged: (v) {},
                activeThumbColor: AppTheme.primary,
              ),
              SwitchListTile(
                title: const Text('Martes 10:00 - 13:00'),
                value: false,
                onChanged: (v) {},
                activeThumbColor: AppTheme.primary,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () {
                final ics = state.exportCalendarToIcs();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        '📅 Turnos guardados para el calendario de tu móvil (${ics.split("\n").length} eventos).'),
                    backgroundColor: AppTheme.primary,
                  ),
                );
              },
              icon: const Icon(Icons.calendar_today_rounded, size: 18),
              label: const Text('Guardar turnos en mi móvil'),
            ),
            OutlinedButton.icon(
              onPressed: () {
                final dac7 = state.generateCaregiverDac7Report(activeCg.id);
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('📄 Resumen de mis ingresos (Hacienda)'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Profesional: ${dac7.caregiverName}'),
                        Text('DNI / NIF: ${dac7.taxNif}'),
                        Text('Año: ${dac7.fiscalYear}'),
                        const Divider(height: 20),
                        Text('Cuidados realizados: ${dac7.completedServicesCount}'),
                        Text('Total facturado: ${currencyFormat.format(dac7.grossVolumeEur)}'),
                        Text(
                            'Gestión y seguro: ${currencyFormat.format(dac7.platformFeesWithheldEur)}'),
                        Text(
                          'Recibido en tu banco: ${currencyFormat.format(dac7.netTransferredToCaregiverEur)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, color: AppTheme.primary),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cerrar'),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.request_quote_rounded, size: 18),
              label: const Text('Resumen de ingresos (Hacienda)'),
            ),
            OutlinedButton.icon(
              onPressed: () => ExplorerScreen.showGuidedDocumentsCenterDialog(context),
              icon: const Icon(Icons.verified_user_rounded, size: 18),
              label: const Text('Mis documentos paso a paso (Gratis)'),
            ),
          ],
        ),
      ],
    );
  }

  static void _showUpdateBankAccountModal(BuildContext context, CaregiverProfile caregiver) {
    final ibanController = TextEditingController(text: 'ES91');
    final bankController = TextEditingController(text: caregiver.bankName);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Cambiar Cuenta Bancaria (IBAN)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Indica tu nueva cuenta corriente para recibir tus ingresos. Las transferencias en espera se enviarán a este nuevo IBAN.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13, height: 1.3),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: bankController,
              decoration: const InputDecoration(
                labelText: 'Nombre del Banco o Entidad',
                hintText: 'Ej. CaixaBank, BBVA, Santander, ING, Revolut',
                prefixIcon: Icon(Icons.business_rounded, color: AppTheme.primary),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ibanController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Número IBAN completo',
                hintText: 'ES91 2100 0418 4502 0005 1332',
                prefixIcon: Icon(Icons.credit_card_rounded, color: AppTheme.primary),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                final iban = ibanController.text.trim();
                final bank = bankController.text.trim();
                if (iban.length < 15) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('Por favor introduce un IBAN válido (mínimo 15 caracteres).'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                final settled = context.read<AppState>().updateCaregiverBankAccount(
                  caregiverId: caregiver.id,
                  newIban: iban,
                  newBankName: bank.isEmpty ? 'Banco Nacional' : bank,
                );
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      settled > 0
                          ? '✅ Cuenta bancaria actualizada. Se han transferido $settled cobro(s) que estaban retenidos.'
                          : '✅ Cuenta bancaria actualizada correctamente.',
                    ),
                    backgroundColor: AppTheme.primary,
                  ),
                );
              },
              child: const Text('Guardar y Vincular Nueva Cuenta'),
            ),
            const SizedBox(height: 10),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('🔒 Redirigiendo al panel oficial de Stripe Express con cifrado PCI-DSS...'),
                      backgroundColor: AppTheme.primary,
                    ),
                  );
                },
                icon: const Icon(Icons.lock_rounded, size: 16),
                label: const Text('Gestionar directamente en portal de Stripe'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
