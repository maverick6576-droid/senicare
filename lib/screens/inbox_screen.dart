import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/screens/screens.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Map<String, Future<ClientProfile?>> _clientFutures = {};
  final Map<String, Future<CaregiverProfile?>> _caregiverFutures = {};

  Stream<List<ChatConversation>>? _chatsStream;
  String? _streamKey;
  String _searchQuery = '';
  bool _onlyUnread = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Stream<List<ChatConversation>> _ensureChatsStream(
    String userId,
    String role,
  ) {
    final key = '${userId}_$role';
    if (_chatsStream == null || _streamKey != key) {
      _streamKey = key;
      _chatsStream = DependencyInjection.chats.streamActiveChats(userId, role);
    }
    return _chatsStream!;
  }

  Future<ClientProfile?> _getClientProfile(String clientId) {
    return _clientFutures.putIfAbsent(
      clientId,
      () => DependencyInjection.clients.getClient(clientId),
    );
  }

  Future<CaregiverProfile?> _getCaregiverProfile(String caregiverId) {
    return _caregiverFutures.putIfAbsent(
      caregiverId,
      () => DependencyInjection.caregivers.getCaregiver(caregiverId),
    );
  }

  String _formatWhatsAppListTime(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final msgDay = DateTime(date.year, date.month, date.day);

    if (msgDay == today) {
      return DateFormat('HH:mm').format(date);
    }
    if (msgDay == yesterday) {
      return 'Ayer';
    }
    return DateFormat('dd/MM/yy').format(date);
  }

  void _openNewChatFromBookings(
    BuildContext context,
    String userId,
    String role,
  ) {
    final isClient = role == 'client';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.55,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text(
                    isClient
                        ? 'Chatear con tus cuidadores'
                        : 'Chatear con familias de tus reservas',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.darkSlate,
                    ),
                  ),
                ),
                Expanded(
                  child: StreamBuilder<List<Booking>>(
                    stream:
                        DependencyInjection.bookings.streamBookings(userId, role),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final bookings = snap.data ?? const [];
                      final seenPeers = <String, Booking>{};
                      for (final b in bookings) {
                        final peerId = isClient ? b.caregiverId : b.clientId;
                        if (peerId.isNotEmpty && !seenPeers.containsKey(peerId)) {
                          seenPeers[peerId] = b;
                        }
                      }
                      final peers = seenPeers.values.toList();
                      if (peers.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Todavía no tienes reservas para iniciar un chat rápido.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppTheme.slateMuted),
                            ),
                          ),
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: peers.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final b = peers[index];
                          if (isClient) {
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppTheme.primarySurface,
                                child: Text(
                                  b.caregiverName.isNotEmpty
                                      ? b.caregiverName[0].toUpperCase()
                                      : 'C',
                                  style: const TextStyle(
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              title: Text(
                                b.caregiverName,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text('Reserva · ${b.day}'),
                              trailing: const Icon(
                                Icons.chat_rounded,
                                color: AppTheme.primary,
                              ),
                              onTap: () {
                                Navigator.pop(sheetCtx);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ChatScreen(
                                      clientId: b.clientId,
                                      caregiverId: b.caregiverId,
                                      caregiverName: b.caregiverName,
                                    ),
                                  ),
                                );
                              },
                            );
                          }
                          return FutureBuilder<ClientProfile?>(
                            future: _getClientProfile(b.clientId),
                            builder: (context, clientSnap) {
                              final rawName = clientSnap.data?.name ?? '';
                              final displayName = rawName.trim().isNotEmpty
                                  ? 'Familia ${rawName.trim()}'
                                  : 'Familia (${b.clientId.substring(0, b.clientId.length < 4 ? b.clientId.length : 4)})';
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.teal.shade50,
                                  child: const Icon(
                                    Icons.family_restroom_rounded,
                                    color: AppTheme.primary,
                                  ),
                                ),
                                title: Text(
                                  displayName,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text('Reserva · ${b.day}'),
                                trailing: const Icon(
                                  Icons.chat_rounded,
                                  color: AppTheme.primary,
                                ),
                                onTap: () {
                                  Navigator.pop(sheetCtx);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ChatScreen(
                                        clientId: b.clientId,
                                        caregiverId: b.caregiverId,
                                        caregiverName: b.caregiverName,
                                        clientName: rawName,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthNotifier>();
    final isClient = auth.currentRole == 'client';
    final String userId = auth.currentUserId ?? '';

    if (userId.isEmpty) {
      return const Center(child: Text('No tienes conversaciones activas.'));
    }

    return Scaffold(
      backgroundColor: Colors.white,
      floatingActionButton: FloatingActionButton(
        heroTag: 'inbox_new_chat_fab',
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        tooltip: 'Nuevo chat',
        onPressed: () =>
            _openNewChatFromBookings(context, userId, auth.currentRole),
        child: const Icon(Icons.add_comment_rounded),
      ),
      body: StreamBuilder<List<ChatConversation>>(
        stream: _ensureChatsStream(userId, auth.currentRole),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.wifi_off_rounded,
                      size: 56,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No se pudieron cargar los chats',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.darkSlate,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _streamKey = null;
                        });
                      },
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            );
          }

          final allChats = snapshot.data ?? const [];
          final totalUnreadChats = allChats.where((chat) {
            final unread = isClient
                ? chat.unreadClientCount
                : chat.unreadCaregiverCount;
            return unread > 0;
          }).length;

          final query = _searchQuery.trim().toLowerCase();
          final filteredChats = allChats.where((chat) {
            final unread = isClient
                ? chat.unreadClientCount
                : chat.unreadCaregiverCount;
            if (_onlyUnread && unread == 0) return false;
            if (query.isEmpty) return true;
            final titleCandidate = isClient
                ? chat.caregiverName
                : chat.familyDisplayName();
            return titleCandidate.toLowerCase().contains(query) ||
                chat.lastMessage.toLowerCase().contains(query);
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Buscar chat o mensaje...',
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: AppTheme.slateMuted,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFFF1F5F9),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    ChoiceChip(
                      label: Text('Todos (${allChats.length})'),
                      selected: !_onlyUnread,
                      selectedColor: AppTheme.primarySurface,
                      labelStyle: TextStyle(
                        color:
                            !_onlyUnread ? AppTheme.primary : AppTheme.slateMuted,
                        fontWeight: FontWeight.w600,
                      ),
                      onSelected: (_) => setState(() => _onlyUnread = false),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text('No leídos ($totalUnreadChats)'),
                      selected: _onlyUnread,
                      selectedColor: AppTheme.primarySurface,
                      labelStyle: TextStyle(
                        color:
                            _onlyUnread ? AppTheme.primary : AppTheme.slateMuted,
                        fontWeight: FontWeight.w600,
                      ),
                      onSelected: (_) => setState(() => _onlyUnread = true),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: filteredChats.isEmpty
                    ? RefreshIndicator(
                        onRefresh: () async {
                          setState(() => _streamKey = null);
                          await Future.delayed(
                            const Duration(milliseconds: 500),
                          );
                        },
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.5,
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.chat_bubble_outline_rounded,
                                        size: 64,
                                        color: Colors.grey.shade300,
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        allChats.isEmpty
                                            ? 'Aún no tienes chats'
                                            : 'No hay chats con ese filtro',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.darkSlate,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        allChats.isEmpty
                                            ? (isClient
                                                ? 'Chatea directamente con cualquier cuidador para conocerle mejor.'
                                                : 'Aquí verás los mensajes de las familias interesadas en tus servicios.')
                                            : 'Prueba borrando la búsqueda o cambiando el filtro.',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: AppTheme.slateMuted,
                                        ),
                                      ),
                                      if (allChats.isEmpty) ...[
                                        const SizedBox(height: 18),
                                        OutlinedButton.icon(
                                          onPressed: () =>
                                              _openNewChatFromBookings(
                                            context,
                                            userId,
                                            auth.currentRole,
                                          ),
                                          icon: const Icon(
                                            Icons.add_comment_rounded,
                                          ),
                                          label: const Text(
                                            'Chatear desde mis reservas',
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          setState(() => _streamKey = null);
                          await Future.delayed(
                            const Duration(milliseconds: 500),
                          );
                        },
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: filteredChats.length,
                          separatorBuilder: (_, _) => const Divider(
                            height: 1,
                            indent: 84,
                          ),
                          itemBuilder: (context, index) {
                            final chat = filteredChats[index];
                            final unreadCount = isClient
                                ? chat.unreadClientCount
                                : chat.unreadCaregiverCount;
                            final isPeerTyping = chat.isPeerTyping(isClient);
                            final viewerSender = isClient
                                ? ChatSender.Client
                                : ChatSender.Caregiver;
                            final isLastFromMe =
                                chat.lastMessageSender == viewerSender;

                            return InkWell(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ChatScreen(
                                      clientId: chat.clientId,
                                      caregiverId: chat.caregiverId,
                                      caregiverName: chat.caregiverName,
                                      caregiverImageUrl: chat.caregiverImageUrl,
                                      clientName: chat.clientName,
                                    ),
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    _buildAvatar(chat, isClient),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: _buildTitle(
                                                  chat,
                                                  isClient,
                                                  unreadCount > 0,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                _formatWhatsAppListTime(
                                                  chat.lastMessageTimestamp,
                                                ),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: unreadCount > 0
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
                                                  color: unreadCount > 0
                                                      ? AppTheme.primary
                                                      : AppTheme.slateMuted,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              if (!isPeerTyping &&
                                                  isLastFromMe) ...[
                                                Icon(
                                                  Icons.done_all_rounded,
                                                  size: 17,
                                                  color: chat.lastMessageIsRead
                                                      ? const Color(0xFF0284C7)
                                                      : Colors.grey.shade500,
                                                ),
                                                const SizedBox(width: 4),
                                              ],
                                              Expanded(
                                                child: Text(
                                                  isPeerTyping
                                                      ? 'escribiendo...'
                                                      : chat.lastMessage,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontStyle: isPeerTyping
                                                        ? FontStyle.italic
                                                        : FontStyle.normal,
                                                    fontWeight: (isPeerTyping ||
                                                            unreadCount > 0)
                                                        ? FontWeight.w600
                                                        : FontWeight.normal,
                                                    color: isPeerTyping
                                                        ? const Color(0xFF16A34A)
                                                        : (unreadCount > 0
                                                            ? AppTheme.darkSlate
                                                            : AppTheme.slateMuted),
                                                  ),
                                                ),
                                              ),
                                              if (unreadCount > 0) ...[
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    horizontal: 7,
                                                    vertical: 3,
                                                  ),
                                                  decoration:
                                                      const BoxDecoration(
                                                    color: AppTheme.primary,
                                                    shape: BoxShape.rectangle,
                                                    borderRadius:
                                                        BorderRadius.all(
                                                      Radius.circular(12),
                                                    ),
                                                  ),
                                                  constraints:
                                                      const BoxConstraints(
                                                    minWidth: 22,
                                                  ),
                                                  child: Text(
                                                    unreadCount > 99
                                                        ? '99+'
                                                        : unreadCount.toString(),
                                                    textAlign: TextAlign.center,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11.5,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAvatar(ChatConversation chat, bool isClient) {
    if (isClient) {
      if (chat.caregiverImageUrl.isNotEmpty) {
        return CircleAvatar(
          radius: 26,
          backgroundColor: AppTheme.primarySurface,
          backgroundImage: CachedNetworkImageProvider(chat.caregiverImageUrl),
        );
      }
      return FutureBuilder<CaregiverProfile?>(
        future: _getCaregiverProfile(chat.caregiverId),
        builder: (context, snap) {
          final url = snap.data?.imageUrl ?? '';
          if (url.isNotEmpty) {
            return CircleAvatar(
              radius: 26,
              backgroundColor: AppTheme.primarySurface,
              backgroundImage: CachedNetworkImageProvider(url),
            );
          }
          final initial = chat.caregiverName.isNotEmpty
              ? chat.caregiverName[0].toUpperCase()
              : 'C';
          return CircleAvatar(
            radius: 26,
            backgroundColor: AppTheme.primarySurface,
            child: Text(
              initial,
              style: const TextStyle(
                color: AppTheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          );
        },
      );
    }

    return CircleAvatar(
      radius: 26,
      backgroundColor: const Color(0xFFE0F2FE),
      child: const Icon(
        Icons.family_restroom_rounded,
        color: Color(0xFF0369A1),
        size: 26,
      ),
    );
  }

  Widget _buildTitle(ChatConversation chat, bool isClient, bool isUnread) {
    final baseStyle = TextStyle(
      fontWeight: isUnread ? FontWeight.bold : FontWeight.w600,
      fontSize: 16,
      color: AppTheme.darkSlate,
    );

    if (isClient) {
      return Text(
        chat.caregiverName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: baseStyle,
      );
    }

    if (chat.clientName.trim().isNotEmpty) {
      return Text(
        chat.familyDisplayName(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: baseStyle,
      );
    }

    return FutureBuilder<ClientProfile?>(
      future: _getClientProfile(chat.clientId),
      builder: (context, snapshot) {
        return Text(
          chat.familyDisplayName(snapshot.data?.name),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: baseStyle,
        );
      },
    );
  }
}
