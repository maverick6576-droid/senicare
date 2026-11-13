import 'dart:async';

import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/screens/screens.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/widgets/widgets.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  /// Switches the root bottom navigation tab when hosted inside [MainLayout].
  static bool switchTab(BuildContext context, int index) {
    final state = context.findAncestorStateOfType<_MainLayoutState>();
    if (state == null) return false;
    state._selectTab(index);
    return true;
  }

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0;

  void _selectTab(int index) {
    if (!mounted) return;
    setState(() => _currentIndex = index);
  }
  final AppTutorialTargets _tutorialTargets = AppTutorialTargets();
  bool _showCaregiverTutorial = false;
  bool _showClientTutorial = false;
  String? _checkedAutoTutorialKey;
  Timer? _autoTutorialTimer;

  @override
  void initState() {
    super.initState();
    pendingPushRoute.addListener(_onPendingPushRouteChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumePendingPushRoute());
  }

  @override
  void dispose() {
    pendingPushRoute.removeListener(_onPendingPushRouteChanged);
    _autoTutorialTimer?.cancel();
    super.dispose();
  }

  void _onPendingPushRouteChanged() {
    if (!mounted) return;
    _consumePendingPushRoute();
  }

  void _consumePendingPushRoute() {
    final route = pendingPushRoute.value;
    if (route == null || !mounted) return;
    pendingPushRoute.value = null;

    final type = route['type']?.toString() ?? '';
    switch (type) {
      case 'chat':
        _selectTab(3);
        break;
      case 'tracking':
      case 'booking':
      case 'payment':
        _selectTab(2);
        break;
      case 'job_offer':
      case 'job_application':
      case 'job_application_accepted':
        _selectTab(1);
        break;
      case 'verification':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const IdentityVerificationScreen()),
        );
        break;
    }
  }

  void _startTutorial({required bool forClient}) {
    _autoTutorialTimer?.cancel();
    setState(() {
      _currentIndex = 0;
      _showClientTutorial = forClient;
      _showCaregiverTutorial = !forClient;
    });
  }

  void _closeTutorial({
    required bool forClient,
    required AuthNotifier auth,
  }) {
    _autoTutorialTimer?.cancel();
    setState(() {
      if (forClient) {
        _showClientTutorial = false;
      } else {
        _showCaregiverTutorial = false;
      }
      _currentIndex = 0;
    });
    final userId = auth.currentUserId;
    if (forClient) {
      unawaited(ClientTutorialService.markSeen(auth));
    } else if (userId != null && userId.isNotEmpty) {
      unawaited(CaregiverTutorialService.markSeen(userId: userId, auth: auth));
    }
  }

  Future<void> _maybeScheduleAutoTutorial(AuthNotifier auth) async {
    final userId = auth.currentUserId;
    if (userId == null || userId.isEmpty) return;
    final role = auth.currentRole;
    final checkKey = '$role:$userId';
    if (_checkedAutoTutorialKey == checkKey) return;
    _checkedAutoTutorialKey = checkKey;

    if (role == 'client') {
      final seenClient = await ClientTutorialService.hasSeen(auth);
      if (!mounted ||
          seenClient ||
          _showClientTutorial ||
          _showCaregiverTutorial ||
          auth.currentRole != 'client' ||
          auth.currentUserId != userId) {
        return;
      }
      _autoTutorialTimer?.cancel();
      _autoTutorialTimer = Timer(const Duration(milliseconds: 180), () {
        if (!mounted) return;
        if (auth.currentRole == 'client' &&
            auth.currentUserId == userId &&
            !_showClientTutorial) {
          _startTutorial(forClient: true);
        }
      });
      return;
    }

    CaregiverProfile? profile = auth.currentCaregiver;
    if (profile == null) {
      try {
        profile = await DependencyInjection.caregivers.getCaregiver(userId);
      } catch (_) {}
    }

    if (!mounted || auth.currentRole != 'caregiver' || auth.currentUserId != userId) {
      return;
    }

    if (profile?.hasSeenCaregiverTutorial == true) {
      return;
    }

    final seenLocally = await CaregiverTutorialService.hasSeenLocally(userId);
    if (!mounted || seenLocally || _showCaregiverTutorial || _showClientTutorial) {
      return;
    }
    if (auth.currentRole != 'caregiver' || auth.currentUserId != userId) return;

    _autoTutorialTimer?.cancel();
    _autoTutorialTimer = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      if (auth.currentRole == 'caregiver' &&
          auth.currentUserId == userId &&
          !_showCaregiverTutorial) {
        _startTutorial(forClient: false);
      }
    });
  }

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
    final config = context.watch<ConfigNotifier>();
    final isClient = auth.currentRole == 'client';

    if (!isClient) {
      _showClientTutorial = false;
      if (config.pendingCaregiverTutorial) {
        config.consumeCaregiverTutorialRequest();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && auth.currentRole == 'caregiver') {
            _startTutorial(forClient: false);
          }
        });
      } else if (!_showCaregiverTutorial) {
        _maybeScheduleAutoTutorial(auth);
      }
    } else {
      _showCaregiverTutorial = false;
      if (config.pendingClientTutorial) {
        config.consumeClientTutorialRequest();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && auth.currentRole == 'client') {
            _startTutorial(forClient: true);
          }
        });
      } else if (!_showClientTutorial) {
        _maybeScheduleAutoTutorial(auth);
      }
    }

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
      showOffersBadge = jobOffers.nearbyOffers.any(
        (o) =>
            o.status == JobOfferStatus.open &&
            !o.isExpired &&
            !jobOffers.myApplicationsByOfferId.containsKey(o.id),
      );
    }

    // Reservas Badge
    final bookings = context.watch<BookingNotifier>().bookings;
    bool showBookingsBadge = bookings.any((b) => b.isActive);

    // Mensajes Badge setup
    final String userId =
        (isClient ? auth.effectiveClientId : auth.currentUserId) ?? '';

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

    return TutorialScope(
      targets: _tutorialTargets,
      child: PopScope(
        canPop: !((_showCaregiverTutorial && !isClient) ||
            (_showClientTutorial && isClient)),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _showCaregiverTutorial && !isClient) {
            _closeTutorial(forClient: false, auth: auth);
          } else if (!didPop && _showClientTutorial && isClient) {
            _closeTutorial(forClient: true, auth: auth);
          }
        },
        child: Stack(
          children: [
            Scaffold(
              appBar: AppBar(
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(1),
                  child: Container(height: 1, color: AppTheme.borderSubtle),
                ),
                title: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        'assets/images/logo.png',
                        height: 34,
                        width: 34,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox(
                          width: 34,
                          height: 34,
                          child: Icon(
                            Icons.health_and_safety_rounded,
                            color: AppTheme.primary,
                            size: 28,
                          ),
                        ),
                      ),
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
                  Row(
                    key: _tutorialTargets.topRightActionsKey,
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                          if (action == 'tutorial') {
                            _startTutorial(forClient: isClient);
                          } else if (action == 'logout') {
                            DependencyInjection.auth.signOut();
                          } else if (action == 'settings') {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'tutorial',
                            child: Row(
                              children: [
                                Icon(Icons.play_circle_outline_rounded, size: 18, color: AppTheme.primary),
                                SizedBox(width: 8),
                                Expanded(child: Text('Tutorial guiado paso a paso')),
                              ],
                            ),
                          ),
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
                ],
              ),
              body: currentScreens[_currentIndex],
              bottomNavigationBar: Container(
                key: _tutorialTargets.bottomNavKey,
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppTheme.borderSubtle, width: 1)),
                ),
                child: BottomNavigationBar(
                  type: BottomNavigationBarType.fixed,
                  currentIndex: _currentIndex,
                  onTap: (idx) => setState(() => _currentIndex = idx),
                  selectedItemColor: AppTheme.primary,
                  unselectedItemColor: AppTheme.slateMuted,
                  items: () {
                    final l10n = AppLocalizations.of(context);
                    return isClient
                        ? [
                            BottomNavigationBarItem(icon: const Icon(Icons.search), activeIcon: const Icon(Icons.saved_search), label: l10n.tabExplore),
                            BottomNavigationBarItem(icon: _buildIcon(Icons.work_outline, showOffersBadge), activeIcon: _buildIcon(Icons.work, showOffersBadge), label: l10n.tabOffers),
                            BottomNavigationBarItem(icon: _buildIcon(Icons.calendar_today, showBookingsBadge), activeIcon: _buildIcon(Icons.calendar_month, showBookingsBadge), label: l10n.tabBookings),
                            BottomNavigationBarItem(icon: buildMessagesIcon(), activeIcon: buildMessagesIcon(active: true), label: l10n.tabInbox),
                            BottomNavigationBarItem(icon: const Icon(Icons.person_outline), activeIcon: const Icon(Icons.person), label: l10n.tabSettings),
                          ]
                        : [
                            BottomNavigationBarItem(icon: const Icon(Icons.dashboard_outlined), activeIcon: const Icon(Icons.dashboard), label: l10n.tabHome),
                            BottomNavigationBarItem(icon: _buildIcon(Icons.work_outline, showOffersBadge), activeIcon: _buildIcon(Icons.work, showOffersBadge), label: l10n.tabOffers),
                            BottomNavigationBarItem(icon: _buildIcon(Icons.calendar_today, showBookingsBadge), activeIcon: _buildIcon(Icons.calendar_month, showBookingsBadge), label: l10n.tabBookings),
                            BottomNavigationBarItem(icon: buildMessagesIcon(), activeIcon: buildMessagesIcon(active: true), label: l10n.tabInbox),
                            BottomNavigationBarItem(icon: const Icon(Icons.person_outline), activeIcon: const Icon(Icons.person), label: l10n.tabSettings),
                          ];
                  }(),
                ),
              ),
            ),
            if (_showCaregiverTutorial && !isClient)
              CaregiverTutorialOverlay(
                targets: _tutorialTargets,
                currentTabIndex: _currentIndex,
                onSwitchTab: (idx) {
                  if (mounted) setState(() => _currentIndex = idx);
                },
                onExit: () => _closeTutorial(forClient: false, auth: auth),
                onFinish: () => _closeTutorial(forClient: false, auth: auth),
              ),
            if (_showClientTutorial && isClient)
              ClientTutorialOverlay(
                targets: _tutorialTargets,
                currentTabIndex: _currentIndex,
                onSwitchTab: (idx) {
                  if (mounted) setState(() => _currentIndex = idx);
                },
                onExit: () => _closeTutorial(forClient: true, auth: auth),
                onFinish: () => _closeTutorial(forClient: true, auth: auth),
              ),
          ],
        ),
      ),
    );
  }
}
