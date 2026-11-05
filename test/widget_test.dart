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
      totalPaid: 59.0,
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
    expect(lastMessage.text.contains('€59.00'), true);
  });

  test('Dynamic commission tiers scale from 18% -> 10% -> 6% based on completed history', () {
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

    // Complete 1st booking -> next quote should be 10% tier
    appState.addBooking(Booking(
      id: 'b1',
      caregiverId: 'c1',
      caregiverName: 'Elena Sanz',
      day: 'Lunes',
      slot: '09:00',
      cost: 40.0,
      appCommission: 7.2,
      totalPaid: 47.2,
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
        totalPaid: 44.0,
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
  });

  test('Semantic Anti-Bypass validator blocks phones, spoken digits, emails, and social handles', () {
    expect(AntiBypassValidator.evaluate('Llámame al 612 34 56 78').wasBlocked, true);
    expect(AntiBypassValidator.evaluate('Mi número es seis uno dos tres cuatro').wasBlocked, true);
    expect(AntiBypassValidator.evaluate('Escríbeme a pedro@gmail.com').wasBlocked, true);
    expect(AntiBypassValidator.evaluate('Hablamos por whatsapp o @elena_care').wasBlocked, true);
    expect(
      AntiBypassValidator.evaluate('Hola Elena, ¿tienes experiencia con Alzheimer?').wasBlocked,
      false,
    );
  });

  test('GPS check-in, Care Log, and Dispute freeze Escrow release', () {
    final appState = AppState();
    appState.addBooking(Booking(
      id: 'b_gps',
      caregiverId: 'c1',
      caregiverName: 'Elena Sanz',
      day: 'Martes',
      slot: '10:00',
      cost: 36.0,
      appCommission: 6.48,
      totalPaid: 42.48,
      status: BookingStatus.Confirmed,
    ));

    appState.checkInGps('b_gps');
    final b = appState.bookings.first;
    expect(b.isGpsCheckedIn, true);
    expect(b.status, BookingStatus.InProgress);
    expect(b.careLogs.length, 1);

    appState.addCareLogEntry('b_gps', 'Medicación', 'Tomó Enalapril 10mg puntual');
    expect(b.careLogs.length, 2);

    // Open dispute -> freezes escrow release
    appState.openDispute('b_gps', 'El turno finalizó antes de tiempo');
    expect(b.isDisputed, true);
    expect(b.status, BookingStatus.Disputed);
    expect(appState.releaseEscrow('b_gps'), false);
  });
}
