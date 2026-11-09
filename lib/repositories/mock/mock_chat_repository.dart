import 'dart:async';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/repositories.dart';

class MockChatRepository implements ChatRepository {
  final StreamController<List<ChatMessage>> _controller = StreamController<List<ChatMessage>>.broadcast();
  final List<ChatMessage> _messages = [
    ChatMessage(
      sender: ChatSender.Caregiver,
      text: 'Â¡Hola! Soy Elena. Â¿En qué te puedo ayudar hoy?',
      timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
    )
  ];

  @override
  Stream<List<ChatMessage>> streamMessages(String clientId, String caregiverId, {int limit = 20}) {
    Future.microtask(() => _controller.add(_messages));
    return _controller.stream;
  }

  @override
  Stream<List<ChatConversation>> streamActiveChats(String userId, String role, {int limit = 20}) async* {
    yield [];
  }

  @override
  Future<void> sendMessage(String clientId, String caregiverId, String caregiverName, ChatMessage message) async {
    _messages.add(message);
    _controller.add(List.from(_messages));
    
    // Auto-Responder Simulation (Anti-bypass handled in state before calling this)
    Future.delayed(const Duration(seconds: 3), () {
      _messages.add(ChatMessage(
        sender: ChatSender.Caregiver,
        text: 'Gracias por tu mensaje. Para poder confirmar la asistencia, por favor completa la reserva en mi calendario.',
        timestamp: DateTime.now(),
      ));
      _controller.add(List.from(_messages));
    });
  }

  @override
  Future<void> resetUnreadCount(String clientId, String caregiverId, String role) async {}
}

