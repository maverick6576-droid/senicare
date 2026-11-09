import 'package:cloud_firestore/cloud_firestore.dart';

class ChatConversation {
  final String roomId;
  final String clientId;
  final String caregiverId;
  final String caregiverName;
  final String lastMessage;
  final DateTime lastMessageTimestamp;
  final int unreadClientCount;
  final int unreadCaregiverCount;

  ChatConversation({
    required this.roomId,
    required this.clientId,
    required this.caregiverId,
    required this.caregiverName,
    required this.lastMessage,
    required this.lastMessageTimestamp,
    this.unreadClientCount = 0,
    this.unreadCaregiverCount = 0,
  });

  factory ChatConversation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return ChatConversation(
      roomId: doc.id,
      clientId: data['clientId'] ?? '',
      caregiverId: data['caregiverId'] ?? '',
      caregiverName: data['caregiverName'] ?? 'Cuidador',
      lastMessage: data['lastMessage'] ?? '',
      lastMessageTimestamp: (data['lastMessageTimestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      unreadClientCount: data['unreadClientCount'] ?? 0,
      unreadCaregiverCount: data['unreadCaregiverCount'] ?? 0,
    );
  }
}
