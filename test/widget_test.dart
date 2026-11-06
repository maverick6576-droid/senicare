import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:senicare/main.dart';

void main() {
  testWidgets('App initialization and Senior Accessible Mode hub smoke test',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (context) => AppState(),
        child: const SeniCareApp(),
      ),
    );

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Garantía 100% SeniCare'), findsOneWidget);

    // Activate Senior Mode
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    // Verify Senior Accessible Hub cards are rendered
    expect(find.text('TU CUIDADORA DE CONFIANZA'), findsOneWidget);
    expect(find.text('MIS MEDICINAS DE HOY'), findsOneWidget);
    expect(find.text('AYUDA URGENTE / SOS FAMILIA'), findsOneWidget);
  });

  test('Booking rejection processes automatic Euro refund and sends professional chat message', () {
    final appState = AppState();
    final initialMessagesCount = appState.chatMessages.length;

    final testBooking = Booking(
      id: 'test_booking_1',
      caregiverId: 'c1',
      caregiverName: 'Elena García',
      day: 'Lunes',
      slot: '09:00',
      status: BookingStatus.PendingApproval,
      cost: 50.0,
      appCommission: 9.0,
      totalPaid: 50.0,
    );

    final added = appState.addBooking(testBooking);
    expect(added, true);
    expect(appState.isSlotBooked('c1', 'Lunes', '09:00'), true);
    expect(appState.bookings.last.status, BookingStatus.PendingApproval);
    expect(appState.bookings.last.isRefunded, false);

    // Double-booking prevention on the same slot
    final duplicateAdded = appState.addBooking(testBooking);
    expect(duplicateAdded, false);

    // Act: Reject booking
    appState.rejectBooking('test_booking_1');

    // Assert: Refund, status, and slot freed
    final rejectedBooking = appState.bookings.firstWhere((b) => b.id == 'test_booking_1');
    expect(rejectedBooking.status, BookingStatus.Cancelled);
    expect(rejectedBooking.isRefunded, true);
    expect(rejectedBooking.isEscrowReleased, false);
    expect(appState.isSlotBooked('c1', 'Lunes', '09:00'), false);

    // Assert: Automated professional chat message sent to client in Euros
    expect(appState.chatMessages.length, initialMessagesCount + 1);
    final lastMessage = appState.chatMessages.last;
    expect(lastMessage.sender, ChatSender.Caregiver);
    expect(lastMessage.text.contains('ha sido declinada'), true);
    expect(lastMessage.text.contains('Devolución automática procesada'), true);
    expect(lastMessage.text.contains('€50.00'), true);
  });

  test('Unified 1:1 commission tiers scale 18% -> 10% -> 6% without double-dipping', () {
    final appState = AppState();

    // 0 completed bookings -> 18% tier
    final quote1 = appState.calculateCommissionQuote(
      caregiverId: 'c1',
      pricePerHour: 20.0,
      durationHours: 2,
    );
    expect(quote1.commissionRatePercent, 18);
    expect(quote1.baseCost, 40.0);
    expect(quote1.platformFee, 7.20);
    expect(quote1.caregiverNetPayout, 32.80);
    expect(quote1.totalClientPayable, 40.0); // caregiverNetPayout + platformFee == totalClientPayable

    // Complete 1st booking -> next quote should be 10% tier
    appState.addBooking(Booking(
      id: 'b1',
      caregiverId: 'c1',
      caregiverName: 'Elena Sanz',
      day: 'Lunes',
      slot: '09:00',
      cost: 40.0,
      appCommission: 7.2,
      totalPaid: 40.0,
      status: BookingStatus.Completed,
      isEscrowReleased: true,
    ));

    final quote2 = appState.calculateCommissionQuote(
      caregiverId: 'c1',
      pricePerHour: 20.0,
      durationHours: 2,
    );
    expect(quote2.commissionRatePercent, 10);
    expect(quote2.platformFee, 4.0);
    expect(quote2.caregiverNetPayout, 36.0);
    expect(quote2.totalClientPayable, 40.0);

    // Complete 4 more bookings (total 5) -> next quote should be 6% tier
    for (int i = 2; i <= 5; i++) {
      appState.bookings.add(Booking(
        id: 'b$i',
        caregiverId: 'c1',
        caregiverName: 'Elena Sanz',
        day: 'Día $i',
        slot: '10:00',
        cost: 40.0,
        appCommission: 4.0,
        totalPaid: 40.0,
        status: BookingStatus.Completed,
        isEscrowReleased: true,
      ));
    }

    final quote3 = appState.calculateCommissionQuote(
      caregiverId: 'c1',
      pricePerHour: 20.0,
      durationHours: 2,
    );
    expect(quote3.commissionRatePercent, 6);
    expect(quote3.platformFee, 2.40);
    expect(quote3.caregiverNetPayout, 37.60);
    expect(quote3.totalClientPayable, 40.0);
  });

  test('Context-Aware Anti-Bypass blocks pre-booking contact and unlocks post-confirmation', () {
    final appState = AppState();

    // 1. Pre-booking: blocks phone numbers, spoken digits, emails, social handles
    expect(AntiBypassValidator.evaluate('Llámame al 612 34 56 78').wasBlocked, true);
    expect(AntiBypassValidator.evaluate('Mi número es seis uno dos tres cuatro').wasBlocked, true);
    expect(AntiBypassValidator.evaluate('Escríbeme a pedro@gmail.com').wasBlocked, true);
    expect(AntiBypassValidator.evaluate('Hablamos por whatsapp o @elena_care').wasBlocked, true);

    final preResult = appState.sendChatMessage('El teléfono de mi padre es 612345678');
    expect(preResult.wasBlocked, true);

    // 2. Post-confirmation: unlocks phone numbers and intercom details
    appState.addBooking(Booking(
      id: 'b_unlock',
      caregiverId: 'c1',
      caregiverName: 'Elena Sanz',
      day: 'Jueves',
      slot: '09:00',
      cost: 36.0,
      appCommission: 6.48,
      totalPaid: 36.0,
    ));
    appState.confirmBooking('b_unlock');
    expect(appState.hasActiveConfirmedBooking, true);

    final postResult = appState.sendChatMessage('Llama al 612345678 cuando llegues al portero 3B');
    expect(postResult.wasBlocked, false);
    expect(postResult.sanitizedText.contains('612345678'), true);
  });

  test('24h Auto-Completion, Zombie Pending Timeout, PIN Check-in, Overtime & Verified Reviews', () {
    final appState = AppState();
    final pastTime = DateTime.now().subtract(const Duration(hours: 30));

    // 1. Zombie PendingApproval (>12h) gets auto-cancelled and refunded
    appState.addBooking(Booking(
      id: 'b_zombie',
      caregiverId: 'c1',
      caregiverName: 'Elena Sanz',
      day: 'Lunes',
      slot: '10:00',
      cost: 36.0,
      appCommission: 6.48,
      totalPaid: 36.0,
      status: BookingStatus.PendingApproval,
      createdAt: pastTime,
    ));

    // 2. Confirmed booking >24h after service end where client forgot to confirm
    appState.addBooking(Booking(
      id: 'b_forgotten',
      caregiverId: 'c1',
      caregiverName: 'Elena Sanz',
      day: 'Martes',
      slot: '10:00',
      durationHours: 2,
      cost: 36.0,
      appCommission: 6.48,
      totalPaid: 36.0,
      status: BookingStatus.Confirmed,
      createdAt: pastTime,
      serviceEndTime: pastTime.add(const Duration(hours: 2)),
    ));

    // Test 4-digit PIN Check-in & +1h Shift Extension before maintenance runs
    expect(appState.checkInWithPin('b_forgotten', '4829'), true);
    expect(appState.extendBookingShift('b_forgotten', 1), true);
    final activeBooking = appState.bookings.firstWhere((b) => b.id == 'b_forgotten');
    expect(activeBooking.durationHours, 3);
    expect(activeBooking.totalPaid, 54.0);

    // Run scheduled maintenance
    final processed = appState.runScheduledEscrowMaintenance();
    expect(processed, 2);

    final zombie = appState.bookings.firstWhere((b) => b.id == 'b_zombie');
    expect(zombie.status, BookingStatus.Cancelled);
    expect(zombie.isRefunded, true);

    expect(activeBooking.status, BookingStatus.Completed);
    expect(activeBooking.isEscrowReleased, true);

    // Submit 5-star review on completed booking
    final reviewed = appState.submitBookingReview('b_forgotten', 5, 'Inmejorable atención');
    expect(reviewed, true);
    expect(activeBooking.reviewRating, 5);
    expect(appState.caregivers.first.reviewsCount, 125);
  });

  test('Payment & Escrow Safeguards: Ghost Release Prevention, Idempotency & Chargebacks', () {
    final appState = AppState();

    // 1. Prevent Ghost Release when caregiver has not connected a Stripe bank account
    appState.caregivers.first.hasStripeConnectedAccount = false;
    appState.addBooking(Booking(
      id: 'b_no_bank',
      caregiverId: 'c1',
      caregiverName: 'Elena Sanz',
      day: 'Miércoles',
      slot: '11:00',
      cost: 36.0,
      appCommission: 6.48,
      totalPaid: 36.0,
      status: BookingStatus.InProgress,
    ));

    final releasedEarly = appState.releaseEscrow('b_no_bank');
    expect(releasedEarly, false);
    final pendingConnectBooking = appState.bookings.firstWhere((b) => b.id == 'b_no_bank');
    expect(pendingConnectBooking.status, BookingStatus.Completed);
    expect(pendingConnectBooking.isEscrowReleased, false);
    expect(pendingConnectBooking.escrowStatus, 'pending_caregiver_connect');

    // When caregiver completes Stripe Connect onboarding, pending funds automatically release
    final settledCount = appState.connectCaregiverStripeAccount('c1');
    expect(settledCount, 1);
    expect(pendingConnectBooking.isEscrowReleased, true);
    expect(pendingConnectBooking.escrowStatus, 'released');

    // 2. Anti-double refund / replay idempotency on rejectBooking
    appState.addBooking(Booking(
      id: 'b_reject_once',
      caregiverId: 'c1',
      caregiverName: 'Elena Sanz',
      day: 'Jueves',
      slot: '17:00',
      cost: 36.0,
      appCommission: 6.48,
      totalPaid: 36.0,
    ));
    expect(appState.rejectBooking('b_reject_once'), true);
    expect(appState.rejectBooking('b_reject_once'), false); // Second call blocked

    // 3. Bank Chargeback freezes Escrow
    appState.addBooking(Booking(
      id: 'b_chargeback',
      caregiverId: 'c1',
      caregiverName: 'Elena Sanz',
      day: 'Viernes',
      slot: '20:00',
      cost: 44.0,
      appCommission: 7.92,
      totalPaid: 44.0,
      status: BookingStatus.InProgress,
    ));
    expect(appState.handleBankChargeback('b_chargeback'), true);
    expect(appState.releaseEscrow('b_chargeback'), false);
  });

  test('7 Market-Leader Solutions: Barthel Triage, 1-Tap Substitution, Handoff Report, Family Circle, Bidirectional Review, Bundles & Official Invoice', () {
    final appState = AppState();

    // 1. Clinical Dependency Triage (Escala Barthel): Grado III + Crane filters out non-certified caregivers (c2)
    appState.updateDependencyTriage(
      grade: 3,
      requiresCrane: true,
      filterCompatibleOnly: true,
    );
    expect(appState.filteredCaregivers.length, 2); // c1 and c3 are Grado III & Crane certified; c2 is Grado I

    // 2. Guarantee of Urgent Substitution (1-Tap Backup Caregiver Re-assignment)
    appState.addBooking(Booking(
      id: 'b_sub',
      caregiverId: 'c1',
      caregiverName: 'Elena Sanz',
      day: 'Lunes',
      slot: '09:00',
      durationHours: 2,
      cost: 36.0,
      appCommission: 6.48,
      totalPaid: 36.0,
    ));
    appState.rejectBooking('b_sub');
    expect(appState.reassignToBackupCaregiver('b_sub'), true);
    final subBooking = appState.bookings.firstWhere((b) => b.id == 'b_sub');
    expect(subBooking.wasSubstituted, true);
    expect(subBooking.caregiverId, 'c3'); // Compatible Grado III backup caregiver
    expect(subBooking.status, BookingStatus.Confirmed);
    expect(subBooking.isRefunded, false);

    // 3. Structured Check-out with Shift Hand-off Report
    expect(
      appState.completeShiftHandoffCheckout(
        bookingId: 'b_sub',
        medicationGiven: true,
        mealIntake: 'Completa',
        seniorMood: 'Tranquilo y animado',
        keysReturnedAndLocked: true,
        summaryNote: 'Tensión 12/8 estable y paseo matutino.',
      ),
      true,
    );
    expect(subBooking.handoffReport, isNotNull);
    expect(subBooking.handoffReport!.mealIntake, 'Completa');

    // 4. Shared Family Circle ("Círculo Familiar")
    expect(appState.familyCircle.length, 3);
    expect(
      appState.addFamilyCircleMember(
        name: 'Marta Vila',
        relation: 'Nieta',
        roleLabel: 'Familiar Supervisor',
      ),
      true,
    );
    expect(appState.familyCircle.length, 4);

    // 5. Blind Bidirectional Review (Family <-> Caregiver)
    expect(appState.releaseEscrow('b_sub'), true);
    expect(appState.submitBookingReview('b_sub', 5, 'Excelente sustitución'), true);
    expect(subBooking.isBidirectionalReviewPublished, false); // Waiting for caregiver review
    expect(appState.submitClientReviewByCaregiver('b_sub', 5, 'Familia muy amable'), true);
    expect(subBooking.isBidirectionalReviewPublished, true); // Both reviewed -> Published!

    // 6. Prepaid Care Hour Bundle ("Bolsa de Horas Prepagada")
    expect(appState.purchaseCareHourBundle(20), true);
    expect(appState.prepaidHourBalance, 20);
    expect(appState.applyPrepaidHoursToBooking('b_sub'), true);
    expect(appState.prepaidHourBalance, 18);

    // 7. Official Spanish Tax & Dependency Law Invoice (4% Super-reduced VAT)
    final invoice = appState.generateOfficialInvoice('b_sub');
    expect(invoice, isNotNull);
    expect(invoice!.vatRatePercent, 4);
    expect(invoice.totalPaidEur, 36.0);
    expect(invoice.familyNif, '47892103-Z');
  });
}
