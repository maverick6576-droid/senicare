import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/screens/screens.dart';
import 'package:senicare/models/models.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0;

  Widget _buildIcon(IconData iconData, bool showBadge) {
    if (!showBadge) return Icon(iconData);
    return Badge(
      smallSize: 10,
      backgroundColor: Colors.red,
      child: Icon(iconData),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthNotifier>();
    final isClient = auth.currentRole == 'client';

    final currentScreens = isClient
        ? const <Widget>[ExplorerScreen(), OffersHubScreen(), BookingsScreen(), InboxScreen(), ClientProfileEditScreen()]
        : const <Widget>[CaregiverDashboard(), OffersHubScreen(), BookingsScreen(), InboxScreen(), CaregiverProfileEditScreen()];

    if (_currentIndex >= currentScreens.length) {
      _currentIndex = 0;
    }

    // Ofertas Badge
    final jobOffers = context.watch<JobOfferNotifier>();
    bool showOffersBadge = false;
    if (isClient) {
      showOffersBadge = jobOffers.clientOffers.any((o) => o.status == JobOfferStatus.open && !o.isExpired);
    } else {
      showOffersBadge = jobOffers.nearbyOffers.any((o) => o.status == JobOfferStatus.open && !o.isExpired);
    }

    // Reservas Badge
    final bookings = context.watch<BookingNotifier>().bookings;
    bool showBookingsBadge = bookings.any((b) => b.isActive);

    // Mensajes Badge setup
    final String userId = auth.currentUserId ?? '';

    Widget buildMessagesIcon({bool active = false}) {
      if (userId.isEmpty) {
        return Icon(active ? Icons.chat_bubble : Icons.chat_bubble_outline);
      }
      return StreamBuilder<List<ChatConversation>>(
        stream: DependencyInjection.chats.streamActiveChats(userId, auth.currentRole),
        builder: (context, snapshot) {
          final conversations = snapshot.data ?? [];
          bool showMessagesBadge = false;
          if (isClient) {
            showMessagesBadge = conversations.any((c) => c.unreadClientCount > 0);
          } else {
            showMessagesBadge = conversations.any((c) => c.unreadCaregiverCount > 0);
          }
          
          IconData iconData = active ? Icons.chat_bubble : Icons.chat_bubble_outline;
          if (!showMessagesBadge) return Icon(iconData);
          return Badge(smallSize: 10, backgroundColor: Colors.red, child: Icon(iconData));
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppTheme.borderSubtle),
        ),
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset('assets/images/logo.png', height: 34),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primarySurface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
                ),
                child: Text(
                  isClient ? 'Familias' : 'Cuidador',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primary, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: AppTheme.darkSlate),
            tooltip: 'Ajustes y Cuenta',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: AppTheme.darkSlate),
            tooltip: 'Más opciones',
            onSelected: (action) {
              if (action == 'logout') {
                DependencyInjection.auth.signOut();
              } else if (action == 'settings') {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined, size: 18, color: AppTheme.darkSlate),
                    SizedBox(width: 8),
                    Expanded(child: Text('Ajustes y Modo Accesible')),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded, size: 18, color: Colors.red),
                    SizedBox(width: 8),
                    Expanded(child: Text('Cerrar Sesión', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600))),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: currentScreens[_currentIndex],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.borderSubtle, width: 1)),
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: _currentIndex,
          onTap: (idx) => setState(() => _currentIndex = idx),
          selectedItemColor: AppTheme.primary,
          unselectedItemColor: AppTheme.slateMuted,
          items: isClient 
            ? [
                const BottomNavigationBarItem(icon: Icon(Icons.search), activeIcon: Icon(Icons.saved_search), label: 'Explorar'),
                BottomNavigationBarItem(icon: _buildIcon(Icons.work_outline, showOffersBadge), activeIcon: _buildIcon(Icons.work, showOffersBadge), label: 'Ofertas'),
                BottomNavigationBarItem(icon: _buildIcon(Icons.calendar_today, showBookingsBadge), activeIcon: _buildIcon(Icons.calendar_month, showBookingsBadge), label: 'Reservas'),
                BottomNavigationBarItem(icon: buildMessagesIcon(), activeIcon: buildMessagesIcon(active: true), label: 'Mensajes'),
                const BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Mi Perfil'),
              ]
            : [
                const BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard), label: 'Inicio'),
                BottomNavigationBarItem(icon: _buildIcon(Icons.work_outline, showOffersBadge), activeIcon: _buildIcon(Icons.work, showOffersBadge), label: 'Ofertas'),
                BottomNavigationBarItem(icon: _buildIcon(Icons.calendar_today, showBookingsBadge), activeIcon: _buildIcon(Icons.calendar_month, showBookingsBadge), label: 'Reservas'),
                BottomNavigationBarItem(icon: buildMessagesIcon(), activeIcon: buildMessagesIcon(active: true), label: 'Mensajes'),
                const BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Mi Perfil'),
              ],
        ),
      ),
    );
  }
}
