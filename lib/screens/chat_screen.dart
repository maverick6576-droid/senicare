import 'dart:async';
import 'dart:math';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/widgets/widgets.dart';

class ChatScreen extends StatefulWidget {
  final String clientId;
  final String caregiverId;
  final String caregiverName;
  
  const ChatScreen({
    super.key,
    required this.clientId,
    required this.caregiverId,
    required this.caregiverName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  int _limit = 20;
  bool _isRecordingVoice = false;
  int _recordingSeconds = 0;
  Timer? _recordTimer;
  String? _playingMessageId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = context.read<AuthNotifier>();
      DependencyInjection.chats.resetUnreadCount(widget.clientId, widget.caregiverId, auth.currentRole);
    });
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _toggleVoiceRecording(bool isClient) {
    HapticFeedback.mediumImpact();
    if (_isRecordingVoice) {
      _recordTimer?.cancel();
      final duration = _recordingSeconds.clamp(1, 120);
      final mins = (duration ~/ 60).toString();
      final secs = (duration % 60).toString().padLeft(2, '0');
      setState(() {
        _isRecordingVoice = false;
        _recordingSeconds = 0;
      });
      final message = ChatMessage(
        sender: isClient ? ChatSender.Client : ChatSender.Caregiver,
        text: '🎤 Nota de voz ($mins:$secs)',
        timestamp: DateTime.now(),
      );
      DependencyInjection.chats.sendMessage(
        widget.clientId,
        widget.caregiverId,
        widget.caregiverName,
        message,
      );
    } else {
      setState(() {
        _isRecordingVoice = true;
        _recordingSeconds = 0;
      });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() => _recordingSeconds++);
        }
      });
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      setState(() {
        _limit += 20;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthNotifier>();
    final isClient = auth.currentRole == 'client';

    return Scaffold(
      appBar: AppBar(
          title: isClient
            ? Text('Chat con ${widget.caregiverName}')
            : FutureBuilder<ClientProfile?>(
                future: DependencyInjection.clients.getClient(widget.clientId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return const Text('Chat con Familia: ...');
                  final clientName = snapshot.data?.name ?? '';
                  final nameParts = clientName.trim().split(RegExp(r'\s+'));
                  final surname = nameParts.length > 1 ? nameParts[1] : clientName;
                  final displayName = surname.isNotEmpty ? surname : widget.clientId.substring(0, min(4, widget.clientId.length));
                  return Text('Chat con Familia: $displayName');
                }
              ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: TextButton.icon(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  final message = ChatMessage(
                    sender: isClient ? ChatSender.Client : ChatSender.Caregiver,
                    text: '📹 Ha iniciado una sala de entrevista por videollamada (15 min gratis)',
                    timestamp: DateTime.now(),
                  );
                  DependencyInjection.chats.sendMessage(
                    widget.clientId,
                    widget.caregiverId,
                    widget.caregiverName,
                    message,
                  );
                  VideoCallModal.show(
                    context,
                    participantName: isClient ? widget.caregiverName : 'Familia',
                    isCaregiver: !isClient,
                  );
                },
                icon: const Icon(Icons.videocam_rounded, color: AppTheme.primary),
                label: const Text(
                  'Entrevista 15m',
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      body: Column(
        children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.orange.shade50,
          child: const Row(
            children: [
              Icon(Icons.shield, color: Colors.orange),
              SizedBox(width: 8),
              Expanded(child: Text('Recuerda: Los pagos fuera de SeniCare anulan tu Seguro de Responsabilidad Civil de 500.000€ y la garantía de sustitución por bajas.', style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold))),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<ChatMessage>>(
            stream: DependencyInjection.chats.streamMessages(widget.clientId, widget.caregiverId, limit: _limit),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return const Center(child: Text('Error al cargar mensajes'));
              }
              
              final messages = snapshot.data ?? [];
              
              return ListView.builder(
                controller: _scrollController,
                reverse: true, // Newest messages at bottom
                padding: const EdgeInsets.all(16),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final m = messages[index];
                  final isMe = isClient ? m.sender == ChatSender.Client : m.sender == ChatSender.Caregiver;
                  final isVoiceNote = m.text.startsWith('🎤 Nota de voz');
                  final msgKey = '${m.timestamp.millisecondsSinceEpoch}_$index';
                  final isPlaying = _playingMessageId == msgKey;

                  return Align(
                    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isMe ? AppTheme.primary : Colors.white,
                        borderRadius: BorderRadius.circular(16).copyWith(
                          bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(16),
                          bottomLeft: !isMe ? const Radius.circular(0) : const Radius.circular(16),
                        ),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))],
                      ),
                      child: isVoiceNote
                          ? InkWell(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  _playingMessageId = isPlaying ? null : msgKey;
                                });
                                if (!isPlaying) {
                                  Future.delayed(const Duration(seconds: 3), () {
                                    if (mounted && _playingMessageId == msgKey) {
                                      setState(() => _playingMessageId = null);
                                    }
                                  });
                                }
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                                    color: isMe ? Colors.white : AppTheme.primary,
                                    size: 28,
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        m.text,
                                        style: TextStyle(
                                          color: isMe ? Colors.white : AppTheme.darkSlate,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      SizedBox(
                                        width: 110,
                                        child: LinearProgressIndicator(
                                          value: isPlaying ? null : 1.0,
                                          backgroundColor: isMe ? Colors.white24 : Colors.grey.shade200,
                                          valueColor: AlwaysStoppedAnimation<Color>(
                                            isMe ? Colors.white : AppTheme.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            )
                          : Text(m.text, style: TextStyle(color: isMe ? Colors.white : AppTheme.darkSlate)),
                    ),
                  );
                },
              );
            }
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16).copyWith(bottom: 32),
          decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))]),
          child: Row(
            children: [
              IconButton(
                onPressed: () => _toggleVoiceRecording(isClient),
                style: IconButton.styleFrom(
                  backgroundColor: _isRecordingVoice ? Colors.red.shade100 : AppTheme.primarySurface,
                ),
                tooltip: _isRecordingVoice ? 'Detener y enviar nota de voz' : 'Grabar nota de voz',
                icon: Icon(
                  _isRecordingVoice ? Icons.stop_rounded : Icons.mic_rounded,
                  color: _isRecordingVoice ? Colors.red.shade700 : AppTheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _isRecordingVoice
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.fiber_manual_record_rounded, color: Colors.red.shade700, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Grabando nota de voz... 0:${_recordingSeconds.toString().padLeft(2, '0')} (toca Stop para enviar)',
                                style: TextStyle(
                                  color: Colors.red.shade800,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                          hintText: 'Escribe un mensaje o graba un audio...',
                          filled: true,
                          fillColor: AppTheme.backgroundNeutral,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                radius: 24,
                backgroundColor: AppTheme.primary,
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: () {
                    if (_isRecordingVoice) {
                      _toggleVoiceRecording(isClient);
                      return;
                    }
                    final text = _controller.text.trim();
                    if (text.isNotEmpty) {
                      // RegEx anti-fuga
                      final leakRegExp = RegExp(r'(bizum|efectivo|whatsapp|@|\+34|\b[679][0-9]{8}\b|tlf|telefono|teléfono)', caseSensitive: false);
                      if (leakRegExp.hasMatch(text)) {
                         CustomSnackBar.show(context, message: '⚠️ Por seguridad, no se permite compartir datos de contacto o pagos externos antes de reservar.', type: SnackBarType.error);
                         return;
                      }

                      final message = ChatMessage(
                        sender: isClient ? ChatSender.Client : ChatSender.Caregiver,
                        text: text,
                        timestamp: DateTime.now(),
                      );
                      DependencyInjection.chats.sendMessage(widget.clientId, widget.caregiverId, widget.caregiverName, message);
                      _controller.clear();
                    }
                  },
                ),
              )
            ],
          ),
        )
      ],
    ),
   );
  }
}

