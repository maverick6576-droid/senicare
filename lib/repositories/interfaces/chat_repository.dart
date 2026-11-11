import 'package:senicare/models/models.dart';

abstract class ChatRepository {
  Stream<List<ChatMessage>> streamMessages(
    String clientId,
    String caregiverId, {
    int limit = 30,
  });

  Stream<ChatConversation?> streamConversation(
    String clientId,
    String caregiverId,
  );

  Future<void> sendMessage(
    String clientId,
    String caregiverId,
    String caregiverName,
    ChatMessage message, {
    String? clientName,
    String? caregiverImageUrl,
    bool allowContactSharing = false,
  });

  Stream<List<ChatConversation>> streamActiveChats(
    String userId,
    String role, {
    int limit = 30,
  });

  Future<void> resetUnreadCount(
    String clientId,
    String caregiverId,
    String role,
  );

  Future<void> markMessagesAsRead(
    String clientId,
    String caregiverId,
    String viewerRole,
    List<String> messageIds,
  );

  Future<void> setTypingStatus(
    String clientId,
    String caregiverId,
    String role,
    bool isTyping,
  );

  Future<void> toggleReaction(
    String clientId,
    String caregiverId,
    String messageId,
    String userId,
    String emoji,
  );

  Future<void> deleteMessageForEveryone(
    String clientId,
    String caregiverId,
    String messageId,
  );
}
