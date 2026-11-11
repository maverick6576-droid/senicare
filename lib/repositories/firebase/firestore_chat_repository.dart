import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';

class FirestoreChatRepository implements ChatRepository {
  final FirebaseFirestore _firestore;

  FirestoreChatRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static String roomIdFor(String clientId, String caregiverId) =>
      '${clientId}_$caregiverId';

  static final RegExp _emailRegExp = RegExp(
    r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
  );

  static final RegExp _phoneRegExp = RegExp(
    r'(\+?\d{1,3}[\s.-]?)?(\d{3}[\s.-]?\d{3}[\s.-]?\d{3}|\d{9,12})',
  );

  /// Sanitizes phone numbers and email addresses before a booking is confirmed.
  static String sanitizeMessageText(
    String text, {
    bool allowContactSharing = false,
  }) {
    if (allowContactSharing) return text;
    var sanitized = text.replaceAll(
      _emailRegExp,
      '[Contacto bloqueado hasta confirmar reserva]',
    );
    sanitized = sanitized.replaceAll(
      _phoneRegExp,
      '[Contacto bloqueado hasta confirmar reserva]',
    );
    return sanitized;
  }

  @override
  Stream<List<ChatConversation>> streamActiveChats(
    String userId,
    String role, {
    int limit = 30,
  }) {
    if (userId.isEmpty) return Stream.value(const []);
    final field = role == 'client' ? 'clientId' : 'caregiverId';
    // Single-field where without Firestore composite orderBy avoids failed-precondition
    // errors when composite indexes are not deployed yet.
    return _firestore
        .collection('chats')
        .where(field, isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      final docs = snapshot.docs
          .where((doc) {
            final data = doc.data();
            final lastMsg = data['lastMessage']?.toString() ?? '';
            return lastMsg.isNotEmpty ||
                data['lastMessageTimestamp'] != null;
          })
          .map((doc) => ChatConversation.fromFirestore(doc))
          .toList();
      docs.sort(
        (a, b) => b.lastMessageTimestamp.compareTo(a.lastMessageTimestamp),
      );
      if (docs.length > limit) {
        return docs.sublist(0, limit);
      }
      return docs;
    });
  }

  @override
  Stream<ChatConversation?> streamConversation(
    String clientId,
    String caregiverId,
  ) {
    final roomId = roomIdFor(clientId, caregiverId);
    return _firestore
        .collection('chats')
        .doc(roomId)
        .snapshots()
        .map((doc) => doc.exists ? ChatConversation.fromFirestore(doc) : null);
  }

  @override
  Stream<List<ChatMessage>> streamMessages(
    String clientId,
    String caregiverId, {
    int limit = 30,
  }) {
    final roomId = roomIdFor(clientId, caregiverId);
    return _firestore
        .collection('chats/$roomId/messages')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => ChatMessage.fromFirestore(doc)).toList());
  }

  @override
  Future<void> sendMessage(
    String clientId,
    String caregiverId,
    String caregiverName,
    ChatMessage message, {
    String? clientName,
    String? caregiverImageUrl,
    bool allowContactSharing = false,
  }) async {
    try {
      final roomId = roomIdFor(clientId, caregiverId);
      final parentDocRef = _firestore.collection('chats').doc(roomId);
      final messagesColRef = parentDocRef.collection('messages');

      final shouldSanitize = message.type == ChatMessageType.text ||
          message.type == ChatMessageType.image;
      final cleanText = shouldSanitize
          ? sanitizeMessageText(
              message.text,
              allowContactSharing: allowContactSharing,
            )
          : message.text;

      final senderId = message.senderId ??
          (message.sender == ChatSender.Client ? clientId : caregiverId);
      final receiverId = message.receiverId ??
          (message.sender == ChatSender.Client ? caregiverId : clientId);

      final safeMessage = message.copyWith(
        text: cleanText,
        senderId: senderId,
        receiverId: receiverId,
        isRead: false,
        isDeleted: false,
      );

      final batch = _firestore.batch();

      final Map<String, dynamic> parentUpdate = {
        'clientId': clientId,
        'caregiverId': caregiverId,
        'caregiverName': caregiverName,
        'lastMessage': safeMessage.previewSummary,
        'lastMessageTimestamp': FieldValue.serverTimestamp(),
        'lastMessageSender':
            message.sender == ChatSender.Caregiver ? 'Caregiver' : 'Client',
        'lastMessageIsRead': false,
        if (message.sender == ChatSender.Client) ...{
          'unreadCaregiverCount': FieldValue.increment(1),
          'clientTypingAt': null,
        },
        if (message.sender == ChatSender.Caregiver) ...{
          'unreadClientCount': FieldValue.increment(1),
          'caregiverTypingAt': null,
        },
      };

      if (clientName != null && clientName.trim().isNotEmpty) {
        parentUpdate['clientName'] = clientName.trim();
      }
      if (caregiverImageUrl != null && caregiverImageUrl.trim().isNotEmpty) {
        parentUpdate['caregiverImageUrl'] = caregiverImageUrl.trim();
      }

      batch.set(parentDocRef, parentUpdate, SetOptions(merge: true));

      final newMessageRef = messagesColRef.doc();
      final messageData = safeMessage.toFirestore();
      messageData['timestamp'] = FieldValue.serverTimestamp();
      batch.set(newMessageRef, messageData);

      await batch.commit();
    } catch (e) {
      debugPrint('Error in sendMessage: $e');
      rethrow;
    }
  }

  @override
  Future<void> resetUnreadCount(
    String clientId,
    String caregiverId,
    String role,
  ) async {
    try {
      final roomId = roomIdFor(clientId, caregiverId);
      final parentDocRef = _firestore.collection('chats').doc(roomId);
      await parentDocRef.set({
        if (role == 'client') 'unreadClientCount': 0,
        if (role == 'caregiver') 'unreadCaregiverCount': 0,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error resetting unread count: $e');
    }
  }

  @override
  Future<void> markMessagesAsRead(
    String clientId,
    String caregiverId,
    String viewerRole,
    List<String> messageIds,
  ) async {
    try {
      final roomId = roomIdFor(clientId, caregiverId);
      final parentDocRef = _firestore.collection('chats').doc(roomId);
      final batch = _firestore.batch();

      for (final msgId in messageIds) {
        if (msgId.isEmpty) continue;
        final msgRef = parentDocRef.collection('messages').doc(msgId);
        batch.update(msgRef, {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
        });
      }

      final parentSnap = await parentDocRef.get();
      if (parentSnap.exists) {
        final data = parentSnap.data() ?? {};
        final unreadField =
            viewerRole == 'client' ? 'unreadClientCount' : 'unreadCaregiverCount';
        final viewerSender = viewerRole == 'client' ? 'Client' : 'Caregiver';
        final lastSender = data['lastMessageSender']?.toString();

        final Map<String, dynamic> parentUpdates = {
          unreadField: 0,
        };
        if (messageIds.isNotEmpty ||
            (lastSender != null && lastSender != viewerSender)) {
          parentUpdates['lastMessageIsRead'] = true;
        }
        batch.update(parentDocRef, parentUpdates);
      }

      await batch.commit();
    } catch (e) {
      debugPrint('Error marking messages as read: $e');
    }
  }

  @override
  Future<void> setTypingStatus(
    String clientId,
    String caregiverId,
    String role,
    bool isTyping,
  ) async {
    try {
      final roomId = roomIdFor(clientId, caregiverId);
      final field = role == 'client' ? 'clientTypingAt' : 'caregiverTypingAt';
      await _firestore.collection('chats').doc(roomId).update({
        field: isTyping ? FieldValue.serverTimestamp() : null,
      });
    } catch (_) {
      // Room may not exist yet before the first message; ignore safely.
    }
  }

  @override
  Future<void> toggleReaction(
    String clientId,
    String caregiverId,
    String messageId,
    String userId,
    String emoji,
  ) async {
    if (messageId.isEmpty || userId.isEmpty) return;
    final roomId = roomIdFor(clientId, caregiverId);
    final msgRef = _firestore
        .collection('chats')
        .doc(roomId)
        .collection('messages')
        .doc(messageId);

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(msgRef);
      if (!snap.exists) return;
      final data = snap.data() ?? {};
      final rawReactions = data['reactions'];
      final Map<String, String> updated = {};
      if (rawReactions is Map) {
        rawReactions.forEach((k, v) {
          if (k != null && v != null) {
            updated[k.toString()] = v.toString();
          }
        });
      }
      final bool removing = updated[userId] == emoji;
      if (removing) {
        updated.remove(userId);
        if (updated.isEmpty) {
          tx.update(msgRef, {'reactions': FieldValue.delete()});
        } else if (!userId.contains('.')) {
          tx.update(msgRef, {'reactions.$userId': FieldValue.delete()});
        } else {
          tx.update(msgRef, {'reactions': updated});
        }
      } else {
        updated[userId] = emoji;
        if (!userId.contains('.')) {
          tx.update(msgRef, {'reactions.$userId': emoji});
        } else {
          tx.update(msgRef, {'reactions': updated});
        }
      }
    });
  }

  @override
  Future<void> deleteMessageForEveryone(
    String clientId,
    String caregiverId,
    String messageId,
  ) async {
    if (messageId.isEmpty) return;
    final roomId = roomIdFor(clientId, caregiverId);
    final parentDocRef = _firestore.collection('chats').doc(roomId);
    final msgRef = parentDocRef.collection('messages').doc(messageId);

    await msgRef.update({
      'isDeleted': true,
      'text': '🚫 Mensaje eliminado',
      'type': 'text',
      'mediaUrl': FieldValue.delete(),
      'reactions': FieldValue.delete(),
    });

    final latest = await parentDocRef
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();
    if (latest.docs.isNotEmpty && latest.docs.first.id == messageId) {
      await parentDocRef.update({
        'lastMessage': '🚫 Mensaje eliminado',
      });
    }
  }
}
