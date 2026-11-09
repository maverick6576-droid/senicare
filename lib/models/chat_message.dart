import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum ChatSender { Client, Caregiver }


class ChatMessage {
  final ChatSender sender;
  final String text;
  final DateTime timestamp;

  ChatMessage({
    required this.sender,
    required this.text,
    required this.timestamp,
  });

  factory ChatMessage.fromFirestore(DocumentSnapshot doc) {
    try {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>? ?? {};
      return ChatMessage(
        sender: data['sender'] == 'Caregiver' ? ChatSender.Caregiver : ChatSender.Client,
        text: data['text']?.toString() ?? '',
        timestamp: (data['timestamp'] is Timestamp)
            ? (data['timestamp'] as Timestamp).toDate()
            : DateTime.now(),
      );
    } catch (e) {
      debugPrint('Error parsing ChatMessage ${doc.id}: $e');
      return ChatMessage(
        sender: ChatSender.Caregiver,
        text: '⚠️ Mensaje corrupto',
        timestamp: DateTime.now(),
      );
    }
  }

  Map<String, dynamic> toFirestore() {
    return {
      'sender': sender == ChatSender.Caregiver ? 'Caregiver' : 'Client',
      'text': text,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }
}
