import 'package:flutter/material.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';
import 'package:senicare/core/core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreChatRepository implements ChatRepository {
  
  /// Analiza el texto en busca de correos electrónicos y números de teléfono.
  /// Sustituye los patrones sospechosos por un aviso de bloqueo.
  String _sanitizeMessage(String text) {
    // Patrón para correos electrónicos
    final emailRegExp = RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}');
    // Patrón para números de teléfono (ej. bloques de dígitos largos, prefijos internacionales, espacios, guiones)
    final phoneRegExp = RegExp(r'(\+?\d{1,3}[\s-]?)?(\d{3}[\s-]?\d{3}[\s-]?\d{3}|\d{9})');

    String sanitized = text.replaceAll(emailRegExp, '[Contacto Bloqueado hasta realizar reserva]');
    sanitized = sanitized.replaceAll(phoneRegExp, '[Contacto Bloqueado hasta realizar reserva]');
    return sanitized;
  }

  @override
  Stream<List<ChatConversation>> streamActiveChats(String userId, String role, {int limit = 20}) async* {
    try {
      final field = role == 'client' ? 'clientId' : 'caregiverId';
      final collection = FirebaseFirestore.instance.collection('chats');
      
      await for (var snapshot in collection.where(field, isEqualTo: userId).orderBy('lastMessageTimestamp', descending: true).limit(limit).snapshots()) {
        final docs = snapshot.docs.map((doc) => ChatConversation.fromFirestore(doc)).toList();
        docs.sort((a, b) => b.lastMessageTimestamp.compareTo(a.lastMessageTimestamp));
        yield docs;
      }
    } catch (e) {
      debugPrint('âš ï¸ Error in streamActiveChats: $e.');
      yield* const Stream.empty();
    }
  }

  // Uses a subcollection structure: chats/{roomId}/messages/{messageId}
  @override
  Stream<List<ChatMessage>> streamMessages(String clientId, String caregiverId, {int limit = 20}) async* {
    try {
      final roomId = '${clientId}_$caregiverId';
      final collection = FirebaseFirestore.instance.collection('chats/$roomId/messages');
      
      await for (var snapshot in collection.orderBy('timestamp', descending: true).limit(limit).snapshots()) {
        final messages = snapshot.docs.map((doc) => ChatMessage.fromFirestore(doc)).toList();
        yield messages;
      }
    } catch (e) {
      debugPrint('==================================================');
      debugPrint('âš ï¸ Error in streamMessages: $e');
      debugPrint('==================================================');
      yield* const Stream.empty();
    }
  }

  @override
  Future<void> sendMessage(String clientId, String caregiverId, String caregiverName, ChatMessage message) async {
    try {
      final roomId = '${clientId}_$caregiverId';
      final parentDocRef = FirebaseFirestore.instance.collection('chats').doc(roomId);
      final messagesColRef = parentDocRef.collection('messages');
      
      final sanitizedText = _sanitizeMessage(message.text);
      final safeMessage = ChatMessage(
        sender: message.sender,
        text: sanitizedText,
        timestamp: message.timestamp,
      );
      
      final batch = FirebaseFirestore.instance.batch();
      
      batch.set(parentDocRef, {
        'clientId': clientId,
        'caregiverId': caregiverId,
        'caregiverName': caregiverName,
        'lastMessage': sanitizedText,
        'lastMessageTimestamp': FieldValue.serverTimestamp(),
        if (message.sender == ChatSender.Client) 'unreadCaregiverCount': FieldValue.increment(1),
        if (message.sender == ChatSender.Caregiver) 'unreadClientCount': FieldValue.increment(1),
      }, SetOptions(merge: true));
      
      final newMessageRef = messagesColRef.doc();
      final messageData = safeMessage.toFirestore();
      messageData['timestamp'] = FieldValue.serverTimestamp();
      
      batch.set(newMessageRef, messageData);
      
      await batch.commit();

    } catch (e) {
      debugPrint('🚨 Error in sendMessage: $e.');
      rethrow;
    }
  }

  @override
  Future<void> resetUnreadCount(String clientId, String caregiverId, String role) async {
    try {
      final roomId = '${clientId}_$caregiverId';
      final parentDocRef = FirebaseFirestore.instance.collection('chats').doc(roomId);
      await parentDocRef.set({
        if (role == 'client') 'unreadClientCount': 0,
        if (role == 'caregiver') 'unreadCaregiverCount': 0,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error reseting unread count: $e');
    }
  }
}
