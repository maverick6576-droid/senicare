import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/screens/screens.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final Map<String, Future<ClientProfile?>> _clientFutures = {};
  final Map<String, Future<CaregiverProfile?>> _caregiverFutures = {};

  Future<ClientProfile?> _getClientProfile(String clientId) {
    if (!_clientFutures.containsKey(clientId)) {
      _clientFutures[clientId] = DependencyInjection.clients.getClient(clientId);
    }
    return _clientFutures[clientId]!;
  }

  Future<CaregiverProfile?> _getCaregiverProfile(String caregiverId) {
    if (!_caregiverFutures.containsKey(caregiverId)) {
      _caregiverFutures[caregiverId] = DependencyInjection.caregivers.getCaregiver(caregiverId);
    }
    return _caregiverFutures[caregiverId]!;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthNotifier>();
    final isClient = auth.currentRole == 'client';
    
    final String userId = auth.currentUserId ?? '';
    if (userId.isEmpty) {
      return const Center(child: Text('No tienes conversaciones activas.'));
    }

    return StreamBuilder<List<ChatConversation>>(
      stream: DependencyInjection.chats.streamActiveChats(userId, auth.currentRole),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Error al cargar conversaciones'));
        }

        final chats = snapshot.data ?? [];
        if (chats.isEmpty) {
          return RefreshIndicator(
            onRefresh: () async {
              setState(() {});
              await Future.delayed(const Duration(milliseconds: 800));
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.5,
                  child: const Center(child: Text('No tienes conversaciones activas.')),
                )
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
            await Future.delayed(const Duration(milliseconds: 800));
          },
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: chats.length,
            itemBuilder: (context, index) {
            final chat = chats[index];
            final unreadCount = isClient ? chat.unreadClientCount : chat.unreadCaregiverCount;
            final hasUnread = unreadCount > 0;

            Widget buildTile(String displayName, String chatCaregiverName) {
              final initials = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
              final now = DateTime.now();
              final dt = chat.lastMessageTimestamp;
              final String timeString;
              if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
                timeString = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
              } else {
                timeString = '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year.toString().substring(2)}';
              }

              return InkWell(
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(
                    clientId: chat.clientId,
                    caregiverId: chat.caregiverId,
                    caregiverName: chatCaregiverName,
                  )));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: hasUnread ? const Color(0xFFF2FBF5) : Colors.transparent,
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade200, width: 0.8),
                    ),
                  ),
                  child: Row(
                    children: [
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                            child: Text(
                              initials,
                              style: TextStyle(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          if (hasUnread)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF25D366),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: hasUnread ? FontWeight.w800 : FontWeight.w600,
                                      color: AppTheme.darkSlate,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  timeString,
                                  style: TextStyle(
                                    color: hasUnread ? const Color(0xFF25D366) : Colors.grey.shade600,
                                    fontSize: 12,
                                    fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    chat.lastMessage,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                                      color: hasUnread ? AppTheme.darkSlate : Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                                if (hasUnread) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF25D366),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      unreadCount > 99 ? '99+' : '$unreadCount',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
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
            }

            if (isClient) {
              return FutureBuilder<CaregiverProfile?>(
                key: ValueKey(chat.roomId),
                future: _getCaregiverProfile(chat.caregiverId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return buildTile(chat.caregiverName, chat.caregiverName);
                  final caregiverName = snapshot.data?.name ?? chat.caregiverName;
                  return buildTile(caregiverName, caregiverName);
                }
              );
            } else {
              return FutureBuilder<ClientProfile?>(
                key: ValueKey(chat.roomId),
                future: _getClientProfile(chat.clientId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return buildTile('Familia: ...', chat.caregiverName);
                  final clientName = snapshot.data?.name ?? '';
                  final nameParts = clientName.trim().split(RegExp(r'\s+'));
                  final surname = nameParts.length > 1 ? nameParts[1] : clientName;
                  final displayName = surname.isNotEmpty ? 'Familia: $surname' : 'Familia (ID: ${chat.clientId.substring(0, 4)})';
                  return buildTile(displayName, chat.caregiverName);
                }
              );
            }
          },
        ));
      },
    );
  }
}
