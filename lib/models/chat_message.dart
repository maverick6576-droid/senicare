import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum ChatSender { Client, Caregiver }

enum ChatMessageType { text, image, audio, location, call, system }

class ChatMessage {
  final String id;
  final ChatSender sender;
  final String text;
  final DateTime timestamp;
  final String? senderId;
  final String? receiverId;
  final ChatMessageType type;
  final String? mediaUrl;
  final int? audioDurationSeconds;
  final double? latitude;
  final double? longitude;
  final String? replyToMessageId;
  final String? replyToText;
  final ChatSender? replyToSender;
  final Map<String, String> reactions;
  final bool isRead;
  final DateTime? readAt;
  final bool isDeleted;
  final bool isPending;

  const ChatMessage({
    this.id = '',
    required this.sender,
    required this.text,
    required this.timestamp,
    this.senderId,
    this.receiverId,
    this.type = ChatMessageType.text,
    this.mediaUrl,
    this.audioDurationSeconds,
    this.latitude,
    this.longitude,
    this.replyToMessageId,
    this.replyToText,
    this.replyToSender,
    this.reactions = const {},
    this.isRead = false,
    this.readAt,
    this.isDeleted = false,
    this.isPending = false,
  });

  String get previewSummary {
    if (isDeleted) return '🚫 Mensaje eliminado';
    switch (type) {
      case ChatMessageType.image:
        final caption = text.trim();
        return caption.isNotEmpty && caption != '📷 Foto'
            ? '📷 $caption'
            : '📷 Foto';
      case ChatMessageType.audio:
        if (audioDurationSeconds != null && audioDurationSeconds! > 0) {
          final mins = audioDurationSeconds! ~/ 60;
          final secs = (audioDurationSeconds! % 60).toString().padLeft(2, '0');
          return '🎤 Nota de voz ($mins:$secs)';
        }
        return text.trim().isNotEmpty ? text : '🎤 Nota de voz';
      case ChatMessageType.location:
        return '📍 Ubicación compartida';
      case ChatMessageType.call:
        return '📹 Videollamada de entrevista';
      case ChatMessageType.system:
      case ChatMessageType.text:
        return text;
    }
  }

  ChatMessage copyWith({
    String? id,
    ChatSender? sender,
    String? text,
    DateTime? timestamp,
    String? senderId,
    String? receiverId,
    ChatMessageType? type,
    String? mediaUrl,
    int? audioDurationSeconds,
    double? latitude,
    double? longitude,
    String? replyToMessageId,
    String? replyToText,
    ChatSender? replyToSender,
    Map<String, String>? reactions,
    bool? isRead,
    DateTime? readAt,
    bool? isDeleted,
    bool? isPending,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      sender: sender ?? this.sender,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      type: type ?? this.type,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      audioDurationSeconds: audioDurationSeconds ?? this.audioDurationSeconds,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      replyToText: replyToText ?? this.replyToText,
      replyToSender: replyToSender ?? this.replyToSender,
      reactions: reactions ?? this.reactions,
      isRead: isRead ?? this.isRead,
      readAt: readAt ?? this.readAt,
      isDeleted: isDeleted ?? this.isDeleted,
      isPending: isPending ?? this.isPending,
    );
  }

  static ChatMessageType _parseType(String? rawType, String text) {
    switch (rawType) {
      case 'image':
        return ChatMessageType.image;
      case 'audio':
        return ChatMessageType.audio;
      case 'location':
        return ChatMessageType.location;
      case 'call':
        return ChatMessageType.call;
      case 'system':
        return ChatMessageType.system;
      case 'text':
        return ChatMessageType.text;
    }
    if (text.startsWith('🎤 Nota de voz')) return ChatMessageType.audio;
    if (text.startsWith('📹')) return ChatMessageType.call;
    return ChatMessageType.text;
  }

  static String typeToString(ChatMessageType type) {
    return type.name;
  }

  factory ChatMessage.fromFirestore(DocumentSnapshot doc) {
    try {
      final Map<String, dynamic> data =
          doc.data() as Map<String, dynamic>? ?? {};
      final rawText = data['text']?.toString() ?? '';
      final rawReactions = data['reactions'];
      final Map<String, String> parsedReactions = {};
      if (rawReactions is Map) {
        rawReactions.forEach((k, v) {
          if (k != null && v != null) {
            parsedReactions[k.toString()] = v.toString();
          }
        });
      }

      ChatSender? replySender;
      if (data['replyToSender'] == 'Caregiver') {
        replySender = ChatSender.Caregiver;
      } else if (data['replyToSender'] == 'Client') {
        replySender = ChatSender.Client;
      }

      bool pendingWrites = false;
      try {
        pendingWrites = doc.metadata.hasPendingWrites;
      } catch (_) {}

      return ChatMessage(
        id: doc.id,
        sender: data['sender'] == 'Caregiver'
            ? ChatSender.Caregiver
            : ChatSender.Client,
        text: rawText,
        timestamp: (data['timestamp'] is Timestamp)
            ? (data['timestamp'] as Timestamp).toDate()
            : DateTime.now(),
        senderId: data['senderId']?.toString(),
        receiverId: data['receiverId']?.toString(),
        type: _parseType(data['type']?.toString(), rawText),
        mediaUrl: data['mediaUrl']?.toString(),
        audioDurationSeconds: data['audioDurationSeconds'] != null
            ? (data['audioDurationSeconds'] as num).toInt()
            : null,
        latitude: data['latitude'] != null
            ? (data['latitude'] as num).toDouble()
            : null,
        longitude: data['longitude'] != null
            ? (data['longitude'] as num).toDouble()
            : null,
        replyToMessageId: data['replyToMessageId']?.toString(),
        replyToText: data['replyToText']?.toString(),
        replyToSender: replySender,
        reactions: parsedReactions,
        isRead: data['isRead'] == true,
        readAt: (data['readAt'] is Timestamp)
            ? (data['readAt'] as Timestamp).toDate()
            : null,
        isDeleted: data['isDeleted'] == true,
        isPending: pendingWrites,
      );
    } catch (e) {
      debugPrint('Error parsing ChatMessage ${doc.id}: $e');
      return ChatMessage(
        id: doc.id,
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
      'type': typeToString(type),
      'isRead': isRead,
      'isDeleted': isDeleted,
      if (senderId != null) 'senderId': senderId,
      if (receiverId != null) 'receiverId': receiverId,
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
      if (audioDurationSeconds != null)
        'audioDurationSeconds': audioDurationSeconds,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
      if (replyToText != null) 'replyToText': replyToText,
      if (replyToSender != null)
        'replyToSender':
            replyToSender == ChatSender.Caregiver ? 'Caregiver' : 'Client',
      if (reactions.isNotEmpty) 'reactions': reactions,
      if (readAt != null) 'readAt': Timestamp.fromDate(readAt!),
    };
  }
}
