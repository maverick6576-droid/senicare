import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/screens/screens.dart';
import 'package:senicare/widgets/widgets.dart';
import 'package:qr_flutter/qr_flutter.dart';

class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key});

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  final ScrollController _scrollActive = ScrollController();
  final ScrollController _scrollHistory = ScrollController();
  final Map<String, Future<ClientProfile?>> _clientFutures = {};
  final Set<String> _busyBookingIds = {};
  String _caregiverFilter = 'all'; // 'all', 'pending', 'today'
  String _clientFilter = 'all'; // 'all', 'attention', 'today'

  String _extractCaregiverInitials(String? rawName) {
    final clean = (rawName ?? '').trim();
    if (clean.isEmpty) return 'C';
    final parts = clean.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'C';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  Future<ClientProfile?> _getClientProfile(String clientId) {
    if (clientId.isEmpty) return Future.value(null);
    return _clientFutures.putIfAbsent(
      clientId,
      () => DependencyInjection.clients.getClient(clientId),
    );
  }

  String _formatDay(String d) {
    try {
      final p = d.split('-');
      if (p.length == 3) return '${p[2]}/${p[1]}/${p[0]}';
    } catch (_) {}
    return d;
  }

  bool _isScheduledToday(Booking b) {
    final start = b.scheduledStartTime;
    if (start == null) return false;
    final now = DateTime.now();
    return start.year == now.year && start.month == now.month && start.day == now.day;
  }

  String _formatFriendlyDay(Booking b) {
    final start = b.scheduledStartTime;
    if (start == null) return _formatDay(b.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(start.year, start.month, start.day);
    final diffDays = target.difference(today).inDays;
    final shortDate =
        '${start.day.toString().padLeft(2, '0')}/${start.month.toString().padLeft(2, '0')}';
    if (diffDays == 0) return 'Hoy ($shortDate)';
    if (diffDays == 1) return 'Mañana ($shortDate)';
    if (diffDays == -1) return 'Ayer ($shortDate)';
    const weekdays = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    final wd = weekdays[(start.weekday - 1).clamp(0, 6)];
    return '$wd $shortDate/${start.year}';
  }

  ({String label, String initials}) _extractFamilyDisplay(String? rawName) {
    final clean = (rawName ?? '').trim();
    if (clean.isEmpty) return (label: 'Familia', initials: 'F');
    final parts = clean.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return (label: 'Familia', initials: 'F');
    if (parts.length == 1) {
      return (label: 'Familia ${parts.first}', initials: parts.first[0].toUpperCase());
    }
    final surname = parts.sublist(1).join(' ');
    final initials = parts.length > 2
        ? '${parts[1][0]}${parts[2][0]}'.toUpperCase()
        : parts[1][0].toUpperCase();
    return (label: 'Familia $surname', initials: initials);
  }

  Future<void> _handleRefresh(BookingNotifier state) async {
    _clientFutures.clear();
    await state.refreshBookings();
  }

  Future<void> _runBookingAction(
    String bookingId,
    Future<void> Function() action, {
    String? successMessage,
    SnackBarType successType = SnackBarType.success,
  }) async {
    if (_busyBookingIds.contains(bookingId)) return;
    setState(() => _busyBookingIds.add(bookingId));
    try {
      await action();
      if (mounted && successMessage != null) {
        CustomSnackBar.show(context, message: successMessage, type: successType);
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: 'No se pudo completar la acción: $e',
          type: SnackBarType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busyBookingIds.remove(bookingId));
      }
    }
  }

  Future<void> _openMapsForBooking(Booking b, ClientProfile? profile) async {
    final double? lat = b.clientLatitude ?? profile?.latitude;
    final double? lng = b.clientLongitude ?? profile?.longitude;
    final String address = profile?.homeAddress.trim() ?? '';
    Uri? uri;
    if (lat != null && lng != null && (lat != 0 || lng != 0)) {
      uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    } else if (address.isNotEmpty) {
      uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}',
      );
    }
    if (uri == null) {
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: 'La familia aún no ha indicado una dirección exacta.',
          type: SnackBarType.info,
        );
      }
      return;
    }
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        CustomSnackBar.show(
          context,
          message: 'No se pudo abrir la aplicación de mapas.',
          type: SnackBarType.error,
        );
      }
    } catch (_) {
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: 'No se pudo abrir la aplicación de mapas.',
          type: SnackBarType.error,
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollActive.addListener(_onScroll);
    _scrollHistory.addListener(_onScroll);
  }

  void _onScroll() {
    final notifier = context.read<BookingNotifier>();
    if (!notifier.hasMore || notifier.isLoadingMore) return;
    final nearBottomActive = _scrollActive.hasClients &&
        _scrollActive.position.pixels >= _scrollActive.position.maxScrollExtent - 200;
    final nearBottomHistory = _scrollHistory.hasClients &&
        _scrollHistory.position.pixels >= _scrollHistory.position.maxScrollExtent - 200;
    if (nearBottomActive || nearBottomHistory) {
      notifier.loadMoreBookings();
    }
  }

  @override
  void dispose() {
    _scrollActive.dispose();
    _scrollHistory.dispose();
    super.dispose();
  }

  bool _isReviewPopupShowing = false;
  final Set<String> _dismissedReviewGroups = {};

  void _checkPendingReviews(List<Booking> bookings) {
    if (_isReviewPopupShowing || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    
    // Find pending reviews: completed/expired, unreviewed, not cancelled, client only
    final pending = bookings.where((b) => 
        !b.isReviewed &&
        !b.reviewPromptDismissed &&
        b.status != BookingStatus.cancelled && 
        b.status != BookingStatus.cancelledLate &&
        b.escrowStatus != 'disputed' &&
        (b.status == BookingStatus.completed || b.liveStatus == 'completed' || isBookingExpired(b))
    ).toList();
    
    if (pending.isEmpty) return;
    
    // Group by caregiverId and day
    final Map<String, List<Booking>> grouped = {};
    for (var b in pending) {
      final key = '${b.caregiverId}_${b.day}';
      if (!grouped.containsKey(key)) grouped[key] = [];
      grouped[key]!.add(b);
    }
    
    // Get all unexpired active bookings to check if they still have hours left today
    final unexpired = bookings.where((b) => 
        b.status != BookingStatus.cancelled && 
        b.status != BookingStatus.cancelledLate &&
        !isBookingExpired(b)
    ).toList();
    
    for (var entry in grouped.entries) {
      final group = entry.value;
      final first = group.first;
      
      // Check if there is an unexpired booking for this caregiver and day
      final hasUnexpired = unexpired.any((b) => b.caregiverId == first.caregiverId && b.day == first.day);
      
      if (!hasUnexpired) {
        final key = '${first.caregiverId}_${first.day}';
        if (_dismissedReviewGroups.contains(key)) continue;

        _isReviewPopupShowing = true;
        showDialog(
          context: context,
          barrierDismissible: true,
          builder: (ctx) => ReviewDialog(bookings: group),
        ).then((_) {
          _isReviewPopupShowing = false;
          _dismissedReviewGroups.add(key);
        });
        break; // Only show one popup at a time
      }
    }
  }

  bool isBookingExpired(Booking b) => b.isExpired;

  bool _belongsToActiveTab(Booking b, bool isClient) {
    if (!isClient && b.status == BookingStatus.pendingPayment) {
      return false;
    }
    if (b.isInProgressAwaitingCheckOut || b.isOpenDisputePendingAction) {
      return true;
    }
    if (isClient &&
        b.status == BookingStatus.pendingPayment &&
        !b.isEscrowSettled &&
        !b.isExpired) {
      return true;
    }
    return b.isActive;
  }

  int _caregiverActivePriority(Booking b) {
    if (b.isInProgressAwaitingCheckOut) return 0;
    if (b.isOpenDisputePendingAction) return 1;
    if (b.status == BookingStatus.pending) return 2;
    return 3;
  }

  int _compareBySchedule(Booking a, Booking b, {bool descending = false}) {
    final dtA = a.scheduledStartTime ?? a.createdAt;
    final dtB = b.scheduledStartTime ?? b.createdAt;
    final cmp = descending ? dtB.compareTo(dtA) : dtA.compareTo(dtB);
    return cmp != 0 ? cmp : a.createdAt.compareTo(b.createdAt);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthNotifier>();
    final bookingState = context.watch<BookingNotifier>();
    final seniorMode = context.watch<ConfigNotifier>().seniorMode;
    final isClient = auth.currentRole == 'client';
    final bookings = bookingState.bookings
        .where((b) => isClient || b.status != BookingStatus.pendingPayment)
        .toList();

    final activeBookings =
        bookings.where((b) => _belongsToActiveTab(b, isClient)).toList();
    final historyBookings =
        bookings.where((b) => !_belongsToActiveTab(b, isClient)).toList();

    activeBookings.sort((a, b) {
      if (!isClient) {
        final pCmp =
            _caregiverActivePriority(a).compareTo(_caregiverActivePriority(b));
        if (pCmp != 0) return pCmp;
      }
      return _compareBySchedule(a, b, descending: false);
    });
    historyBookings.sort((a, b) => _compareBySchedule(a, b, descending: true));

    if (isClient) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _checkPendingReviews(bookings);
      });
    }

    final int caregiverPendingCount =
        activeBookings.where((b) => b.status == BookingStatus.pending).length;
    final int caregiverTodayCount =
        activeBookings.where(_isScheduledToday).length;

    final int clientAttentionCount = activeBookings.where((b) {
      return b.status == BookingStatus.pending ||
          b.status == BookingStatus.pendingPayment ||
          (b.liveStatus == 'completed' && !b.isEscrowSettled) ||
          (b.disputeRequested && !b.disputeEscalated);
    }).length;
    final int clientTodayCount = activeBookings.where((b) {
      return _isScheduledToday(b) ||
          b.isInProgressAwaitingCheckOut ||
          b.liveStatus == 'on_the_way' ||
          b.liveStatus == 'in_progress';
    }).length;

    final List<Booking> filteredActiveBookings = isClient
        ? activeBookings.where((b) {
            if (_clientFilter == 'attention') {
              return b.status == BookingStatus.pending ||
                  b.status == BookingStatus.pendingPayment ||
                  (b.liveStatus == 'completed' && !b.isEscrowSettled) ||
                  (b.disputeRequested && !b.disputeEscalated);
            }
            if (_clientFilter == 'today') {
              return _isScheduledToday(b) ||
                  b.isInProgressAwaitingCheckOut ||
                  b.liveStatus == 'on_the_way' ||
                  b.liveStatus == 'in_progress';
            }
            return true;
          }).toList()
        : activeBookings.where((b) {
            if (_caregiverFilter == 'pending') {
              return b.status == BookingStatus.pending;
            }
            if (_caregiverFilter == 'today') {
              return _isScheduledToday(b);
            }
            return true;
          }).toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: Column(
          children: [
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
              ),
              child: TabBar(
                labelColor: AppTheme.primary,
                unselectedLabelColor: AppTheme.slateMuted,
                indicatorColor: AppTheme.primary,
                indicatorWeight: 3,
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: seniorMode ? 16.5 : 15,
                ),
                tabs: [
                  Tab(text: 'Activas (${activeBookings.length})'),
                  Tab(text: 'Historial (${historyBookings.length})'),
                ],
              ),
            ),
            Expanded(
              child: bookingState.isLoadingBookings && bookings.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 14),
                            Text(
                              'Cargando tus reservas...',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.slateMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : (bookingState.bookingError != null && bookings.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.cloud_off_rounded,
                                  size: 52,
                                  color: Colors.red.shade400,
                                ),
                                const SizedBox(height: 14),
                                const Text(
                                  'No pudimos cargar tus reservas',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.darkSlate,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  bookingState.bookingError!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppTheme.slateMuted,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                FilledButton.icon(
                                  onPressed: bookingState.retryBookings,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Reintentar'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : TabBarView(
                          children: [
                            _buildBookingsList(
                              context,
                              filteredActiveBookings,
                              isClient,
                              auth,
                              bookingState,
                              isActiveTab: true,
                              controller: _scrollActive,
                              caregiverTotalActiveCount: activeBookings.length,
                              caregiverPendingCount: caregiverPendingCount,
                              caregiverTodayCount: caregiverTodayCount,
                              clientTotalActiveCount: activeBookings.length,
                              clientAttentionCount: clientAttentionCount,
                              clientTodayCount: clientTodayCount,
                              seniorMode: seniorMode,
                            ),
                            _buildBookingsList(
                              context,
                              historyBookings,
                              isClient,
                              auth,
                              bookingState,
                              isActiveTab: false,
                              controller: _scrollHistory,
                              seniorMode: seniorMode,
                            ),
                          ],
                        )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required bool selected,
    required VoidCallback onSelected,
    required String label,
    Color? dotColor,
    bool seniorMode = false,
  }) {
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dotColor != null && !selected) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(label),
        ],
      ),
      labelStyle: TextStyle(
        fontSize: seniorMode ? 14.5 : 13,
        fontWeight: FontWeight.w700,
        color: selected ? Colors.white : AppTheme.darkSlate,
      ),
      selectedColor: AppTheme.primary,
      backgroundColor: Colors.white,
      side: BorderSide(
        color: selected ? AppTheme.primary : AppTheme.borderSubtle,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: EdgeInsets.symmetric(
        horizontal: seniorMode ? 12 : 10,
        vertical: seniorMode ? 8 : 6,
      ),
    );
  }

  Widget _buildCaregiverActivasHeader({
    required int totalActive,
    required int pendingCount,
    required int todayCount,
  }) {
    return Container(
      key: TutorialScope.maybeOf(context)?.bookingsToolbarKey,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Tus turnos y solicitudes',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slateMuted,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CaregiverCalendarScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.calendar_month_rounded, size: 18),
                label: const Text(
                  'Mi horario',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(
                  selected: _caregiverFilter == 'all',
                  onSelected: () => setState(() => _caregiverFilter = 'all'),
                  label: 'Todas ($totalActive)',
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  selected: _caregiverFilter == 'pending',
                  onSelected: () => setState(() => _caregiverFilter = 'pending'),
                  label: 'Por aceptar ($pendingCount)',
                  dotColor: pendingCount > 0 ? Colors.amber.shade700 : null,
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  selected: _caregiverFilter == 'today',
                  onSelected: () => setState(() => _caregiverFilter = 'today'),
                  label: 'Hoy ($todayCount)',
                  dotColor: todayCount > 0 ? AppTheme.secondaryColor : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClientActivasHeader({
    required int totalActive,
    required int attentionCount,
    required int todayCount,
    required bool seniorMode,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, seniorMode ? 14 : 12, 16, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user_rounded,
                  size: 16, color: AppTheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Pago protegido hasta que termine el cuidado',
                  style: TextStyle(
                    fontSize: seniorMode ? 14 : 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slateMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildFilterChip(
                selected: _clientFilter == 'all',
                onSelected: () => setState(() => _clientFilter = 'all'),
                label: 'Todas ($totalActive)',
                seniorMode: seniorMode,
              ),
              _buildFilterChip(
                selected: _clientFilter == 'attention',
                onSelected: () => setState(() => _clientFilter = 'attention'),
                label: 'Por confirmar ($attentionCount)',
                dotColor: attentionCount > 0 ? Colors.amber.shade700 : null,
                seniorMode: seniorMode,
              ),
              _buildFilterChip(
                selected: _clientFilter == 'today',
                onSelected: () => setState(() => _clientFilter = 'today'),
                label: 'Hoy / En curso ($todayCount)',
                dotColor: todayCount > 0 ? AppTheme.secondaryColor : null,
                seniorMode: seniorMode,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBookingsList(
    BuildContext context,
    List<Booking> bookings,
    bool isClient,
    AuthNotifier auth,
    BookingNotifier state, {
    required bool isActiveTab,
    required ScrollController controller,
    int caregiverTotalActiveCount = 0,
    int caregiverPendingCount = 0,
    int caregiverTodayCount = 0,
    int clientTotalActiveCount = 0,
    int clientAttentionCount = 0,
    int clientTodayCount = 0,
    bool seniorMode = false,
  }) {
    final bool showCaregiverToolbar = !isClient && isActiveTab;
    final bool showClientToolbar = isClient && isActiveTab && clientTotalActiveCount > 0;
    final bool isCaregiverFilteredEmpty = showCaregiverToolbar &&
        bookings.isEmpty &&
        caregiverTotalActiveCount > 0 &&
        _caregiverFilter != 'all';
    final bool isClientFilteredEmpty = isClient &&
        isActiveTab &&
        bookings.isEmpty &&
        clientTotalActiveCount > 0 &&
        _clientFilter != 'all';
    final bool isFilteredEmpty = isCaregiverFilteredEmpty || isClientFilteredEmpty;

    return Column(
      children: [
        if (showCaregiverToolbar)
          _buildCaregiverActivasHeader(
            totalActive: caregiverTotalActiveCount,
            pendingCount: caregiverPendingCount,
            todayCount: caregiverTodayCount,
          ),
        if (showClientToolbar)
          _buildClientActivasHeader(
            totalActive: clientTotalActiveCount,
            attentionCount: clientAttentionCount,
            todayCount: clientTodayCount,
            seniorMode: seniorMode,
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _handleRefresh(state),
            child: bookings.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      Container(
                        constraints: BoxConstraints(
                          minHeight: MediaQuery.of(context).size.height * 0.45,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(22),
                              decoration: BoxDecoration(
                                color: AppTheme.primarySurface,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isFilteredEmpty
                                    ? Icons.filter_alt_off_rounded
                                    : (isActiveTab
                                        ? Icons.favorite_border_rounded
                                        : Icons.history_edu_rounded),
                                size: seniorMode ? 54 : 50,
                                color: AppTheme.primary,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              isFilteredEmpty
                                  ? (isClient
                                      ? (_clientFilter == 'attention'
                                          ? 'No tienes reservas pendientes de confirmar'
                                          : 'No tienes cuidados programados hoy')
                                      : (_caregiverFilter == 'pending'
                                          ? 'No tienes solicitudes pendientes'
                                          : 'No tienes servicios programados hoy'))
                                  : (isActiveTab
                                      ? 'Aún no tienes cuidados activos'
                                      : 'Tu historial de cuidados está vacío'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: seniorMode ? 20 : 18,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.darkSlate,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              isFilteredEmpty
                                  ? 'Puedes ver todas tus reservas activas pulsando el botón de abajo.'
                                  : (isActiveTab
                                      ? (isClient
                                          ? 'Reserva un cuidador verificado o publica una oferta para tu familiar y haz el seguimiento desde aquí.'
                                          : 'Revisa el tablón de ofertas cercanas o mantén tu horario actualizado para recibir solicitudes.')
                                      : 'Aquí aparecerán todas las visitas finalizadas con su Diario del Cuidado y justificantes de pago.'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: seniorMode ? 15 : 13.5,
                                color: AppTheme.slateMuted,
                                height: 1.4,
                              ),
                            ),
                            if (isFilteredEmpty) ...[
                              const SizedBox(height: 16),
                              OutlinedButton(
                                onPressed: () => setState(() {
                                  if (isClient) {
                                    _clientFilter = 'all';
                                  } else {
                                    _caregiverFilter = 'all';
                                  }
                                }),
                                child: const Text('Ver todas las reservas'),
                              ),
                            ] else if (isClient && isActiveTab) ...[
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: () {
                                    if (!MainLayout.switchTab(context, 0)) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => Scaffold(
                                            appBar: AppBar(title: const Text('Explorar cuidadores')),
                                            body: const ExplorerScreen(),
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppTheme.primary,
                                    padding: EdgeInsets.symmetric(
                                      vertical: seniorMode ? 16 : 13,
                                    ),
                                  ),
                                  icon: const Icon(Icons.search_rounded),
                                  label: Text(
                                    'Buscar cuidador',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: seniorMode ? 16 : 14.5,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    if (!MainLayout.switchTab(context, 1)) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => Scaffold(
                                            appBar: AppBar(title: const Text('Ofertas de cuidado')),
                                            body: const OffersHubScreen(),
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  style: OutlinedButton.styleFrom(
                                    padding: EdgeInsets.symmetric(
                                      vertical: seniorMode ? 15 : 12,
                                    ),
                                  ),
                                  icon: const Icon(Icons.campaign_rounded),
                                  label: Text(
                                    'Publicar oferta de cuidado',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: seniorMode ? 15.5 : 14,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                    ],
                  )
                : ListView.builder(
                    controller: controller,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: bookings.length + (state.hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= bookings.length) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            ),
                          ),
                        );
                      }
                      final b = bookings[index];
                      if (isClient) {
                        return _buildBookingCard(
                          context,
                          b,
                          isClient: true,
                          state: state,
                          allBookings: bookings,
                          isActiveTab: isActiveTab,
                        );
                      }
                      return FutureBuilder<ClientProfile?>(
                        future: _getClientProfile(b.clientId),
                        builder: (context, snapshot) {
                          return _buildBookingCard(
                            context,
                            b,
                            isClient: false,
                            state: state,
                            allBookings: bookings,
                            isActiveTab: isActiveTab,
                            clientProfile: snapshot.data,
                            isLoadingClient: snapshot.connectionState ==
                                ConnectionState.waiting,
                          );
                        },
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildBookingCard(
    BuildContext context,
    Booking b, {
    required bool isClient,
    required BookingNotifier state,
    required List<Booking> allBookings,
    required bool isActiveTab,
    ClientProfile? clientProfile,
    bool isLoadingClient = false,
  }) {
    final seniorMode = context.watch<ConfigNotifier>().seniorMode;
    final badge = _resolveStatusBadge(b);
    final familyInfo =
        isClient ? null : _extractFamilyDisplay(clientProfile?.name);
    final bool hasUrgentBorder = !isClient &&
        isActiveTab &&
        (b.isInProgressAwaitingCheckOut || b.status == BookingStatus.pending);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: hasUrgentBorder
              ? badge.color.withValues(alpha: 0.45)
              : AppTheme.borderSubtle,
          width: hasUrgentBorder ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(seniorMode ? 18 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                isClient
                    ? CircleAvatar(
                        radius: seniorMode ? 24 : 20,
                        backgroundColor: AppTheme.primarySurface,
                        foregroundColor: AppTheme.primary,
                        child: Text(
                          _extractCaregiverInitials(b.caregiverName),
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: seniorMode ? 16 : 14,
                          ),
                        ),
                      )
                    : CircleAvatar(
                        backgroundColor: Colors.blue.shade50,
                        foregroundColor: Colors.blue.shade900,
                        child: isLoadingClient && clientProfile == null
                            ? const Icon(Icons.person, color: Colors.blue)
                            : Text(
                                familyInfo!.initials,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                      ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isClient
                            ? b.caregiverName
                            : (isLoadingClient && clientProfile == null
                                ? 'Familia...'
                                : familyInfo!.label),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: seniorMode && isClient ? 18 : 16.5,
                          color: AppTheme.darkSlate,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_formatFriendlyDay(b)} · ${b.slot}',
                        style: TextStyle(
                          color: AppTheme.slateMuted,
                          fontWeight: FontWeight.w600,
                          fontSize: seniorMode && isClient ? 15 : 13.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => _showStatusExplanation(context, b),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: badge.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: badge.color.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 15, color: badge.color),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        badge.label,
                        style: TextStyle(
                          color: badge.color,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isClient
                            ? 'Cuidados a domicilio'
                            : (b.isEscrowSettled || b.status == BookingStatus.completed
                                ? 'Tu ingreso neto'
                                : 'Tu ganancia estimada'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.darkSlate,
                        ),
                      ),
                      if (!isClient)
                        Text(
                          b.escrowStatus == 'refunded'
                              ? 'Reserva reembolsada'
                              : 'Neto tras comisión Senicare',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.slateMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isClient
                      ? '${b.totalPaid.toStringAsFixed(2)} €'
                      : (b.escrowStatus == 'refunded'
                          ? '0.00 €'
                          : '+${b.netPayoutForCaregiver.toStringAsFixed(2)} €'),
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                    color: (!isClient && b.escrowStatus != 'refunded')
                        ? Colors.green.shade700
                        : AppTheme.primary,
                  ),
                ),
              ],
            ),
            if (b.tipAmount > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('☕', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Propina de agradecimiento: +${b.tipAmount.toStringAsFixed(0)} € (100% íntegra)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (!isClient &&
                isActiveTab &&
                b.status == BookingStatus.confirmed &&
                clientProfile != null &&
                (clientProfile.patientDetails.isNotEmpty ||
                    clientProfile.homeAddress.isNotEmpty)) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.medical_information_rounded,
                          size: 17,
                          color: Colors.amber.shade900,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Ficha del domicilio y paciente',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ),
                        if (clientProfile.homeAddress.isNotEmpty ||
                            b.clientLatitude != null ||
                            clientProfile.latitude != null)
                          TextButton.icon(
                            onPressed: () =>
                                _openMapsForBooking(b, clientProfile),
                            icon: const Icon(Icons.directions_rounded, size: 17),
                            label: const Text(
                              'Cómo llegar',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.primary,
                              backgroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              minimumSize: const Size(0, 32),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                  color: AppTheme.primary.withValues(alpha: 0.3),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (clientProfile.homeAddress.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        '📍 ${clientProfile.homeAddress}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.darkSlate,
                        ),
                      ),
                    ],
                    if (clientProfile.patientDetails.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '📋 ${clientProfile.patientDetails}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.darkSlate,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (!isClient &&
                isActiveTab &&
                b.status == BookingStatus.confirmed &&
                b.checkInTime == null &&
                b.liveStatus == 'on_the_way' &&
                !isBookingExpired(b)) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded,
                        size: 17, color: Colors.orange.shade800),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        b.onTheWayAt != null
                            ? 'Aviso "En camino" enviado a las ${DateFormat("HH:mm").format(b.onTheWayAt!)}. Ficha al llegar.'
                            : 'Aviso "En camino" enviado a la familia. Recuerda fichar al llegar.',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (b.status == BookingStatus.confirmed ||
                b.status == BookingStatus.completed) ...[
              if (isActiveTab && b.status == BookingStatus.confirmed) ...[
                const SizedBox(height: 14),
                _buildLiveStatusStepper(b),
              ],
              const SizedBox(height: 12),
              _buildCareJournalSection(
                context,
                b,
                isClient,
                state,
                isActiveTab: isActiveTab,
              ),
            ],
            if (b.escrowStatus == 'disputed') ...[
              const SizedBox(height: 12),
              _buildDisputeBanner(context, b, isClient, state),
            ],
            if (isClient &&
                isBookingExpired(b) &&
                b.checkInTime == null &&
                b.status == BookingStatus.confirmed &&
                b.escrowStatus != 'refunded') ...[
              const SizedBox(height: 12),
              _buildNoShowBanner(context, b),
            ],
            Builder(
              builder: (context) {
                final primaryBtn = _buildPrimaryActionButton(
                  context,
                  b,
                  isClient,
                  state,
                  allBookings,
                );
                if (primaryBtn == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 14.0),
                  child: primaryBtn,
                );
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final auth = context.read<AuthNotifier>();
                      final familyName =
                          (auth.currentClient?.name.trim().isNotEmpty ?? false)
                              ? auth.currentClient!.name
                              : 'Familia';
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            clientId: b.clientId,
                            clientName: familyName,
                            caregiverId: b.caregiverId,
                            caregiverName: b.caregiverName,
                          ),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      minimumSize: Size(0, seniorMode && isClient ? 48 : 42),
                    ),
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                    label: Text(
                      isClient
                          ? 'Chat con ${b.caregiverName.split(" ").first}'
                          : 'Chat con Familia',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: seniorMode && isClient ? 15 : 13.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (isClient)
                  OutlinedButton.icon(
                    onPressed: () => _showBookingMoreOptionsModal(
                      context,
                      b,
                      isClient,
                      state,
                      clientProfile: clientProfile,
                    ),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: AppTheme.backgroundNeutral,
                      foregroundColor: AppTheme.darkSlate,
                      side: const BorderSide(color: AppTheme.borderSubtle),
                      minimumSize: Size(0, seniorMode ? 48 : 42),
                      padding: EdgeInsets.symmetric(
                        horizontal: seniorMode ? 14 : 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: Text(
                      'Más',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: seniorMode ? 14.5 : 13,
                      ),
                    ),
                  )
                else
                  IconButton(
                    onPressed: () => _showBookingMoreOptionsModal(
                      context,
                      b,
                      isClient,
                      state,
                      clientProfile: clientProfile,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.backgroundNeutral,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppTheme.borderSubtle),
                      ),
                      padding: const EdgeInsets.all(12),
                    ),
                    tooltip: 'Más opciones de la reserva',
                    icon: const Icon(Icons.more_horiz_rounded,
                        color: AppTheme.darkSlate),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  ({String label, String explanation, Color color}) _resolveStatusBadge(Booking b) {
    if (b.escrowStatus == 'released' ||
        b.escrowStatus == 'released_manual' ||
        b.escrowStatus == 'released_auto') {
      return (
        label: 'Completado (Pagado)',
        explanation:
            'El servicio se ha realizado correctamente y el pago ha sido liberado al cuidador (se completaron las 24h tras el fin del servicio o se liberó manualmente).',
        color: Colors.green.shade700,
      );
    }
    if (b.escrowStatus == 'refunded') {
      return (
        label: 'Cancelado (Reembolsado)',
        explanation:
            'El servicio fue cancelado o hubo una incidencia mayor (como un No-Show) y se ha devuelto el importe íntegro al cliente.',
        color: Colors.red.shade700,
      );
    }
    if (b.escrowStatus == 'resolved_partial') {
      final isComp = b.status == BookingStatus.completed;
      return (
        label: isComp
            ? 'Acuerdo Resuelto (Pago ajustado)'
            : 'Cancelado (Reembolso parcial)',
        explanation: isComp
            ? 'Ambas partes alcanzaron un acuerdo satisfactorio para resolver la incidencia y los pagos se han ajustado según lo pactado.'
            : 'La reserva fue cancelada fuera de plazo (con penalización) y se reembolsó la parte correspondiente al cliente.',
        color: isComp ? Colors.teal.shade700 : Colors.orange.shade800,
      );
    }
    if (b.escrowStatus == 'disputed') {
      final escalated = b.disputeEscalated == true;
      return (
        label: escalated ? 'Disputa en Mediación' : 'Disputa Abierta',
        explanation: escalated
            ? 'La incidencia ha sido escalada al equipo de Administración y Mediación de Senicare para su arbitraje definitivo.'
            : 'Hay una incidencia en curso entre la familia y el cuidador. Los fondos permanecen en custodia hasta que se alcance un acuerdo o transcurran 24h.',
        color: Colors.deepOrange.shade700,
      );
    }
    if (b.isInProgressAwaitingCheckOut) {
      if (isBookingExpired(b)) {
        return (
          label: '⏳ Turno cumplido (Falta fichar salida)',
          explanation:
              'La hora prevista de fin ya ha pasado, pero el turno sigue abierto porque aún falta registrar la salida con el botón "Finalizar Servicio y Salir".',
          color: Colors.orange.shade800,
        );
      }
      return (
        label: '🟢 En domicilio (Cuidado en curso)',
        explanation:
            'El cuidador ha registrado su llegada presencial (Check-in con QR/PIN) y se encuentra atendiendo al familiar en el domicilio.',
        color: AppTheme.secondaryColor,
      );
    }
    if (b.liveStatus == 'completed' || b.status == BookingStatus.completed) {
      return (
        label: '✅ Visita Finalizada (Custodia 24h)',
        explanation:
            'El cuidador ha finalizado el servicio y registrado su salida. El dinero se mantiene en custodia protegida durante 24 horas por si surge alguna duda o puede liberarse antes.',
        color: Colors.blue.shade700,
      );
    }
    if (b.checkInTime != null && b.status == BookingStatus.confirmed) {
      return (
        label: '✅ Visita Realizada (Custodia 24h)',
        explanation:
            'El servicio ha finalizado según el horario previsto y el dinero se mantiene en custodia durante el periodo de garantía de 24 horas.',
        color: Colors.blue.shade700,
      );
    }
    if (b.liveStatus == 'on_the_way' &&
        b.checkInTime == null &&
        !isBookingExpired(b) &&
        b.status == BookingStatus.confirmed) {
      return (
        label: '🚗 Cuidador en camino',
        explanation:
            'El cuidador ha avisado de que se encuentra desplazándose hacia el domicilio para iniciar el servicio.',
        color: Colors.orange.shade800,
      );
    }
    if (isBookingExpired(b) &&
        b.checkInTime == null &&
        b.status == BookingStatus.confirmed) {
      return (
        label: 'Caducada / No-Show',
        explanation:
            'La hora del servicio ha pasado y no se llegó a fichar la entrada mediante el código QR o PIN.',
        color: Colors.red.shade700,
      );
    }
    if (isBookingExpired(b) && b.status == BookingStatus.pending) {
      return (
        label: 'Solicitud caducada (Sin respuesta)',
        explanation:
            'Pasó la fecha y hora de la solicitud antes de que fuera confirmada.',
        color: AppTheme.slateMuted,
      );
    }

    switch (b.status) {
      case BookingStatus.pendingPayment:
        return (
          label: 'Procesando pago...',
          explanation:
              'Se está validando la retención de la tarjeta del cliente a través de la pasarela de pago segura.',
          color: Colors.orange.shade700,
        );
      case BookingStatus.pending:
        return (
          label: 'Pendiente de aceptación',
          explanation:
              'El pago está asegurado, pero el cuidador todavía tiene que aceptar la solicitud de servicio para confirmarla.',
          color: Colors.amber.shade800,
        );
      case BookingStatus.confirmed:
        return (
          label: 'Confirmada',
          explanation:
              'El cuidador ha aceptado el servicio. Solo queda esperar al día y hora acordados para realizar el fichaje presencial (Check-in).',
          color: Colors.green.shade700,
        );
      case BookingStatus.cancelled:
        return (
          label: 'Cancelada',
          explanation:
              'El servicio ha sido cancelado antes de tiempo sin penalización.',
          color: Colors.red.shade700,
        );
      case BookingStatus.cancelledLate:
        return (
          label: 'Cancelada (Tarde)',
          explanation:
              'El servicio ha sido cancelado fuera de plazo (con menos de 24h de antelación), lo cual acarrea una penalización.',
          color: Colors.red.shade800,
        );
      case BookingStatus.completed:
        return (
          label: 'Completada',
          explanation:
              'El servicio ha terminado y todo el flujo de pagos ha concluido correctamente.',
          color: Colors.blue.shade700,
        );
    }
  }

  void _showStatusExplanation(BuildContext context, Booking b) {
    final badge = _resolveStatusBadge(b);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.info_outline, color: badge.color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(badge.label, style: const TextStyle(fontSize: 18)),
            ),
          ],
        ),
        content: Text(badge.explanation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  String _getStatusText(Booking b) => _resolveStatusBadge(b).label;

  Widget _buildLiveStatusStepper(Booking b) {
    const bool step1 = true;
    final bool step2 = b.liveStatus == 'on_the_way' ||
        b.checkInTime != null ||
        b.status == BookingStatus.completed;
    final bool step3 = b.checkInTime != null ||
        b.liveStatus == 'in_progress' ||
        b.status == BookingStatus.completed;
    final bool step4 = b.status == BookingStatus.completed ||
        b.checkOutTime != null ||
        b.liveStatus == 'completed' ||
        b.escrowStatus == 'released' ||
        b.escrowStatus == 'released_manual' ||
        b.escrowStatus == 'released_auto';

    final steps = [
      {'label': 'Confirmada', 'done': step1, 'icon': Icons.event_available_rounded},
      {'label': 'En camino', 'done': step2, 'icon': Icons.directions_car_rounded},
      {'label': 'En domicilio', 'done': step3, 'icon': Icons.home_rounded},
      {'label': 'Finalizada', 'done': step4, 'icon': Icons.verified_rounded},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.backgroundNeutral,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(steps.length * 2 - 1, (idx) {
          if (idx.isOdd) {
            final nextDone = steps[(idx + 1) ~/ 2]['done'] as bool;
            return Expanded(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  height: 3,
                  color: nextDone ? AppTheme.secondaryColor : Colors.grey.shade300,
                ),
              ),
            );
          }
          final step = steps[idx ~/ 2];
          final done = step['done'] as bool;
          return Expanded(
            flex: 3,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: done ? AppTheme.secondaryColor : Colors.grey.shade300,
                  child: Icon(
                    step['icon'] as IconData,
                    size: 14,
                    color: done ? Colors.white : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  step['label'] as String,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: done ? FontWeight.w800 : FontWeight.w500,
                    color: done ? AppTheme.darkSlate : Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCareJournalSection(
    BuildContext context,
    Booking b,
    bool isClient,
    BookingNotifier state, {
    required bool isActiveTab,
  }) {
    final completedCount = b.careChecklist.where((t) => t.completed).length;
    final totalCount = b.careChecklist.length;

    const quickFamilySuggestions = [
      '💊 Dar medicación pautada',
      '🍲 Preparar comida y supervisar hidratación',
      '🚶 Paseo tranquilo de 30-40 min',
      '🧠 Conversación y estimulación cognitiva',
      '🚿 Apoyo en aseo e higiene personal',
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.primarySurface.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: const Icon(Icons.assignment_turned_in_rounded, color: AppTheme.primary, size: 22),
          title: const Text(
            'Diario y Pautas del Cuidado',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
              color: AppTheme.darkSlate,
            ),
          ),
          subtitle: Text(
            totalCount > 0
                ? '$completedCount de $totalCount tareas completadas'
                : (isClient ? 'Toca para ver o añadir tareas' : 'Sin tareas asignadas aún'),
            style: const TextStyle(fontSize: 12, color: AppTheme.slateMuted),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (b.carePhotoUrls.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: Text(
                    '📸 ${b.carePhotoUrls.length}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.darkSlate),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              const Icon(Icons.expand_more_rounded, size: 20, color: AppTheme.slateMuted),
            ],
          ),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(height: 12),
                Text(
                  isClient
                      ? 'Personaliza las tareas que necesita tu familiar. El cuidador las irá marcando en tiempo real.'
                      : 'Toca cada tarea creada por la familia cuando la completes para registrar la hora exacta.',
                  style: const TextStyle(fontSize: 12, color: AppTheme.slateMuted),
                ),
          if (b.onTheWayAt != null || b.checkInTime != null || completedCount > 0 || b.careNotes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.timeline_rounded, size: 16, color: AppTheme.secondaryColor),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '🕒 Cronología en Tiempo Real (Modo Tranquilidad)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.secondaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (b.onTheWayAt != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        '🚗 ${b.onTheWayAt!.hour.toString().padLeft(2, '0')}:${b.onTheWayAt!.minute.toString().padLeft(2, '0')} — Salida hacia el domicilio',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.darkSlate),
                      ),
                    ),
                  if (b.checkInTime != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        '📍 ${b.checkInTime!.hour.toString().padLeft(2, '0')}:${b.checkInTime!.minute.toString().padLeft(2, '0')} — Entrada verificada en casa (GPS / PIN)',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.secondaryColor),
                      ),
                    ),
                  ...b.careChecklist.where((t) => t.completed).map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        '✓ ${t.completedAt ?? 'Hecho'} — ${t.title}',
                        style: const TextStyle(fontSize: 12, color: AppTheme.darkSlate),
                      ),
                    ),
                  ),
                  if (b.careNotes.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '📝 Parte registrado: "${b.careNotes}"',
                        style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AppTheme.slateMuted),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (b.careChecklist.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                isClient
                    ? 'Aún no has añadido tareas para esta visita. Usa los botones rápidos de abajo o escribe una tarea a medida.'
                    : 'La familia aún no ha indicado tareas específicas en la checklist de esta visita.',
                style: TextStyle(
                  fontSize: 12.5,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey.shade600,
                ),
              ),
            )
          else
            ...b.careChecklist.map((item) {
              final timeFormatted = item.completedAt;
              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: (!isClient && isActiveTab)
                    ? () {
                        HapticFeedback.mediumImpact();
                        state.toggleChecklistTask(b.id, item.id);
                      }
                    : null,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: item.completed
                          ? AppTheme.secondaryColor.withValues(alpha: 0.45)
                          : Colors.grey.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        item.completed
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: item.completed ? AppTheme.secondaryColor : Colors.grey.shade400,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item.title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            decoration: item.completed ? TextDecoration.lineThrough : null,
                            color: item.completed ? Colors.grey.shade600 : AppTheme.darkSlate,
                          ),
                        ),
                      ),
                      if (timeFormatted != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.secondaryColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '✓ $timeFormatted',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.secondaryColor,
                            ),
                          ),
                        ),
                      if (isClient && isActiveTab && !item.completed)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.close_rounded, size: 17, color: Colors.grey),
                          tooltip: 'Quitar tarea',
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            state.removeChecklistTask(b.id, item.id);
                          },
                        ),
                    ],
                  ),
                ),
              );
            }),
          if (isClient && isActiveTab) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.add_rounded, size: 16, color: Colors.white),
                    backgroundColor: AppTheme.primary,
                    label: const Text(
                      'Escribir tarea a medida',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () => _showAddTaskDialog(context, b, state),
                  ),
                  const SizedBox(width: 6),
                  ...quickFamilySuggestions
                      .where((s) => !b.careChecklist.any((t) => t.title == s))
                      .map((suggestion) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ActionChip(
                              backgroundColor: Colors.white,
                              label: Text(suggestion, style: const TextStyle(fontSize: 11.5)),
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                state.addChecklistTask(b.id, suggestion);
                              },
                            ),
                          )),
                ],
              ),
            ),
          ],
          if (b.careNotes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '📝 Parte del cuidador:',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppTheme.primary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    b.careNotes,
                    style: const TextStyle(fontSize: 13, color: AppTheme.darkSlate),
                  ),
                ],
              ),
            ),
          ],
          if (b.carePhotoUrls.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.photo_camera_rounded, size: 16, color: AppTheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isClient
                        ? '📸 Fotos del cuidado (compartidas por ${b.caregiverName}):'
                        : '📸 Fotos compartidas con la familia (${b.carePhotoUrls.length}):',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppTheme.darkSlate),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 75,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: b.carePhotoUrls.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) => InkWell(
                  onTap: () => _showPhotoFullScreen(context, b.carePhotoUrls[i], b.caregiverName),
                  borderRadius: BorderRadius.circular(10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      children: [
                        Image.network(
                          b.carePhotoUrls[i],
                          width: 75,
                          height: 75,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 75,
                            height: 75,
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.photo_camera_back_rounded),
                          ),
                        ),
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.zoom_in_rounded, size: 14, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (!isClient && isActiveTab) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showEditCareNotesDialog(context, b, state),
                    icon: const Icon(Icons.edit_note_rounded, size: 18),
                    label: Text(
                      b.careNotes.isEmpty ? 'Añadir nota del día' : 'Editar nota',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _uploadCarePhoto(context, b, state),
                    icon: const Icon(Icons.add_a_photo_rounded, size: 16),
                    label: const Text('Foto cuidado', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    ],
    ),
    ),
    );
  }

  Widget? _buildPrimaryActionButton(
    BuildContext context,
    Booking b,
    bool isClient,
    BookingNotifier state,
    List<Booking> bookings,
  ) {
    final bool isBusy = _busyBookingIds.contains(b.id);
    if (isClient) {
      final seniorMode = context.watch<ConfigNotifier>().seniorMode;
      final btnPad = EdgeInsets.symmetric(vertical: seniorMode ? 14 : 12);

      final bool awaitingClientEscrowRelease = b.escrowStatus == 'held' &&
          (b.liveStatus == 'completed' || b.checkOutTime != null) &&
          b.status != BookingStatus.cancelled &&
          b.status != BookingStatus.cancelledLate;

      if (awaitingClientEscrowRelease) {
        return Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: isBusy
                    ? null
                    : () async {
                        final confirm = await CustomDialog.showConfirmation(
                          context,
                          title: 'Confirmar que todo fue bien',
                          message:
                              '¿Confirmas que ${b.caregiverName} completó bien el cuidado? Se enviará el pago al cuidador.',
                          confirmText: 'Confirmar y pagar',
                        );
                        if (confirm == true) {
                          await _runBookingAction(
                            b.id,
                            () => state.releaseEscrow(b.id),
                            successMessage:
                                '🎉 ¡Servicio confirmado y pago liberado al cuidador!',
                          );
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  padding: btnPad,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: isBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle_rounded, size: 20),
                label: Text(
                  'Confirmar y liberar pago',
                  style: TextStyle(
                    fontSize: seniorMode ? 16 : 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isBusy
                    ? null
                    : () => showDialog(
                          context: context,
                          builder: (_) => DisputeDialog(booking: b),
                        ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.deepOrange.shade700,
                  side: BorderSide(color: Colors.deepOrange.shade300),
                  padding: btnPad,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.warning_amber_rounded, size: 18),
                label: Text(
                  'Informar de un problema',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: seniorMode ? 15 : 13.5,
                  ),
                ),
              ),
            ),
          ],
        );
      }

      if (b.status == BookingStatus.confirmed &&
          b.checkInTime == null &&
          !isBookingExpired(b)) {
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => _showAccessCodeAndFridgeSheetModal(context, b),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: seniorMode ? 15 : 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.key_rounded, size: 20),
            label: Text(
              '🔑 Código de Entrada: ${b.bookingPin ?? "Ver PIN"}',
              style: TextStyle(
                fontSize: seniorMode ? 16.5 : 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
        );
      }

      if (b.status == BookingStatus.confirmed &&
          b.checkInTime != null &&
          b.liveStatus != 'completed') {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          decoration: BoxDecoration(
            color: AppTheme.secondaryColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.home_rounded, color: AppTheme.secondaryColor, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '🟢 Cuidador en casa · Cuidado en curso',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.secondaryColor,
                    fontSize: seniorMode ? 15 : 13.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }

      if ((b.status == BookingStatus.completed ||
              (b.status == BookingStatus.confirmed &&
                  b.checkInTime != null &&
                  isBookingExpired(b))) &&
          !b.isReviewed) {
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () {
              final group = bookings
                  .where((bk) =>
                      bk.caregiverId == b.caregiverId &&
                      bk.day == b.day &&
                      !bk.isReviewed &&
                      bk.status != BookingStatus.cancelled &&
                      bk.status != BookingStatus.cancelledLate)
                  .toList();
              showDialog(
                context: context,
                builder: (ctx) =>
                    ReviewDialog(bookings: group.isNotEmpty ? group : [b]),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.amber,
              foregroundColor: Colors.black87,
              padding: btnPad,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.star_rounded, size: 20),
            label: Text(
              '⭐ Valorar a ${b.caregiverName}',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: seniorMode ? 15.5 : 14,
              ),
            ),
          ),
        );
      }

      if (b.status == BookingStatus.pendingPayment && !isBookingExpired(b)) {
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: isBusy
                ? null
                : () async {
                    final confirm = await CustomDialog.showConfirmation(
                      context,
                      title: 'Descartar Intento',
                      message:
                          '¿Deseas descartar este intento de reserva no pagado?',
                      confirmText: 'Descartar',
                      isDestructive: true,
                    );
                    if (confirm == true) {
                      await _runBookingAction(
                        b.id,
                        () => state.cancelBooking(
                            b.id, 'Intento descartado por el cliente', false),
                        successMessage: 'Intento descartado.',
                        successType: SnackBarType.info,
                      );
                    }
                  },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.deepOrange.shade800,
              side: BorderSide(color: Colors.deepOrange.shade300),
              padding: btnPad,
            ),
            icon: isBusy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline_rounded, size: 18),
            label: Text(
              'Descartar intento no pagado',
              style: TextStyle(fontSize: seniorMode ? 15 : 13.5),
            ),
          ),
        );
      }

      if (b.status == BookingStatus.pending && !isBookingExpired(b)) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.hourglass_top_rounded,
                  color: Colors.amber.shade800, size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Esperando confirmación de ${b.caregiverName}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.amber.shade900,
                        fontSize: seniorMode ? 14.5 : 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tu pago queda protegido hasta que acepte.',
                      style: TextStyle(
                        fontSize: seniorMode ? 13 : 11.5,
                        color: Colors.amber.shade900.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }

      if (b.status == BookingStatus.cancelled ||
          b.status == BookingStatus.cancelledLate ||
          (b.status == BookingStatus.pending && isBookingExpired(b))) {
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _findUrgentSubstitute(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primary,
              side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.45)),
              padding: btnPad,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.search_rounded, size: 18),
            label: Text(
              'Buscar otro cuidador',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: seniorMode ? 15 : 13.5,
              ),
            ),
          ),
        );
      }

      if (b.status == BookingStatus.completed && b.isReviewed) {
        return Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _repeatBookingNextWeek(context, b),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: seniorMode ? 12 : 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.repeat_rounded, size: 17),
                label: Text(
                  'Repetir',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: seniorMode ? 14.5 : 13,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _showLegalReceiptDialog(context, b),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: seniorMode ? 12 : 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.receipt_long_rounded, size: 17),
                label: Text(
                  'Justificante',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: seniorMode ? 14.5 : 13,
                  ),
                ),
              ),
            ),
          ],
        );
      }

      return null;
    }

    // Acciones para el cuidador
    if (b.status == BookingStatus.pending && !isBookingExpired(b)) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: isBusy
                  ? null
                  : () async {
                      final confirm = await CustomDialog.showConfirmation(
                        context,
                        title: 'Rechazar Solicitud',
                        message:
                            '¿Seguro que no puedes atender este servicio? La reserva se cancelará y los fondos se liberarán para la familia.',
                        confirmText: 'Rechazar',
                        isDestructive: true,
                      );
                      if (confirm == true) {
                        await _runBookingAction(
                          b.id,
                          () => state.rejectBooking(b.id),
                          successMessage: 'Solicitud rechazada.',
                          successType: SnackBarType.info,
                        );
                      }
                    },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              child: const Text('Rechazar'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: isBusy
                  ? null
                  : () async {
                      HapticFeedback.mediumImpact();
                      await _runBookingAction(
                        b.id,
                        () => state.confirmBooking(b.id),
                        successMessage:
                            '✅ ¡Servicio aceptado! Recuerda registrar tu llegada.',
                      );
                    },
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              child: isBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Aceptar',
                      style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      );
    }
    if (b.status == BookingStatus.confirmed &&
        b.checkInTime == null &&
        !isBookingExpired(b)) {
      return Column(
        children: [
          if (b.liveStatus != 'on_the_way') ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isBusy
                    ? null
                    : () async {
                        HapticFeedback.mediumImpact();
                        await _runBookingAction(
                          b.id,
                          () => state.markOnTheWay(b.id),
                          successMessage:
                              '🚗 Familia avisada de que estás en camino al domicilio.',
                        );
                      },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange.shade800,
                  side: BorderSide(color: Colors.orange.shade400, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: isBusy
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.orange.shade800,
                        ),
                      )
                    : const Icon(Icons.directions_car_rounded, size: 18),
                label: const Text('🚗 Avisar a familia: Estoy en camino'),
              ),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: isBusy
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ScannerScreen(booking: b),
                        ),
                      );
                    },
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              icon: const Icon(Icons.qr_code_scanner, size: 18),
              label: const Text(
                'Fichar Llegada (QR o PIN)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      );
    }
    if (b.status == BookingStatus.confirmed &&
        b.checkInTime != null &&
        b.liveStatus != 'completed') {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: isBusy
              ? null
              : () async {
                  final confirm = await CustomDialog.showConfirmation(
                    context,
                    title: 'Finalizar Servicio',
                    message:
                        '¿Confirmas que has terminado el turno y vas a salir del domicilio? Se registrará la salida y la familia recibirá el aviso.',
                    confirmText: 'Finalizar y Salir',
                    cancelText: 'Continuar turno',
                  );
                  if (confirm == true && context.mounted) {
                    HapticFeedback.heavyImpact();
                    await _runBookingAction(
                      b.id,
                      () => state.completeService(b.id),
                      successMessage:
                          '🎉 ¡Servicio finalizado con éxito! Buen descanso.',
                    );
                  }
                },
          style: FilledButton.styleFrom(
            backgroundColor: Colors.green.shade700,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
          ),
          icon: isBusy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check_circle_outline_rounded, size: 18),
          label: const Text(
            '🏁 Finalizar Servicio y Salir',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
    }
    return null;
  }

  Widget _buildDisputeBanner(
      BuildContext context, Booking b, bool isClient, BookingNotifier state) {
    final bool isBusy = _busyBookingIds.contains(b.id);
    if (!isClient && b.disputeEscalated != true) {
      final double proposedRefund = b.disputeAmount ?? 0.0;
      final double estimatedNet = b.estimateNetAfterDispute(proposedRefund);
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'El cliente ha propuesto un reembolso de ${proposedRefund.toStringAsFixed(2)} €.\nTu ingreso neto estimado restante será de ${estimatedNet.toStringAsFixed(2)} €.',
              style: const TextStyle(
                color: Colors.deepOrange,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: isBusy
                        ? null
                        : () async {
                            bool? confirm = await CustomDialog.showConfirmation(
                              context,
                              title: 'Rechazar Propuesta',
                              message:
                                  'Si rechazas, el caso se escalará al equipo de Administración para su arbitraje. ¿Continuar?',
                              confirmText: 'Escalar',
                              isDestructive: true,
                            );
                            if (confirm == true) {
                              await _runBookingAction(
                                b.id,
                                () => state.escalateDispute(b.id),
                                successMessage:
                                    'Disputa escalada a Administración.',
                                successType: SnackBarType.info,
                              );
                            }
                          },
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Rechazar (Escalar)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: isBusy
                        ? null
                        : () async {
                            bool? confirm = await CustomDialog.showConfirmation(
                              context,
                              title: 'Aceptar Propuesta',
                              message:
                                  'Al aceptar, se aplicarán los pagos acordados y la reserva quedará resuelta definitivamente. ¿Continuar?',
                              confirmText: 'Aceptar',
                            );
                            if (confirm == true) {
                              await _runBookingAction(
                                b.id,
                                () => state.acceptDisputeProposal(b.id),
                                successMessage:
                                    'Propuesta aceptada, pago en proceso.',
                              );
                            }
                          },
                    style: FilledButton.styleFrom(backgroundColor: Colors.green),
                    child: isBusy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Aceptar Propuesta'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (isClient && b.disputeEscalated != true) {
      return Container(
        padding: const EdgeInsets.all(12),
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade300),
        ),
        child: Text(
          'Has propuesto un reembolso de ${b.disputeAmount?.toStringAsFixed(2) ?? "0.00"} €.\nEsperando respuesta del cuidador (máx 24h).',
          style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.w600, fontSize: 12.5),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade300),
      ),
      child: const Text(
        'Disputa escalada al equipo de Administración. Te contactaremos pronto.',
        style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600, fontSize: 12.5),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildNoShowBanner(BuildContext context, Booking b) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_off_outlined, size: 18, color: Colors.red.shade800),
              const SizedBox(width: 6),
              Text(
                'Incomparecencia / Sin Check-in',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red.shade900),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'El cuidador no registró su llegada presencial. Tu importe (${b.totalPaid.toStringAsFixed(2)} €) está asegurado y el reembolso total se tramita automáticamente.',
            style: TextStyle(fontSize: 12, color: Colors.red.shade900, height: 1.3),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _findUrgentSubstitute(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade900,
                side: BorderSide(color: Colors.red.shade300),
              ),
              icon: const Icon(Icons.flash_on_rounded, size: 16),
              label: const Text('🚨 Buscar un cuidador de sustitución hoy', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  void _showAccessCodeAndFridgeSheetModal(BuildContext context, Booking b) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.88,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '🔑 Acceso al Domicilio',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppTheme.darkSlate),
                ),
                const SizedBox(height: 6),
                Text(
                  'Enséñale estos datos a ${b.caregiverName} cuando llegue a casa para validar su entrada:',
                  style: const TextStyle(fontSize: 13, color: AppTheme.slateMuted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.primarySurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'CÓDIGO PIN DE ENTRADA',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppTheme.primary, letterSpacing: 1),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        b.bookingPin ?? "----",
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 10,
                          color: AppTheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Díctale estos 4 números en persona al llegar',
                        style: TextStyle(fontSize: 12, color: AppTheme.darkSlate),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.borderSubtle),
                    ),
                    child: QrImageView(
                      data: b.id,
                      version: QrVersions.auto,
                      size: 128.0,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'O también puede escanear este código QR con su móvil',
                  style: TextStyle(fontSize: 11.5, color: AppTheme.slateMuted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showFridgeSheetModal(context, b);
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.primary, width: 1.2),
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.kitchen_rounded, size: 18, color: AppTheme.primary),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Ver Ficha para la Nevera / WhatsApp',
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cerrar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showBookingMoreOptionsModal(
    BuildContext context,
    Booking b,
    bool isClient,
    BookingNotifier state, {
    ClientProfile? clientProfile,
  }) {
    HapticFeedback.mediumImpact();
    final bool canCancel = isClient &&
        (b.status == BookingStatus.pending || b.status == BookingStatus.confirmed) &&
        b.checkInTime == null &&
        !isBookingExpired(b);

    final bool canDiscard = isClient && b.status == BookingStatus.pendingPayment;
    final bool canTip = isClient && b.tipAmount == 0 && (b.status == BookingStatus.completed || b.isReviewed);
    final bool canRepeat = isClient && b.status != BookingStatus.cancelled && b.status != BookingStatus.cancelledLate;
    final bool canEscrowRelease = isClient && b.escrowStatus == 'held' && b.checkInTime != null;
    final bool canOpenMaps = !isClient &&
        b.status == BookingStatus.confirmed &&
        ((b.clientLatitude != null && b.clientLongitude != null) ||
            (clientProfile != null &&
                (clientProfile.homeAddress.trim().isNotEmpty ||
                    clientProfile.latitude != null)));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.tune_rounded, color: AppTheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Opciones del servicio',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.darkSlate),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 18),
              if (canOpenMaps)
                ListTile(
                  leading: const Icon(Icons.directions_rounded, color: AppTheme.primary),
                  title: const Text('Cómo llegar al domicilio', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: const Text('Abrir ruta en Google Maps'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openMapsForBooking(b, clientProfile);
                  },
                ),
              if (b.status == BookingStatus.confirmed)
                ListTile(
                  leading: const Icon(Icons.event_available_rounded, color: AppTheme.primary),
                  title: const Text('Añadir a Google Calendar / Agenda', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: const Text('Guarda un recordatorio en tu calendario personal'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _addToGoogleCalendar(context, b, isClient);
                  },
                ),
              if (isClient && b.status == BookingStatus.confirmed) ...[
                ListTile(
                  leading: const Icon(Icons.share_rounded, color: AppTheme.primary),
                  title: const Text('Compartir enlace familiar', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: const Text('Envía el seguimiento del turno a otros familiares'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _shareLiveTrackingWithFamily(context, b);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.kitchen_rounded, color: AppTheme.primary),
                  title: const Text('Ficha para la Nevera', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: const Text('Resumen con teléfonos y PIN para imprimir o WhatsApp'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showFridgeSheetModal(context, b);
                  },
                ),
              ],
              if (canRepeat)
                ListTile(
                  leading: const Icon(Icons.repeat_rounded, color: AppTheme.primary),
                  title: const Text('Repetir servicio la próxima semana', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: const Text('Reserva el mismo horario con el mismo cuidador'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _repeatBookingNextWeek(context, b);
                  },
                ),
              if (isClient && b.status != BookingStatus.cancelled && b.status != BookingStatus.cancelledLate)
                ListTile(
                  leading: const Icon(Icons.receipt_long_rounded, color: AppTheme.darkSlate),
                  title: const Text('Descargar Justificante Legal', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: const Text('Documento oficial con seguro RC y horas prestadas'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showLegalReceiptDialog(context, b);
                  },
                ),
              if (canTip)
                ListTile(
                  leading: const Text('☕', style: TextStyle(fontSize: 20)),
                  title: const Text('Enviar propina de agradecimiento', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.secondaryColor)),
                  subtitle: const Text('100% íntegra para el cuidador sin comisiones'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showQuickTipDialog(context, b, state);
                  },
                ),
              if (canEscrowRelease) ...[
                ListTile(
                  leading: const Icon(Icons.check_circle_outline_rounded, color: Colors.green),
                  title: const Text('Confirmar servicio y liberar pago', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.green)),
                  subtitle: const Text('Confirmar que todo fue bien sin esperar las 24h'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final confirm = await CustomDialog.showConfirmation(
                      context,
                      title: 'Liberar Pago al Cuidador',
                      message: '¿Confirmas que el servicio fue satisfactorio? Se transferirán inmediatamente los fondos al cuidador (${b.caregiverPayout > 0 ? b.caregiverPayout.toStringAsFixed(2) : b.cost.toStringAsFixed(2)} €).',
                      confirmText: 'Liberar Ahora',
                    );
                    if (confirm == true) {
                      await _runBookingAction(
                        b.id,
                        () => state.releaseEscrow(b.id),
                        successMessage:
                            '🎉 ¡Pago liberado al cuidador con éxito! Gracias por tu confirmación.',
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.warning_amber_rounded, color: Colors.deepOrange),
                  title: const Text('Informar de un problema', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.deepOrange)),
                  subtitle: const Text('Detener el pago automático y solicitar revisión'),
                  onTap: () {
                    Navigator.pop(ctx);
                    showDialog(context: context, builder: (_) => DisputeDialog(booking: b));
                  },
                ),
              ],
              if (isClient &&
                  (b.status == BookingStatus.cancelled ||
                      b.status == BookingStatus.cancelledLate ||
                      (b.status == BookingStatus.pending && isBookingExpired(b))))
                ListTile(
                  leading: const Icon(Icons.flash_on_rounded, color: Colors.orange),
                  title: const Text('Buscar cuidador sustituto urgente', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.orange)),
                  subtitle: const Text('Encuentra profesionales disponibles hoy cerca de tu casa'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _findUrgentSubstitute(context);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.sos_rounded, color: Colors.red),
                title: const Text('Contacto de Emergencia / SOS', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.red)),
                subtitle: const Text('Llamada rápida al 112 o contacto directo'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showSosQuickContactModal(context, b, isClient);
                },
              ),
              if (canDiscard) ...[
                const Divider(height: 12),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                  title: const Text('Descartar intento de reserva', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.red)),
                  subtitle: const Text('Libera el horario si no vas a completar el pago'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final confirm = await CustomDialog.showConfirmation(
                      context,
                      title: 'Descartar Intento',
                      message: '¿Deseas descartar este intento de reserva no pagado?',
                      confirmText: 'Descartar',
                      isDestructive: true,
                    );
                    if (confirm == true) {
                      await _runBookingAction(
                        b.id,
                        () => state.cancelBooking(
                            b.id, 'Intento descartado por el cliente', false),
                        successMessage: 'Intento de reserva descartado.',
                        successType: SnackBarType.info,
                      );
                    }
                  },
                ),
              ],
              if (canCancel) ...[
                const Divider(height: 12),
                ListTile(
                  leading: const Icon(Icons.cancel_outlined, color: Colors.red),
                  title: const Text('Cancelar Reserva', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.red)),
                  subtitle: const Text('Reembolso gratuito si faltan más de 24h'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final now = DateTime.now();
                    bool isLate = false;
                    DateTime? slotDt;
                    try {
                      final dp = b.day.split('-');
                      final tp = b.slot.split('-')[0].split(':');
                      slotDt = DateTime(int.parse(dp[0]), int.parse(dp[1]), int.parse(dp[2]), int.parse(tp[0]), int.parse(tp[1]));
                    } catch (_) {}

                    if (slotDt != null) {
                      final diffHours = slotDt.difference(now).inHours;
                      if (diffHours < 24) isLate = true;
                    }

                    bool? confirm = await CustomDialog.showConfirmation(
                      context,
                      title: 'Cancelar Reserva',
                      message: isLate
                          ? 'Al cancelar con menos de 24h de antelación, se aplicará una penalización: se te reembolsará el 45% del importe y el resto cubrirá la compensación del cuidador y los gastos de gestión.'
                          : 'Cancelación gratuita (>24h de antelación): Se te reembolsará el 100% del importe íntegramente a tu método de pago original sin ninguna penalización.',
                      cancelText: 'Mantener',
                      confirmText: 'Cancelar Reserva',
                      isDestructive: true,
                    );

                    if (confirm == true) {
                      await _runBookingAction(
                        b.id,
                        () => state.cancelBooking(
                            b.id, 'Cancelado por el cliente', isLate),
                        successMessage: 'Reserva cancelada correctamente.',
                        successType: SnackBarType.info,
                      );
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAddTaskDialog(
    BuildContext context,
    Booking b,
    BookingNotifier state,
  ) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => const _BookingTextPromptDialog(
        title: 'Añadir tarea para el cuidador',
        hintText: 'Ej. Pastilla tensión a las 13:00, regar plantas...',
        confirmLabel: 'Añadir a la Checklist',
      ),
    );
    if (result != null && result.isNotEmpty) {
      HapticFeedback.mediumImpact();
      await _runBookingAction(
        b.id,
        () => state.addChecklistTask(b.id, result),
        successMessage: 'Tarea añadida a la lista del cuidado.',
      );
    }
  }

  Future<void> _showEditCareNotesDialog(
    BuildContext context,
    Booking b,
    BookingNotifier state,
  ) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _BookingTextPromptDialog(
        title: '📝 Resumen del Cuidado',
        initialValue: b.careNotes,
        hintText:
            'Escribe cómo se encuentra el familiar hoy, qué ha comido, estado de ánimo...',
        confirmLabel: 'Guardar Nota',
        maxLines: 4,
        allowEmptySubmit: true,
      ),
    );
    if (result != null) {
      HapticFeedback.mediumImpact();
      await state.updateCareNotes(b.id, result);
      if (context.mounted) {
        CustomSnackBar.show(
          context,
          message: 'Resumen guardado en el Diario del Cuidado.',
          type: SnackBarType.success,
        );
      }
    }
  }

  Future<void> _uploadCarePhoto(
    BuildContext context,
    Booking b,
    BookingNotifier state,
  ) async {
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  'Subir foto al Diario del Cuidado',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_rounded,
                    color: AppTheme.primary),
                title: const Text('Hacer foto ahora con la cámara'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded,
                    color: AppTheme.primary),
                title: const Text('Elegir de la galería'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return;

    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source, imageQuality: 75);
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      final ref = FirebaseStorage.instance
          .ref()
          .child('care_journal/${b.id}/${DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      await state.addCarePhotoUrl(b.id, url);
      if (context.mounted) {
        CustomSnackBar.show(
          context,
          message: '📸 Foto subida al Diario del Cuidado para la familia.',
          type: SnackBarType.success,
        );
      }
    } catch (e) {
      if (context.mounted) {
        CustomSnackBar.show(
          context,
          message: 'No se pudo adjuntar la foto: $e',
          type: SnackBarType.error,
        );
      }
    }
  }

  Future<void> _shareLiveTrackingWithFamily(BuildContext context, Booking b) async {
    HapticFeedback.mediumImpact();
    final completed = b.careChecklist.where((t) => t.completed).length;
    final total = b.careChecklist.length;
    final pinLine = (b.checkInTime == null && (b.bookingPin?.isNotEmpty ?? false))
        ? '🔑 Código PIN de entrada (si recibes al cuidador en casa): ${b.bookingPin}\n'
        : '';
    final summaryText = '🛡️ Seguimiento SeniCare en Tiempo Real\n'
        '👩‍⚕️ Cuidador/a: ${b.caregiverName}\n'
        '📅 Fecha: ${_formatDay(b.day)} (${b.slot})\n'
        '📍 Estado: ${_getStatusText(b)}\n'
        '$pinLine'
        '📋 Checklist familiar: $completed de $total tareas completadas\n'
        '${b.careNotes.isNotEmpty ? "📝 Parte del día: ${b.careNotes}\n" : ""}'
        '🔗 Ver en vivo: https://senicare-3342d.web.app/#/tracking/${b.id}';

    await Clipboard.setData(ClipboardData(text: summaryText));
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.share_rounded, color: AppTheme.primary),
            SizedBox(width: 8),
            Expanded(child: Text('Enlace copiado para familiares')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hemos copiado el parte en tiempo real al portapapeles. Pégalo en vuestro grupo de WhatsApp familiar para que tus hermanos o familiares sigan la visita:',
              style: TextStyle(fontSize: 13, color: AppTheme.slateMuted),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.backgroundNeutral,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.borderSubtle),
              ),
              child: Text(
                summaryText,
                style: const TextStyle(fontSize: 12, height: 1.4),
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Listo'),
          ),
        ],
      ),
    );
  }

  Future<void> _showSosQuickContactModal(
    BuildContext context,
    Booking b,
    bool isClient,
  ) async {
    HapticFeedback.heavyImpact();
    final clientProfile = await _getClientProfile(b.clientId);
    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.sos_rounded, color: Colors.red.shade700, size: 26),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Contacto Rápido y Emergencias',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                        Text(
                          'Asistencia inmediata durante el servicio activo',
                          style: TextStyle(fontSize: 12.5, color: AppTheme.slateMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (clientProfile != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundNeutral,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '📍 Domicilio: ${clientProfile.homeAddress.isNotEmpty ? clientProfile.homeAddress : "No especificado"}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '🩺 Indicaciones médicas: ${clientProfile.patientDetails.isNotEmpty ? clientProfile.patientDetails : "Sin observaciones médicas registradas"}',
                        style: const TextStyle(fontSize: 13, color: AppTheme.darkSlate),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final uri = Uri.parse('tel:112');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.local_hospital_rounded),
                  label: const Text('Llamar al 112 (Emergencias Sanitarias)'),
                ),
              ),
              const SizedBox(height: 10),
              if (isClient)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      final auth = context.read<AuthNotifier>();
                      final familyName =
                          (auth.currentClient?.name.trim().isNotEmpty ?? false)
                              ? auth.currentClient!.name
                              : 'Familia';
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            caregiverId: b.caregiverId,
                            caregiverName: b.caregiverName,
                            clientId: b.clientId,
                            clientName: familyName,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.chat_rounded),
                    label: Text('Escribir por chat a ${b.caregiverName}'),
                  ),
                )
              else if (clientProfile != null && clientProfile.phone.isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final uri = Uri.parse('tel:${clientProfile.phone}');
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      }
                    },
                    icon: const Icon(Icons.phone_in_talk_rounded),
                    label: Text('Llamar a la familia (${clientProfile.phone})'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addToGoogleCalendar(BuildContext context, Booking b, bool isClient) async {
    HapticFeedback.selectionClick();
    try {
      final dayParts = b.day.split('-');
      final year = int.parse(dayParts[0]);
      final month = int.parse(dayParts[1]);
      final day = int.parse(dayParts[2]);

      int startHour = 9, startMin = 0, endHour = 11, endMin = 0;
      if (b.slot.contains('-')) {
        final parts = b.slot.split('-');
        final sp = parts[0].split(':');
        final ep = parts[1].split(':');
        startHour = int.parse(sp[0]);
        startMin = int.parse(sp[1]);
        endHour = int.parse(ep[0]);
        endMin = int.parse(ep[1]);
      } else if (b.slot.contains(':')) {
        final sp = b.slot.split(':');
        startHour = int.parse(sp[0]);
        startMin = int.parse(sp[1]);
        endHour = (startHour + 1).clamp(0, 23);
      }

      final startDt = DateTime(year, month, day, startHour, startMin);
      final endDt = DateTime(year, month, day, endHour, endMin);
      String fmt(DateTime dt) =>
          '${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}T${dt.hour.toString().padLeft(2, '0')}${dt.minute.toString().padLeft(2, '0')}00';

      final title = Uri.encodeComponent(
        isClient
            ? 'SeniCare: Cuidado con ${b.caregiverName}'
            : 'SeniCare: Servicio a domicilio (${b.slot})',
      );
      final details = Uri.encodeComponent(
        'Servicio confirmado en SeniCare.\n'
        'Horario: ${b.slot}\n'
        '${isClient && b.bookingPin != null ? "PIN de entrada: ${b.bookingPin}\n" : ""}'
        'Checklist familiar: ${b.careChecklist.map((t) => t.title).join(", ")}',
      );
      final url = Uri.parse(
        'https://calendar.google.com/calendar/render?action=TEMPLATE&text=$title&dates=${fmt(startDt)}/${fmt(endDt)}&details=$details',
      );
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else if (context.mounted) {
        CustomSnackBar.show(
          context,
          message: 'No se pudo abrir el calendario en este dispositivo.',
          type: SnackBarType.info,
        );
      }
    } catch (e) {
      if (context.mounted) {
        CustomSnackBar.show(
          context,
          message: 'No se pudo generar el evento de calendario: $e',
          type: SnackBarType.error,
        );
      }
    }
  }

  Future<void> _repeatBookingNextWeek(BuildContext context, Booking b) async {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: AppTheme.primarySurface,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.repeat_rounded, color: AppTheme.primary, size: 26),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Plan de Cuidado Continuo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        Text('Reserva asegurada semanal con pago protegido', style: TextStyle(fontSize: 12.5, color: AppTheme.slateMuted)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundNeutral,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.borderSubtle),
                ),
                child: const Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.shield_outlined, color: AppTheme.primary, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Pago protegido semanal: No pagas todo por adelantado. Sólo se retiene el saldo 24h antes de cada visita.',
                            style: TextStyle(fontSize: 12.5, color: AppTheme.darkSlate),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.event_repeat_rounded, color: AppTheme.primary, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '0% Permanencia: Puedes pausar o cancelar cualquier semana con más de 24h sin ningún coste.',
                            style: TextStyle(fontSize: 12.5, color: AppTheme.darkSlate),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _executeRepeatBooking(context, b);
                  },
                  icon: const Icon(Icons.calendar_today_rounded, size: 18),
                  label: Text('Repetir la próxima semana con ${b.caregiverName}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _executeRepeatBooking(BuildContext context, Booking b) async {
    HapticFeedback.mediumImpact();
    try {
      final caregiver = await DependencyInjection.caregivers.getCaregiver(b.caregiverId);
      if (caregiver == null) {
        if (context.mounted) {
          CustomSnackBar.show(
            context,
            message: 'No se ha encontrado el perfil activo del cuidador.',
            type: SnackBarType.error,
          );
        }
        return;
      }

      DateTime baseDate;
      try {
        baseDate = DateFormat('yyyy-MM-dd').parse(b.day);
      } catch (_) {
        baseDate = DateTime.now();
      }
      DateTime nextDate = baseDate.add(const Duration(days: 7));
      final now = DateTime.now();
      while (nextDate.isBefore(DateTime(now.year, now.month, now.day + 1))) {
        nextDate = nextDate.add(const Duration(days: 7));
      }
      final nextDateStr =
          '${nextDate.year}-${nextDate.month.toString().padLeft(2, '0')}-${nextDate.day.toString().padLeft(2, '0')}';

      int startHour = 10;
      int endHour = 12;
      if (b.slot.contains('-')) {
        final parts = b.slot.split('-');
        startHour = int.tryParse(parts[0].split(':')[0]) ?? 10;
        endHour = int.tryParse(parts[1].split(':')[0]) ?? (startHour + 2);
      } else if (b.slot.contains(':')) {
        startHour = int.tryParse(b.slot.split(':')[0]) ?? 10;
        endHour = startHour + 1;
      }
      if (endHour <= startHour) endHour = startHour + 1;

      final slots = <TimeSlot>[];
      for (int h = startHour; h < endHour; h++) {
        slots.add(TimeSlot(
          id: 'repeat_${nextDateStr}_$h',
          dateTime: DateTime(nextDate.year, nextDate.month, nextDate.day, h, 0),
        ));
      }

      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentScreen(
            caregiver: caregiver,
            dateString: nextDateStr,
            slots: slots,
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        CustomSnackBar.show(
          context,
          message: 'Error al preparar la repetición de reserva: $e',
          type: SnackBarType.error,
        );
      }
    }
  }

  Future<void> _showQuickTipDialog(
    BuildContext context,
    Booking b,
    BookingNotifier state,
  ) async {
    double selectedTip = 5.0;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Text('☕', style: TextStyle(fontSize: 22)),
              SizedBox(width: 8),
              Expanded(child: Text('Agradecer con una propina')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'El 100% de la propina va íntegro para ${b.caregiverName}, sin ninguna comisión de plataforma.',
                style: const TextStyle(fontSize: 13, color: AppTheme.slateMuted),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [2.0, 5.0, 10.0].map((amount) {
                  final isSelected = selectedTip == amount;
                  return ChoiceChip(
                    label: Text('+${amount.toInt()} €'),
                    selected: isSelected,
                    selectedColor: AppTheme.secondaryColor.withValues(alpha: 0.2),
                    checkmarkColor: AppTheme.secondaryColor,
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isSelected ? AppTheme.secondaryColor : AppTheme.darkSlate,
                    ),
                    onSelected: (_) => setDialogState(() => selectedTip = amount),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                HapticFeedback.mediumImpact();
                Navigator.pop(ctx);
                await _runBookingAction(
                  b.id,
                  () => state.addTipToBooking(b.id, selectedTip),
                  successMessage:
                      '☕ ¡Gracias! Has enviado +${selectedTip.toInt()} € íntegros a ${b.caregiverName}.',
                );
              },
              style: FilledButton.styleFrom(backgroundColor: AppTheme.secondaryColor),
              child: Text('Enviar +${selectedTip.toInt()} €'),
            ),
          ],
        ),
      ),
    );
  }

  void _findUrgentSubstitute(BuildContext context) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.bolt_rounded, color: Colors.red.shade700, size: 28),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sustitución Express (<2 horas)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        Text('Encuentra un cuidador verificado de inmediato', style: TextStyle(fontSize: 12.5, color: AppTheme.slateMuted)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Tu familiar no se quedará desatendido. El importe abonado permanece protegido y puedes reasignarlo a un nuevo profesional disponible hoy mismo.',
                style: TextStyle(fontSize: 13, color: AppTheme.darkSlate, height: 1.4),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    try {
                      final caregiverNotifier = context.read<CaregiverNotifier>();
                      caregiverNotifier.resetFilters();
                      caregiverNotifier.setSortOption(CaregiverSortOption.distanceAsc);
                    } catch (_) {}
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(
                            title: const Text('🚨 Cuidadores Cercanos Disponibles Hoy'),
                          ),
                          body: const ExplorerScreen(),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.near_me_rounded),
                  label: const Text('Ver Cuidadores Cercanos Disponibles Hoy', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CreateOfferScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add_task_rounded),
                  label: const Text('Publicar Oferta Urgente en el Tablón', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showLegalReceiptDialog(BuildContext context, Booking b) async {
    HapticFeedback.selectionClick();
    final profile = await _getClientProfile(b.clientId);
    if (!context.mounted) return;
    final receiptNumber = 'SC-${b.day.replaceAll("-", "")}-${b.id.substring(0, b.id.length > 5 ? 5 : b.id.length).toUpperCase()}';
    final receiptText = '🧾 JUSTIFICANTE OFICIAL DE SERVICIO ASISTENCIAL — SENICARE\n'
        'Nº Justificante: $receiptNumber\n'
        'Plataforma: SeniCare Asistencia Domiciliaria S.L. (Directiva Europea DAC7 / RGPD Art. 9)\n'
        '────────────────────────────────────────\n'
        'Titular / Familia: ${profile?.name ?? b.clientId}\n'
        'Domicilio: ${profile?.homeAddress.isNotEmpty == true ? profile!.homeAddress : "Registrado en cuenta"}\n'
        'Profesional Sociosanitario: ${b.caregiverName} (ID: ${b.caregiverId})\n'
        'Fecha y Horario: ${_formatDay(b.day)} (${b.slot})\n'
        '────────────────────────────────────────\n'
        'Honorarios Asistenciales: ${b.cost.toStringAsFixed(2)} €\n'
        'Gestión, Seguro RC y Cobertura (3%): ${b.clientFee.toStringAsFixed(2)} €\n'
        '${b.tipAmount > 0 ? "Propina voluntaria (100% cuidador): ${b.tipAmount.toStringAsFixed(2)} €\n" : ""}'
        'TOTAL ABONADO: ${(b.totalPaid + b.tipAmount).toStringAsFixed(2)} €\n'
        'Ref. Transacción Stripe Escrow: ${b.paymentIntentId ?? "Verificada"}\n'
        'Estado: Servicio prestado y verificado en domicilio.';

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.receipt_long_rounded, color: AppTheme.primary),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Justificante Oficial de Gasto',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Válido como comprobante para ayudas a la Ley de Dependencia, seguros privados de salud o deducciones autonómicas:',
                style: TextStyle(fontSize: 12.5, color: AppTheme.slateMuted),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundNeutral,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.borderSubtle),
                ),
                child: Text(
                  receiptText,
                  style: const TextStyle(fontSize: 11.5, height: 1.45, fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: receiptText));
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                CustomSnackBar.show(
                  context,
                  message: '🧾 Justificante oficial copiado al portapapeles para guardar o imprimir.',
                  type: SnackBarType.success,
                );
              }
            },
            icon: const Icon(Icons.copy_rounded, size: 17),
            label: const Text('Copiar / Descargar'),
          ),
        ],
      ),
    );
  }

  Future<void> _showFridgeSheetModal(BuildContext context, Booking b) async {
    HapticFeedback.mediumImpact();
    final profile = await _getClientProfile(b.clientId);
    if (!context.mounted) return;

    final pinText = b.bookingPin ?? "Sin PIN";
    final home = profile?.homeAddress.isNotEmpty == true ? profile!.homeAddress : "Domicilio familiar";
    final phone = profile?.phone.isNotEmpty == true ? profile!.phone : "Teléfono familiar registrado";
    final medicalNotes = profile?.patientDetails.isNotEmpty == true ? profile!.patientDetails : "Sin pautas médicas específicas";
    final tasksList = b.careChecklist.isNotEmpty
        ? b.careChecklist.map((t) => "• ${t.title}").join("\n")
        : "• Compañía, atención general y supervisión en el hogar";

    final fridgeSheetText = '🧊 FICHA DE CUIDADOS PARA LA NEVERA · SENICARE\n'
        '================================================\n'
        '🏠 Domicilio: $home\n'
        '👩‍⚕️ Cuidador/a: ${b.caregiverName}\n'
        '📅 Fecha de Visita: ${_formatDay(b.day)} (${b.slot})\n'
        '🔑 CÓDIGO PIN DE ENTRADA: $pinText\n'
        '(Díselo al cuidador al abrir la puerta para iniciar el servicio)\n\n'
        '🚨 TELÉFONOS DE CONTACTO Y EMERGENCIAS:\n'
        '• Emergencias Médicas Nacionales: 112\n'
        '• Familia Directa: $phone\n\n'
        '💊 PAUTAS Y MEDICACIÓN:\n'
        '$medicalNotes\n\n'
        '📋 TAREAS PROGRAMADAS:\n'
        '$tasksList\n'
        '================================================\n'
        'SeniCare: Servicio con Seguro de Responsabilidad Civil y Custodia de Pago.';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.primarySurface,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                      ),
                      child: const Icon(Icons.kitchen_rounded, color: AppTheme.primary, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Ficha para la Nevera', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.darkSlate)),
                          Text('Imprime o comparte para tenerla visible en la cocina', style: TextStyle(fontSize: 12.5, color: AppTheme.slateMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.amber.shade300, width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.amber.shade100.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Text('🧲', style: TextStyle(fontSize: 18)),
                              SizedBox(width: 6),
                              Text('SENICARE · HOJA DE TURNO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.darkSlate)),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.borderSubtle),
                            ),
                            child: Text(
                              _formatDay(b.day),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5, color: AppTheme.primary),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      Text('📍 Domicilio: $home', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('👩‍⚕️ Cuidador/a: ${b.caregiverName} (${b.slot})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.primary, width: 1.5),
                        ),
                        child: Column(
                          children: [
                            const Text('🔑 CÓDIGO PIN DE ENTRADA', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                            const SizedBox(height: 4),
                            Text(
                              pinText,
                              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 8, color: AppTheme.primary),
                            ),
                            const Text('Dile estos números al cuidador cuando llegue a casa', style: TextStyle(fontSize: 11, color: AppTheme.slateMuted)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('🚨 TELÉFONOS DE CONTACTO:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.red)),
                      const SizedBox(height: 2),
                      const Text('• 112 (Emergencias Médicas / Sanitarias)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                      Text('• Familia Directa: $phone', style: const TextStyle(fontSize: 12.5)),
                      if (profile != null && profile.patientDetails.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text('💊 PAUTAS Y MEDICACIÓN:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.darkSlate)),
                        const SizedBox(height: 2),
                        Text(profile.patientDetails, style: const TextStyle(fontSize: 12.5, color: AppTheme.darkSlate)),
                      ],
                      if (b.careChecklist.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text('📋 CHECKLIST DEL SERVICIO:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.darkSlate)),
                        const SizedBox(height: 2),
                        ...b.careChecklist.map((t) => Text('• ${t.title}', style: const TextStyle(fontSize: 12.5))),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          HapticFeedback.selectionClick();
                          await Clipboard.setData(ClipboardData(text: fridgeSheetText));
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (context.mounted) {
                            CustomSnackBar.show(
                              context,
                              message: '📋 Ficha de la nevera copiada para imprimir o pegar.',
                              type: SnackBarType.success,
                            );
                          }
                        },
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text('Copiar Ficha', style: TextStyle(fontSize: 12.5)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () async {
                          HapticFeedback.mediumImpact();
                          final encoded = Uri.encodeComponent(fridgeSheetText);
                          final whatsappUrl = Uri.parse('whatsapp://send?text=$encoded');
                          final webUrl = Uri.parse('https://wa.me/?text=$encoded');
                          if (await canLaunchUrl(whatsappUrl)) {
                            await launchUrl(whatsappUrl);
                          } else if (await canLaunchUrl(webUrl)) {
                            await launchUrl(webUrl, mode: LaunchMode.externalApplication);
                          } else {
                            await Clipboard.setData(ClipboardData(text: fridgeSheetText));
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (context.mounted) {
                              CustomSnackBar.show(
                                context,
                                message: 'Copiado al portapapeles para WhatsApp.',
                                type: SnackBarType.info,
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.send_rounded, size: 16),
                        label: const Text('WhatsApp', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPhotoFullScreen(BuildContext context, String photoUrl, String caregiverName) {
    HapticFeedback.selectionClick();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: AppTheme.darkSlate,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '📸 Foto compartida por $caregiverName',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 3.5,
                    child: Image.network(
                      photoUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Padding(
                        padding: EdgeInsets.all(40),
                        child: Icon(Icons.broken_image_rounded, size: 48, color: Colors.grey),
                      ),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: Colors.grey.shade50,
                    child: const Text(
                      'Pellizca para ampliar. Las fotos del diario de cuidados quedan guardadas en el historial de la visita.',
                      style: TextStyle(fontSize: 11.5, color: AppTheme.slateMuted),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookingTextPromptDialog extends StatefulWidget {
  final String title;
  final String hintText;
  final String confirmLabel;
  final String initialValue;
  final int maxLines;
  final bool allowEmptySubmit;

  const _BookingTextPromptDialog({
    required this.title,
    required this.hintText,
    required this.confirmLabel,
    this.initialValue = '',
    this.maxLines = 1,
    this.allowEmptySubmit = false,
  });

  @override
  State<_BookingTextPromptDialog> createState() =>
      _BookingTextPromptDialogState();
}

class _BookingTextPromptDialogState extends State<_BookingTextPromptDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        maxLines: widget.maxLines,
        autofocus: true,
        decoration: InputDecoration(
          hintText: widget.hintText,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final text = _ctrl.text.trim();
            if (!widget.allowEmptySubmit && text.isEmpty) {
              Navigator.pop(context);
              return;
            }
            Navigator.pop(context, text);
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

