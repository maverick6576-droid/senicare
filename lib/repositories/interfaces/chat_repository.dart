import 'package:senicare/models/models.dart';

abstract class ChatRepository {
  Stream<List<ChatMessage>> streamMessages(String clientId, String caregiverId, {int limit = 20});
  Future<void> sendMessage(String clientId, String caregiverId, String caregiverName, ChatMessage message);
  Stream<List<ChatConversation>> streamActiveChats(String userId, String role, {int limit = 20});
  Future<void> resetUnreadCount(String clientId, String caregiverId, String role);
}

