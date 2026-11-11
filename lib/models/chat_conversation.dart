import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:senicare/models/chat_message.dart';

class ChatConversation {
  final String roomId;
  final String clientId;
  final String caregiverId;
  final String caregiverName;
  final String clientName;
  final String caregiverImageUrl;
  final String lastMessage;
  final DateTime lastMessageTimestamp;
  final ChatSender? lastMessageSender;
  final bool lastMessageIsRead;
  final int unreadClientCount;
  final int unreadCaregiverCount;
  final DateTime? clientTypingAt;
  final DateTime? caregiverTypingAt;

  ChatConversation({
    required this.roomId,
    required this.clientId,
    required this.caregiverId,
    required this.caregiverName,
    this.clientName = '',
    this.caregiverImageUrl = '',
    required this.lastMessage,
    required this.lastMessageTimestamp,
    this.lastMessageSender,
    this.lastMessageIsRead = false,
    this.unreadClientCount = 0,
    this.unreadCaregiverCount = 0,
    this.clientTypingAt,
    this.caregiverTypingAt,
  });

  /// Returns true when the other participant sent a typing signal in the last 6 seconds.
  bool isPeerTyping(bool viewerIsClient, {DateTime? now}) {
    final DateTime? peerTyping =
        viewerIsClient ? caregiverTypingAt : clientTypingAt;
    if (peerTyping == null) return false;
    final current = now ?? DateTime.now();
    return current.difference(peerTyping).inSeconds.abs() <= 6 &&
        !peerTyping.isAfter(current.add(const Duration(seconds: 2)));
  }

  String familyDisplayName([String? overrideName]) {
    final clean = (overrideName ?? clientName).trim();
    if (clean.isEmpty) {
      final suffix = clientId.isNotEmpty
          ? clientId.substring(0, clientId.length < 4 ? clientId.length : 4)
          : '';
      return suffix.isNotEmpty ? 'Familia ($suffix)' : 'Familia';
    }
    final parts = clean.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'Familia';
    if (parts.length == 1) return 'Familia ${parts.first}';
    return 'Familia ${parts.sublist(1).join(' ')}';
  }

  factory ChatConversation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    ChatSender? lastSender;
    if (data['lastMessageSender'] == 'Caregiver') {
      lastSender = ChatSender.Caregiver;
    } else if (data['lastMessageSender'] == 'Client') {
      lastSender = ChatSender.Client;
    }

    return ChatConversation(
      roomId: doc.id,
      clientId: data['clientId']?.toString() ?? '',
      caregiverId: data['caregiverId']?.toString() ?? '',
      caregiverName: data['caregiverName']?.toString() ?? 'Cuidador',
      clientName: data['clientName']?.toString() ?? '',
      caregiverImageUrl: data['caregiverImageUrl']?.toString() ?? '',
      lastMessage: data['lastMessage']?.toString() ?? '',
      lastMessageTimestamp:
          (data['lastMessageTimestamp'] as Timestamp?)?.toDate() ??
              DateTime.now(),
      lastMessageSender: lastSender,
      lastMessageIsRead: data['lastMessageIsRead'] == true,
      unreadClientCount: (data['unreadClientCount'] as num?)?.toInt() ?? 0,
      unreadCaregiverCount:
          (data['unreadCaregiverCount'] as num?)?.toInt() ?? 0,
      clientTypingAt: (data['clientTypingAt'] as Timestamp?)?.toDate(),
      caregiverTypingAt: (data['caregiverTypingAt'] as Timestamp?)?.toDate(),
    );
  }
}
