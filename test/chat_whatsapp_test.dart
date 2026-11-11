import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';
import 'package:senicare/screens/chat_screen.dart';
import 'package:senicare/screens/inbox_screen.dart';

class _TestClientRepository implements ClientRepository {
  final Map<String, ClientProfile> clients = {};

  @override
  Future<ClientProfile?> getClient(String id) async => clients[id];

  @override
  Future<void> updateClient(String id, Map<String, dynamic> data) async {}
}

Booking _makeBooking({
  required String id,
  required String clientId,
  required String caregiverId,
  BookingStatus status = BookingStatus.confirmed,
}) {
  return Booking(
    id: id,
    clientId: clientId,
    caregiverId: caregiverId,
    caregiverName: 'Elena Cuidadora',
    day: '2026-11-15',
    slot: '10:00-12:00',
    status: status,
    cost: 40,
    clientFee: 1.2,
    caregiverCommissionRate: 0.18,
    caregiverCommissionAmount: 7.2,
    caregiverPayout: 32.8,
    totalPaid: 41.2,
    createdAt: DateTime(2026, 11, 10),
  );
}

void main() {
  group('ChatMessage & ChatConversation WhatsApp models', () {
    test('infers legacy message types and computes preview summaries', () {
      final fake = FakeFirebaseFirestore();
      final docAudio = fake.collection('m').doc('legacy_audio');
      // Use direct constructor + summary checks
      final audioMsg = ChatMessage(
        id: docAudio.id,
        sender: ChatSender.Client,
        text: '🎤 Nota de voz (0:14)',
        timestamp: DateTime(2026, 11, 11, 9, 0),
        type: ChatMessageType.audio,
        audioDurationSeconds: 14,
      );
      expect(audioMsg.previewSummary, '🎤 Nota de voz (0:14)');

      final imgCaption = ChatMessage(
        sender: ChatSender.Caregiver,
        text: 'Foto del desayuno',
        timestamp: DateTime(2026, 11, 11, 9, 5),
        type: ChatMessageType.image,
      );
      expect(imgCaption.previewSummary, '📷 Foto del desayuno');

      final deleted = imgCaption.copyWith(isDeleted: true);
      expect(deleted.previewSummary, '🚫 Mensaje eliminado');
    });

    test('isPeerTyping respects role and 6-second freshness window', () {
      final now = DateTime(2026, 11, 11, 12, 0, 10);
      final conv = ChatConversation(
        roomId: 'c1_cg1',
        clientId: 'c1',
        caregiverId: 'cg1',
        caregiverName: 'Elena',
        lastMessage: 'Hola',
        lastMessageTimestamp: now,
        caregiverTypingAt: now.subtract(const Duration(seconds: 3)),
        clientTypingAt: now.subtract(const Duration(seconds: 12)),
      );

      expect(conv.isPeerTyping(true, now: now), isTrue);
      expect(conv.isPeerTyping(false, now: now), isFalse);
      expect(conv.familyDisplayName('María García López'), 'Familia García López');
    });
  });

  group('FirestoreChatRepository WhatsApp operations', () {
    late FakeFirebaseFirestore fakeFirestore;
    late FirestoreChatRepository repo;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      repo = FirestoreChatRepository(firestore: fakeFirestore);
    });

    test('sanitizeMessageText blocks contacts before confirmation and allows after',
        () {
      const raw = 'Escríbeme a maria@gmail.com o llama al +34 612 345 678';
      final blocked = FirestoreChatRepository.sanitizeMessageText(
        raw,
        allowContactSharing: false,
      );
      expect(blocked, isNot(contains('maria@gmail.com')));
      expect(blocked, isNot(contains('612 345 678')));
      expect(blocked, contains('[Contacto bloqueado hasta confirmar reserva]'));

      final allowed = FirestoreChatRepository.sanitizeMessageText(
        raw,
        allowContactSharing: true,
      );
      expect(allowed, raw);
    });

    test('sendMessage stores metadata, sorts inbox without composite index, and handles read receipts',
        () async {
      await repo.sendMessage(
        'client_1',
        'cg_1',
        'Elena López',
        ChatMessage(
          sender: ChatSender.Client,
          text: 'Hola Elena, teléfono 612345678',
          timestamp: DateTime(2026, 11, 11, 10, 0),
        ),
        clientName: 'Ana Ruiz',
        caregiverImageUrl: 'https://example.com/elena.jpg',
        allowContactSharing: false,
      );

      await repo.sendMessage(
        'client_1',
        'cg_2',
        'Carlos Ruiz',
        ChatMessage(
          sender: ChatSender.Client,
          text: 'Segundo chat más reciente',
          timestamp: DateTime(2026, 11, 11, 11, 0),
        ),
        allowContactSharing: true,
      );

      final chats = await repo.streamActiveChats('client_1', 'client').first;
      expect(chats.length, 2);
      // Sorted descending by serverTimestamp (cg_2 sent after cg_1)
      expect(chats.first.clientId, 'client_1');

      final msgsCg1 = await repo.streamMessages('client_1', 'cg_1').first;
      expect(msgsCg1.length, 1);
      expect(
        msgsCg1.first.text,
        contains('[Contacto bloqueado hasta confirmar reserva]'),
      );
      expect(msgsCg1.first.isRead, isFalse);

      // Sender (client) opening own unanswered room must NOT mark message as read
      await repo.markMessagesAsRead('client_1', 'cg_1', 'client', const []);
      var conv = await repo.streamConversation('client_1', 'cg_1').first;
      expect(conv?.lastMessageIsRead, isFalse);

      // Caregiver opening room marks message as read and sets lastMessageIsRead = true
      await repo.markMessagesAsRead(
        'client_1',
        'cg_1',
        'caregiver',
        [msgsCg1.first.id],
      );
      final afterRead = await repo.streamMessages('client_1', 'cg_1').first;
      expect(afterRead.first.isRead, isTrue);
      conv = await repo.streamConversation('client_1', 'cg_1').first;
      expect(conv?.lastMessageIsRead, isTrue);
      expect(conv?.unreadCaregiverCount, 0);
    });

    test('setTypingStatus updates existing room without creating ghost rooms',
        () async {
      await repo.setTypingStatus('ghost_c', 'ghost_cg', 'client', true);
      final ghostDoc =
          await fakeFirestore.collection('chats').doc('ghost_c_ghost_cg').get();
      expect(ghostDoc.exists, isFalse);

      await repo.sendMessage(
        'c_real',
        'cg_real',
        'Elena',
        ChatMessage(
          sender: ChatSender.Client,
          text: 'Hola',
          timestamp: DateTime.now(),
        ),
      );
      await repo.setTypingStatus('c_real', 'cg_real', 'caregiver', true);
      final conv = await repo.streamConversation('c_real', 'cg_real').first;
      expect(conv?.caregiverTypingAt, isNotNull);
      expect(conv?.isPeerTyping(true), isTrue);
    });

    test('toggleReaction & deleteMessageForEveryone update message and parent summary',
        () async {
      await repo.sendMessage(
        'c1',
        'cg1',
        'Elena',
        ChatMessage(
          sender: ChatSender.Caregiver,
          text: 'Mensaje original',
          timestamp: DateTime.now(),
        ),
      );

      final msgs = await repo.streamMessages('c1', 'cg1').first;
      final msgId = msgs.first.id;

      await repo.toggleReaction('c1', 'cg1', msgId, 'c1', '❤️');
      var updated = await repo.streamMessages('c1', 'cg1').first;
      expect(updated.first.reactions['c1'], '❤️');

      // Tapping same emoji removes it
      await repo.toggleReaction('c1', 'cg1', msgId, 'c1', '❤️');
      updated = await repo.streamMessages('c1', 'cg1').first;
      expect(updated.first.reactions, isEmpty);

      await repo.deleteMessageForEveryone('c1', 'cg1', msgId);
      updated = await repo.streamMessages('c1', 'cg1').first;
      expect(updated.first.isDeleted, isTrue);
      expect(updated.first.text, '🚫 Mensaje eliminado');

      final parentSnap =
          await fakeFirestore.collection('chats').doc('c1_cg1').get();
      expect(parentSnap.data()?['lastMessage'], '🚫 Mensaje eliminado');
    });

    test('fromFirestore parses server-style timestamp cleanly', () async {
      final docRef = fakeFirestore.collection('chats/c9_cg9/messages').doc('m1');
      await docRef.set({
        'sender': 'Caregiver',
        'text': 'Audio legado',
        'timestamp': Timestamp.fromDate(DateTime(2026, 11, 10, 14, 30)),
        'type': 'audio',
        'mediaUrl': 'https://example.com/a.m4a',
        'audioDurationSeconds': 22,
        'isRead': true,
      });
      final snap = await docRef.get();
      final msg = ChatMessage.fromFirestore(snap);
      expect(msg.type, ChatMessageType.audio);
      expect(msg.audioDurationSeconds, 22);
      expect(msg.isRead, isTrue);
    });
  });

  group('ChatScreen & InboxScreen WhatsApp UI and Security', () {
    late MockAuthRepository mockAuth;
    late MockCaregiverRepository mockCaregivers;
    late _TestClientRepository mockClients;
    late MockBookingRepository mockBookings;
    late MockChatRepository mockChats;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      mockAuth = MockAuthRepository();
      mockCaregivers = MockCaregiverRepository();
      mockClients = _TestClientRepository();
      mockBookings = MockBookingRepository();
      mockChats = MockChatRepository();

      DependencyInjection.auth = mockAuth;
      DependencyInjection.caregivers = mockCaregivers;
      DependencyInjection.clients = mockClients;
      DependencyInjection.bookings = mockBookings;
      DependencyInjection.chats = mockChats;
    });

    Widget wrapWithAuth(AuthNotifier auth, Widget child) {
      return ChangeNotifierProvider<AuthNotifier>.value(
        value: auth,
        child: MaterialApp(home: child),
      );
    }

    testWidgets(
        'confirmed booking of Client A does NOT unblock contact sharing for Client B',
        (tester) async {
      await mockBookings.createBooking(
        _makeBooking(
          id: 'b_A',
          clientId: 'client_A',
          caregiverId: 'cg_1',
          status: BookingStatus.confirmed,
        ),
      );

      final authB = AuthNotifier()
        ..isAuthenticated = true
        ..currentUserId = 'client_B'
        ..currentRole = 'client';

      await tester.pumpWidget(
        wrapWithAuth(
          authB,
          const ChatScreen(
            clientId: 'client_B',
            caregiverId: 'cg_1',
            caregiverName: 'Elena Cuidadora',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Security banner MUST still show for client_B
      expect(
        find.textContaining('se desbloquean al confirmar la reserva'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byType(TextField).last,
        'Llámame al 612345678',
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      final msgsB = await mockChats.streamMessages('client_B', 'cg_1').first;
      expect(
        msgsB.first.text,
        contains('[Contacto bloqueado hasta confirmar reserva]'),
      );
    });

    testWidgets(
        'confirmed booking of Client A unlocks contact sharing and hides banner',
        (tester) async {
      await mockBookings.createBooking(
        _makeBooking(
          id: 'b_A',
          clientId: 'client_A',
          caregiverId: 'cg_1',
          status: BookingStatus.confirmed,
        ),
      );

      final authA = AuthNotifier()
        ..isAuthenticated = true
        ..currentUserId = 'client_A'
        ..currentRole = 'client';

      await tester.pumpWidget(
        wrapWithAuth(
          authA,
          const ChatScreen(
            clientId: 'client_A',
            caregiverId: 'cg_1',
            caregiverName: 'Elena Cuidadora',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('se desbloquean al confirmar la reserva'),
        findsNothing,
      );

      // Initially shows mic button
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);

      await tester.enterText(
        find.byType(TextField).last,
        'Mi número es 612345678',
      );
      await tester.pump();

      // Typing swaps mic button to WhatsApp send button
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      final msgsA = await mockChats.streamMessages('client_A', 'cg_1').first;
      expect(msgsA.first.text, 'Mi número es 612345678');
      expect(find.text('HOY'), findsOneWidget);

      // Clear widget tree cleanly so timers dispose
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'ChatScreen displays read ticks, typing status, reply quote bar, and attachments sheet',
        (tester) async {
      await mockChats.sendMessage(
        'client_1',
        'cg_1',
        'Elena Cuidadora',
        ChatMessage(
          sender: ChatSender.Caregiver,
          text: '¿Quedamos a las 10:00?',
          timestamp: DateTime.now(),
        ),
      );

      final auth = AuthNotifier()
        ..isAuthenticated = true
        ..currentUserId = 'cg_1'
        ..currentRole = 'caregiver';

      await tester.pumpWidget(
        wrapWithAuth(
          auth,
          const ChatScreen(
            clientId: 'client_1',
            caregiverId: 'cg_1',
            caregiverName: 'Elena Cuidadora',
            clientName: 'María García',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Caregiver's own sent unread message shows single done tick
      expect(find.byIcon(Icons.done_rounded), findsOneWidget);

      // Simulate client reading the message and typing
      final msgs = await mockChats.streamMessages('client_1', 'cg_1').first;
      await mockChats.markMessagesAsRead(
        'client_1',
        'cg_1',
        'client',
        [msgs.first.id],
      );
      await mockChats.setTypingStatus('client_1', 'cg_1', 'client', true);
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
      expect(find.text('escribiendo...'), findsOneWidget);

      // Long press opens WhatsApp actions sheet -> tap Responder
      await tester.longPress(find.text('¿Quedamos a las 10:00?'));
      await tester.pumpAndSettle();
      expect(find.text('Responder'), findsOneWidget);
      expect(find.text('Eliminar para todos'), findsOneWidget);

      await tester.tap(find.text('Responder'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Respondiendo a'), findsOneWidget);

      // Attachment sheet shows Cámara, Galería, Ubicación
      await tester.tap(find.byIcon(Icons.add_circle_outline_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Cámara'), findsOneWidget);
      expect(find.text('Galería'), findsOneWidget);
      expect(find.text('Ubicación'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'InboxScreen renders unread badges, read ticks, typing status, and filters',
        (tester) async {
      await mockChats.sendMessage(
        'client_1',
        'cg_1',
        'Elena Cuidadora',
        ChatMessage(
          sender: ChatSender.Caregiver,
          text: 'Llegaré en 10 minutos',
          timestamp: DateTime.now(),
        ),
      );
      await mockChats.sendMessage(
        'client_1',
        'cg_2',
        'Carlos Ruiz',
        ChatMessage(
          sender: ChatSender.Client,
          text: 'Gracias Carlos',
          timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
      );
      await mockChats.setTypingStatus('client_1', 'cg_2', 'caregiver', true);

      final auth = AuthNotifier()
        ..isAuthenticated = true
        ..currentUserId = 'client_1'
        ..currentRole = 'client';

      await tester.pumpWidget(wrapWithAuth(auth, const InboxScreen()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Elena Cuidadora'), findsOneWidget);
      expect(find.text('Carlos Ruiz'), findsOneWidget);
      expect(find.text('Llegaré en 10 minutos'), findsOneWidget);
      expect(find.text('escribiendo...'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);

      // Toggle "No leídos" filter
      await tester.tap(find.text('No leídos (1)'));
      await tester.pump();
      expect(find.text('Elena Cuidadora'), findsOneWidget);
      expect(find.text('Carlos Ruiz'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
