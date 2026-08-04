// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:senicare/main.dart';

void main() {
  testWidgets('App initialization smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (context) => AppState(),
        child: const SeniCareApp(),
      ),
    );

    // Verify that the login screen title or main UI builds without error.
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  test('Booking rejection processes automatic refund and sends professional chat message', () {
    final appState = AppState();
    final initialMessagesCount = appState.chatMessages.length;

    final testBooking = Booking(
      id: 'test_booking_1',
      caregiverId: 'c1',
      caregiverName: 'Elena García',
      day: 'Mañana',
      slot: '10:00',
      status: BookingStatus.PendingApproval,
      cost: 50.0,
      appCommission: 7.5,
      totalPaid: 57.5,
    );

    appState.addBooking(testBooking);
    expect(appState.bookings.last.status, BookingStatus.PendingApproval);
    expect(appState.bookings.last.isRefunded, false);

    // Act: Reject booking
    appState.rejectBooking('test_booking_1');

    // Assert: Refund and status
    final rejectedBooking = appState.bookings.firstWhere((b) => b.id == 'test_booking_1');
    expect(rejectedBooking.status, BookingStatus.Cancelled);
    expect(rejectedBooking.isRefunded, true);
    expect(rejectedBooking.isEscrowReleased, false);

    // Assert: Automated professional chat message sent to client
    expect(appState.chatMessages.length, initialMessagesCount + 1);
    final lastMessage = appState.chatMessages.last;
    expect(lastMessage.sender, ChatSender.Caregiver);
    expect(lastMessage.text.contains('ha sido declinada'), true);
    expect(lastMessage.text.contains('Devolución automática procesada'), true);
    expect(lastMessage.text.contains('\$57.50'), true);
  });
}

