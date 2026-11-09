import 'dart:math';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
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
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
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
                  return Align(
                    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isMe ? AppTheme.primary : Colors.white,
                        borderRadius: BorderRadius.circular(16).copyWith(
                          bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(16),
                          bottomLeft: !isMe ? const Radius.circular(0) : const Radius.circular(16),
                        ),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))],
                      ),
                      child: Text(m.text, style: TextStyle(color: isMe ? Colors.white : AppTheme.darkSlate)),
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
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: 'Escribe un mensaje...',
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
                    final text = _controller.text.trim();
                    if (text.isNotEmpty) {
                      // RegEx anti-fuga
                      final leakRegExp = RegExp(r'(bizum|efectivo|whatsapp|@|\+34|\b[679][0-9]{8}\b|tlf|telefono|teléfono)', caseSensitive: false);
                      if (leakRegExp.hasMatch(text) && !isClient) {
                         // Client might type phone? Let's block both or just caregiver. Block both for safety.
                         CustomSnackBar.show(context, message: '⚠️ Por seguridad, no se permite compartir datos de contacto o pagos externos antes de reservar.', type: SnackBarType.error);
                         return;
                      } else if (leakRegExp.hasMatch(text) && isClient) {
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

