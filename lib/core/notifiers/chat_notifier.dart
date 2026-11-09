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
    notifyListeners();
  }

  @override
  void dispose() {
    _chatsSubscription?.cancel();
    super.dispose();
  }
}
