import 'dart:async';
import 'package:flutter/material.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/core/core.dart';

class ChatNotifier extends ChangeNotifier {
  List<ChatMessage> chatMessages = [];
  StreamSubscription? _chatsSubscription;

  String? _currentUserId;
  String? _currentRole;

  void updateAuth(String? userId, String? role) {
    if (_currentUserId != userId || _currentRole != role) {
      _currentUserId = userId;
      _currentRole = role;
      _subscribeToChats();
    }
  }

  void _subscribeToChats() {
    _chatsSubscription?.cancel();
    chatMessages.clear();

    if (_currentUserId == null || _currentRole == null || _currentRole == 'admin') {
      notifyListeners();
      return;
    }

    String effectiveUserId = _currentUserId!;

    // MVP: Suscribirse a un chat por defecto
    _chatsSubscription = DependencyInjection.chats.streamMessages(effectiveUserId, 'c1').listen((data) {
      chatMessages = data;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _chatsSubscription?.cancel();
    super.dispose();
  }
}
