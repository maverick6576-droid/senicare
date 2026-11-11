import 'dart:async';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';

class MockChatRepository implements ChatRepository {
  final Map<String, List<ChatMessage>> _messagesByRoom = {};
  final Map<String, ChatConversation> _conversations = {};
  final Map<String, StreamController<List<ChatMessage>>> _messageControllers =
      {};
  final Map<String, StreamController<ChatConversation?>>
      _conversationControllers = {};
  final StreamController<void> _activeChatsController =
      StreamController<void>.broadcast();
  int _idCounter = 0;

  String _roomId(String clientId, String caregiverId) =>
      FirestoreChatRepository.roomIdFor(clientId, caregiverId);

  List<ChatMessage> _sortedMessages(String roomId) {
    final list = List<ChatMessage>.from(_messagesByRoom[roomId] ?? const []);
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  void _emitRoom(String roomId) {
    final msgCtrl = _messageControllers[roomId];
    if (msgCtrl != null && !msgCtrl.isClosed) {
      msgCtrl.add(_sortedMessages(roomId));
    }
    final convCtrl = _conversationControllers[roomId];
    if (convCtrl != null && !convCtrl.isClosed) {
      convCtrl.add(_conversations[roomId]);
    }
    if (!_activeChatsController.isClosed) {
      _activeChatsController.add(null);
    }
  }

  List<ChatConversation> _chatsFor(String userId, String role, int limit) {
    final list = _conversations.values.where((c) {
      return role == 'client' ? c.clientId == userId : c.caregiverId == userId;
    }).toList();
    list.sort(
      (a, b) => b.lastMessageTimestamp.compareTo(a.lastMessageTimestamp),
    );
    if (list.length > limit) return list.sublist(0, limit);
    return list;
  }

  @override
  Stream<List<ChatMessage>> streamMessages(
    String clientId,
    String caregiverId, {
    int limit = 30,
  }) async* {
    final roomId = _roomId(clientId, caregiverId);
    final ctrl = _messageControllers.putIfAbsent(
      roomId,
      () => StreamController<List<ChatMessage>>.broadcast(),
    );

    final initial = _sortedMessages(roomId);
    yield initial.length > limit ? initial.sublist(0, limit) : initial;

    await for (final list in ctrl.stream) {
      yield list.length > limit ? list.sublist(0, limit) : list;
    }
  }

  @override
  Stream<ChatConversation?> streamConversation(
    String clientId,
    String caregiverId,
  ) async* {
    final roomId = _roomId(clientId, caregiverId);
    final ctrl = _conversationControllers.putIfAbsent(
      roomId,
      () => StreamController<ChatConversation?>.broadcast(),
    );
    yield _conversations[roomId];
    yield* ctrl.stream;
  }

  @override
  Stream<List<ChatConversation>> streamActiveChats(
    String userId,
    String role, {
    int limit = 30,
  }) async* {
    yield _chatsFor(userId, role, limit);
    await for (final _ in _activeChatsController.stream) {
      yield _chatsFor(userId, role, limit);
    }
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
    final roomId = _roomId(clientId, caregiverId);
    final shouldSanitize = message.type == ChatMessageType.text ||
        message.type == ChatMessageType.image;
    final cleanText = shouldSanitize
        ? FirestoreChatRepository.sanitizeMessageText(
            message.text,
            allowContactSharing: allowContactSharing,
          )
        : message.text;

    final generatedId =
        message.id.isNotEmpty ? message.id : 'mock_msg_${++_idCounter}';
    final stored = message.copyWith(
      id: generatedId,
      text: cleanText,
      senderId: message.senderId ??
          (message.sender == ChatSender.Client ? clientId : caregiverId),
      receiverId: message.receiverId ??
          (message.sender == ChatSender.Client ? caregiverId : clientId),
      isRead: false,
      isDeleted: false,
      isPending: false,
    );

    _messagesByRoom.putIfAbsent(roomId, () => []).add(stored);

    final prev = _conversations[roomId];
    _conversations[roomId] = ChatConversation(
      roomId: roomId,
      clientId: clientId,
      caregiverId: caregiverId,
      caregiverName: caregiverName,
      clientName: (clientName != null && clientName.trim().isNotEmpty)
          ? clientName.trim()
          : (prev?.clientName ?? ''),
      caregiverImageUrl:
          (caregiverImageUrl != null && caregiverImageUrl.trim().isNotEmpty)
              ? caregiverImageUrl.trim()
              : (prev?.caregiverImageUrl ?? ''),
      lastMessage: stored.previewSummary,
      lastMessageTimestamp: stored.timestamp,
      lastMessageSender: stored.sender,
      lastMessageIsRead: false,
      unreadClientCount: stored.sender == ChatSender.Caregiver
          ? (prev?.unreadClientCount ?? 0) + 1
          : (prev?.unreadClientCount ?? 0),
      unreadCaregiverCount: stored.sender == ChatSender.Client
          ? (prev?.unreadCaregiverCount ?? 0) + 1
          : (prev?.unreadCaregiverCount ?? 0),
      clientTypingAt:
          stored.sender == ChatSender.Client ? null : prev?.clientTypingAt,
      caregiverTypingAt: stored.sender == ChatSender.Caregiver
          ? null
          : prev?.caregiverTypingAt,
    );

    _emitRoom(roomId);
  }

  @override
  Future<void> resetUnreadCount(
    String clientId,
    String caregiverId,
    String role,
  ) async {
    final roomId = _roomId(clientId, caregiverId);
    final prev = _conversations[roomId];
    if (prev == null) return;
    _conversations[roomId] = ChatConversation(
      roomId: prev.roomId,
      clientId: prev.clientId,
      caregiverId: prev.caregiverId,
      caregiverName: prev.caregiverName,
      clientName: prev.clientName,
      caregiverImageUrl: prev.caregiverImageUrl,
      lastMessage: prev.lastMessage,
      lastMessageTimestamp: prev.lastMessageTimestamp,
      lastMessageSender: prev.lastMessageSender,
      lastMessageIsRead: prev.lastMessageIsRead,
      unreadClientCount: role == 'client' ? 0 : prev.unreadClientCount,
      unreadCaregiverCount: role == 'caregiver' ? 0 : prev.unreadCaregiverCount,
      clientTypingAt: prev.clientTypingAt,
      caregiverTypingAt: prev.caregiverTypingAt,
    );
    _emitRoom(roomId);
  }

  @override
  Future<void> markMessagesAsRead(
    String clientId,
    String caregiverId,
    String viewerRole,
    List<String> messageIds,
  ) async {
    final roomId = _roomId(clientId, caregiverId);
    final list = _messagesByRoom[roomId];
    if (list != null) {
      final now = DateTime.now();
      final idSet = messageIds.toSet();
      for (var i = 0; i < list.length; i++) {
        if (idSet.contains(list[i].id) && !list[i].isRead) {
          list[i] = list[i].copyWith(isRead: true, readAt: now);
        }
      }
    }

    final prev = _conversations[roomId];
    if (prev != null) {
      final viewerSender =
          viewerRole == 'client' ? ChatSender.Client : ChatSender.Caregiver;
      final shouldMarkLastRead = messageIds.isNotEmpty ||
          (prev.lastMessageSender != null &&
              prev.lastMessageSender != viewerSender);
      _conversations[roomId] = ChatConversation(
        roomId: prev.roomId,
        clientId: prev.clientId,
        caregiverId: prev.caregiverId,
        caregiverName: prev.caregiverName,
        clientName: prev.clientName,
        caregiverImageUrl: prev.caregiverImageUrl,
        lastMessage: prev.lastMessage,
        lastMessageTimestamp: prev.lastMessageTimestamp,
        lastMessageSender: prev.lastMessageSender,
        lastMessageIsRead:
            shouldMarkLastRead ? true : prev.lastMessageIsRead,
        unreadClientCount:
            viewerRole == 'client' ? 0 : prev.unreadClientCount,
        unreadCaregiverCount:
            viewerRole == 'caregiver' ? 0 : prev.unreadCaregiverCount,
        clientTypingAt: prev.clientTypingAt,
        caregiverTypingAt: prev.caregiverTypingAt,
      );
    }
    _emitRoom(roomId);
  }

  @override
  Future<void> setTypingStatus(
    String clientId,
    String caregiverId,
    String role,
    bool isTyping,
  ) async {
    final roomId = _roomId(clientId, caregiverId);
    final prev = _conversations[roomId];
    if (prev == null) return;
    final now = DateTime.now();
    _conversations[roomId] = ChatConversation(
      roomId: prev.roomId,
      clientId: prev.clientId,
      caregiverId: prev.caregiverId,
      caregiverName: prev.caregiverName,
      clientName: prev.clientName,
      caregiverImageUrl: prev.caregiverImageUrl,
      lastMessage: prev.lastMessage,
      lastMessageTimestamp: prev.lastMessageTimestamp,
      lastMessageSender: prev.lastMessageSender,
      lastMessageIsRead: prev.lastMessageIsRead,
      unreadClientCount: prev.unreadClientCount,
      unreadCaregiverCount: prev.unreadCaregiverCount,
      clientTypingAt: role == 'client'
          ? (isTyping ? now : null)
          : prev.clientTypingAt,
      caregiverTypingAt: role == 'caregiver'
          ? (isTyping ? now : null)
          : prev.caregiverTypingAt,
    );
    _emitRoom(roomId);
  }

  @override
  Future<void> toggleReaction(
    String clientId,
    String caregiverId,
    String messageId,
    String userId,
    String emoji,
  ) async {
    final roomId = _roomId(clientId, caregiverId);
    final list = _messagesByRoom[roomId];
    if (list == null) return;
    final idx = list.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;
    final current = Map<String, String>.from(list[idx].reactions);
    if (current[userId] == emoji) {
      current.remove(userId);
    } else {
      current[userId] = emoji;
    }
    list[idx] = list[idx].copyWith(reactions: current);
    _emitRoom(roomId);
  }

  @override
  Future<void> deleteMessageForEveryone(
    String clientId,
    String caregiverId,
    String messageId,
  ) async {
    final roomId = _roomId(clientId, caregiverId);
    final list = _messagesByRoom[roomId];
    if (list == null) return;
    final idx = list.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;
    list[idx] = ChatMessage(
      id: list[idx].id,
      sender: list[idx].sender,
      text: '🚫 Mensaje eliminado',
      timestamp: list[idx].timestamp,
      senderId: list[idx].senderId,
      receiverId: list[idx].receiverId,
      type: ChatMessageType.text,
      isRead: list[idx].isRead,
      readAt: list[idx].readAt,
      isDeleted: true,
    );
    final sorted = _sortedMessages(roomId);
    final prev = _conversations[roomId];
    if (prev != null && sorted.isNotEmpty && sorted.first.id == messageId) {
      _conversations[roomId] = ChatConversation(
        roomId: prev.roomId,
        clientId: prev.clientId,
        caregiverId: prev.caregiverId,
        caregiverName: prev.caregiverName,
        clientName: prev.clientName,
        caregiverImageUrl: prev.caregiverImageUrl,
        lastMessage: '🚫 Mensaje eliminado',
        lastMessageTimestamp: prev.lastMessageTimestamp,
        lastMessageSender: prev.lastMessageSender,
        lastMessageIsRead: prev.lastMessageIsRead,
        unreadClientCount: prev.unreadClientCount,
        unreadCaregiverCount: prev.unreadCaregiverCount,
        clientTypingAt: prev.clientTypingAt,
        caregiverTypingAt: prev.caregiverTypingAt,
      );
    }
    _emitRoom(roomId);
  }
}
