import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/screens/screens.dart';
import 'package:senicare/widgets/widgets.dart';

class ExplorerScreen extends StatefulWidget {
  const ExplorerScreen({super.key});

  @override
  State<ExplorerScreen> createState() => _ExplorerScreenState();
}

class _ExplorerScreenState extends State<ExplorerScreen> {
  final ScrollController _scrollController = ScrollController();
  late final TextEditingController _searchController;
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _searchDebounce;
  bool _isBookingBannerMinimized = false;

  @override
  void initState() {
    super.initState();
    final initialQuery = context.read<CaregiverNotifier>().searchQuery;
    _searchController = TextEditingController(text: initialQuery);
    _isBookingBannerMinimized = initialQuery.trim().isNotEmpty;
    _searchFocusNode.addListener(_onSearchFocusChanged);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _searchFocusNode.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchFocusChanged() {
    if (_searchFocusNode.hasFocus && !_isBookingBannerMinimized && mounted) {
      setState(() => _isBookingBannerMinimized = true);
    }
  }

  void _minimizeBookingBannerAndFocusSearch() {
    if (mounted) {
      setState(() => _isBookingBannerMinimized = true);
    }
    _searchFocusNode.requestFocus();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      context.read<CaregiverNotifier>().loadMoreCaregivers();
    }
  }

  void _onSearchChanged(CaregiverNotifier notifier, String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      notifier.setSearchQuery(value);
    });
  }

  void _clearAllFilters(CaregiverNotifier notifier) {
    _searchDebounce?.cancel();
    _searchController.clear();
    notifier.resetAllFilters();
  }

  void _openCaregiverProfile(CaregiverProfile caregiver) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CaregiverDetailScreen(caregiver: caregiver),
      ),
    );
  }

  String _sortLabel(CaregiverSortOption option) {
    switch (option) {
      case CaregiverSortOption.recommended:
        return 'Recomendados';
      case CaregiverSortOption.ratingDesc:
        return 'Mejor valorados';
      case CaregiverSortOption.priceAsc:
        return 'Menor precio';
      case CaregiverSortOption.priceDesc:
        return 'Mayor precio';
      case CaregiverSortOption.distanceAsc:
        return 'Más cercanos';
    }
  }

  List<Booking> _sortedConfirmedBookings(List<Booking> bookings) {
    final sorted = List<Booking>.from(bookings);
    sorted.sort((a, b) {
      int rank(Booking bk) {
        if (bk.checkInTime != null || bk.liveStatus == 'in_progress') {
          return 0;
        }
        if (bk.liveStatus == 'on_the_way') return 1;
        return 2;
      }

      final rCmp = rank(a).compareTo(rank(b));
      if (rCmp != 0) return rCmp;
      final dtA = a.scheduledStartTime ?? a.createdAt;
      final dtB = b.scheduledStartTime ?? b.createdAt;
      return dtA.compareTo(dtB);
    });
    return sorted;
  }

  String _formatBookingFriendlyDay(Booking b) {
    final start = b.scheduledStartTime;
    if (start == null) return b.day;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final target = DateTime(start.year, start.month, start.day);
    final shortDate =
        '${start.day.toString().padLeft(2, '0')}/${start.month.toString().padLeft(2, '0')}';
    if (target == today) return 'Hoy ($shortDate)';
    if (target == tomorrow) return 'Mañana ($shortDate)';
    const weekdays = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    return '${weekdays[(start.weekday - 1).clamp(0, 6)]} $shortDate';
  }

  void _openBookingInReservas(Booking booking) {
    HapticFeedback.selectionClick();
    pendingBookingFocus.value = {'bookingId': booking.id};
    pendingTrackingBookingId.value = booking.id;
    if (!MainLayout.switchTab(context, 2)) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Reservas')),
            body: const BookingsScreen(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final caregiverState = context.watch<CaregiverNotifier>();
    final locationState = context.watch<LocationNotifier>();
    final auth = context.watch<AuthNotifier>();
    final configState = context.watch<ConfigNotifier>();
    final bookingState = context.watch<BookingNotifier>();
    final isSenior = configState.seniorMode;

    final sortedConfirmedBookings = _sortedConfirmedBookings(
      bookingState.bookings
          .where((b) => b.isActive && b.status == BookingStatus.confirmed)
          .toList(),
    );
    final hasConfirmedBooking = sortedConfirmedBookings.isNotEmpty;
    final showExpandedBooking =
        hasConfirmedBooking && !_isBookingBannerMinimized;

    return Scaffold(
      body: Column(
        children: [
          _buildHeader(
            context,
            auth: auth,
            caregiverState: caregiverState,
            confirmedBookings: sortedConfirmedBookings,
            showExpandedBooking: showExpandedBooking,
            isSenior: isSenior,
          ),
          Expanded(
            child: Stack(
              children: [
                IgnorePointer(
                  ignoring: showExpandedBooking,
                  child: Column(
                    children: [
                      if (showExpandedBooking)
                        _buildFilterAndMapRow(
                          context,
                          caregiverState: caregiverState,
                          isSenior: isSenior,
                          horizontalPadding: 16,
                          topPadding: 10,
                          bottomPadding: 4,
                        ),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: caregiverState.refreshCaregivers,
                          child: _buildBody(
                            context,
                            caregiverState: caregiverState,
                            locationState: locationState,
                            auth: auth,
                            isSenior: isSenior,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (showExpandedBooking)
                  Positioned.fill(
                    child: GestureDetector(
                      key: const Key('explorer_booking_backdrop'),
                      onTap: _minimizeBookingBannerAndFocusSearch,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 220),
                        opacity: 1.0,
                        child: Container(
                          color: AppTheme.darkSlate.withValues(alpha: 0.45),
                          alignment: Alignment.topCenter,
                          padding: const EdgeInsets.only(top: 18, left: 24, right: 24),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Pulsa "Buscar cuidador" si deseas buscar otro profesional',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: isSenior ? 13.5 : 12,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.darkSlate,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterAndMapRow(
    BuildContext context, {
    required CaregiverNotifier caregiverState,
    required bool isSenior,
    double horizontalPadding = 0,
    double topPadding = 0,
    double bottomPadding = 0,
  }) {
    final filterCount = caregiverState.activeFilterSheetCount;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        topPadding,
        horizontalPadding,
        bottomPadding,
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('explorer_filter_button'),
              style: OutlinedButton.styleFrom(
                backgroundColor: filterCount > 0
                    ? AppTheme.primary
                    : AppTheme.primarySurface,
                foregroundColor:
                    filterCount > 0 ? Colors.white : AppTheme.primary,
                side: BorderSide(
                  color: AppTheme.primary.withValues(alpha: 0.35),
                ),
                minimumSize: Size(0, isSenior ? 48 : 44),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.tune_rounded, size: 20),
              label: Text(
                filterCount > 0 ? 'Filtros ($filterCount)' : 'Filtrar',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: isSenior ? 15 : 13.5,
                ),
              ),
              onPressed: () => _showFilterSheet(context, caregiverState),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            key: const Key('explorer_map_button'),
            style: OutlinedButton.styleFrom(
              minimumSize: Size(0, isSenior ? 48 : 44),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.map_outlined, size: 18),
            label: Text(
              'Mapa',
              style: TextStyle(
                fontSize: isSenior ? 15 : 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MapScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context, {
    required AuthNotifier auth,
    required CaregiverNotifier caregiverState,
    required List<Booking> confirmedBookings,
    required bool showExpandedBooking,
    required bool isSenior,
  }) {
    final hasConfirmed = confirmedBookings.isNotEmpty;

    return Container(
      key: auth.currentRole == 'client'
          ? AppTutorialTargets.maybeClientOf(context)?.explorerHeaderKey
          : null,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasConfirmed) ...[
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              child: showExpandedBooking
                  ? _buildFeaturedBookingCard(
                      context,
                      confirmedBookings,
                      isSenior: isSenior,
                    )
                  : _buildMiniBookingBanner(
                      context,
                      confirmedBookings,
                      isSenior: isSenior,
                    ),
            ),
            SizedBox(height: showExpandedBooking ? 12 : 8),
          ],
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _searchController,
            builder: (context, value, _) {
              return TextField(
                key: const Key('explorer_search_field'),
                controller: _searchController,
                focusNode: _searchFocusNode,
                onTap: () {
                  if (hasConfirmed && !_isBookingBannerMinimized) {
                    setState(() => _isBookingBannerMinimized = true);
                  }
                },
                onChanged: (q) => _onSearchChanged(caregiverState, q),
                style: TextStyle(fontSize: isSenior ? 17 : 15),
                decoration: InputDecoration(
                  hintText: 'Buscar cuidador',
                  hintStyle: TextStyle(fontSize: isSenior ? 16 : 14.5),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppTheme.primary,
                  ),
                  suffixIcon: value.text.isNotEmpty
                      ? IconButton(
                          tooltip: 'Limpiar búsqueda',
                          icon: const Icon(Icons.clear_rounded, size: 20),
                          onPressed: () {
                            _searchDebounce?.cancel();
                            _searchController.clear();
                            caregiverState.setSearchQuery('');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: AppTheme.backgroundNeutral,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: isSenior ? 14 : 11,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: AppTheme.borderSubtle,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: AppTheme.borderSubtle,
                    ),
                  ),
                ),
              );
            },
          ),
          if (!showExpandedBooking) ...[
            const SizedBox(height: 10),
            _buildFilterAndMapRow(
              context,
              caregiverState: caregiverState,
              isSenior: isSenior,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required CaregiverNotifier caregiverState,
    required LocationNotifier locationState,
    required AuthNotifier auth,
    required bool isSenior,
  }) {
    if (caregiverState.caregivers.isEmpty &&
        caregiverState.isFetchingCaregivers) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 3,
        itemBuilder: (context, index) {
          return Shimmer.fromColors(
            baseColor: Colors.grey.shade300,
            highlightColor: Colors.grey.shade100,
            child: Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: Container(
                height: 180,
                width: double.infinity,
                color: Colors.white,
              ),
            ),
          );
        },
      );
    }

    if (caregiverState.errorMessage != null &&
        caregiverState.caregivers.isEmpty) {
      return _buildErrorState(context, caregiverState, isSenior: isSenior);
    }

    final results = caregiverState.filteredCaregivers;
    if (results.isEmpty) {
      return _buildEmptyState(context, caregiverState, isSenior: isSenior);
    }

    final effectiveLat =
        auth.currentClient?.latitude ?? locationState.latitude;
    final effectiveLng =
        auth.currentClient?.longitude ?? locationState.longitude;

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      itemCount:
          1 + results.length + (caregiverState.isFetchingCaregivers ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildResultsSummaryRow(
            caregiverState,
            count: results.length,
            isSenior: isSenior,
          );
        }

        final cgIndex = index - 1;
        if (cgIndex == results.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final card = _buildCaregiverCard(
          context,
          caregiver: results[cgIndex],
          effectiveLat: effectiveLat,
          effectiveLng: effectiveLng,
          isSenior: isSenior,
        );
        if (cgIndex == 0 && auth.currentRole == 'client') {
          return KeyedSubtree(
            key: AppTutorialTargets.maybeClientOf(context)?.explorerFirstCardKey,
            child: card,
          );
        }
        return card;
      },
    );
  }

  Widget _buildErrorState(
    BuildContext context,
    CaregiverNotifier caregiverState, {
    required bool isSenior,
  }) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 40),
        Icon(Icons.wifi_off_rounded, size: 64, color: Colors.grey.shade400),
        const SizedBox(height: 16),
        Text(
          caregiverState.errorMessage ?? 'No se pudieron cargar los cuidadores.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: isSenior ? 19 : 17,
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 20),
        Center(
          child: ElevatedButton.icon(
            onPressed: caregiverState.refreshCaregivers,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(
              'Reintentar',
              style: TextStyle(fontSize: isSenior ? 16 : 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    CaregiverNotifier caregiverState, {
    required bool isSenior,
  }) {
    final hasFilters = caregiverState.hasCustomFilters;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 32),
        Icon(
          hasFilters ? Icons.search_off_rounded : Icons.location_searching_rounded,
          size: 68,
          color: Colors.grey.shade400,
        ),
        const SizedBox(height: 16),
        Text(
          hasFilters
              ? 'No encontramos cuidadores con esos filtros'
              : 'No hay cuidadores justo en tu radio cercano',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppTheme.darkSlate,
                fontSize: isSenior ? 21 : 19,
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 10),
        Text(
          hasFilters
              ? 'Prueba a quitar algún filtro, ampliar la zona de búsqueda o publicar una oferta.'
              : 'Puedes ampliar la búsqueda para ver cuidadores de zonas cercanas o publicar una oferta de empleo.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.slateMuted,
            fontSize: isSenior ? 16 : 14,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            if (hasFilters)
              OutlinedButton.icon(
                onPressed: () => _clearAllFilters(caregiverState),
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(0, isSenior ? 50 : 44),
                ),
                icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                label: Text(
                  'Quitar filtros',
                  style: TextStyle(fontSize: isSenior ? 16 : 14),
                ),
              ),
            if (!caregiverState.ignoreDistanceLimit &&
                caregiverState.caregivers.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => caregiverState.setIgnoreDistanceLimit(true),
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(0, isSenior ? 50 : 44),
                ),
                icon: const Icon(Icons.public_rounded, size: 18),
                label: Text(
                  'Ampliar zona',
                  style: TextStyle(fontSize: isSenior ? 16 : 14),
                ),
              ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CreateOfferScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                minimumSize: Size(0, isSenior ? 50 : 44),
              ),
              icon: const Icon(Icons.add_task_rounded, size: 18),
              label: Text(
                'Publicar oferta de empleo',
                style: TextStyle(fontSize: isSenior ? 16 : 14),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildResultsSummaryRow(
    CaregiverNotifier caregiverState, {
    required int count,
    required bool isSenior,
  }) {
    final label =
        '$count ${count == 1 ? 'cuidador verificado' : 'cuidadores verificados'}';
    final sortText = _sortLabel(caregiverState.sortOption);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              caregiverState.ignoreDistanceLimit
                  ? '$label · Toda la zona ($sortText)'
                  : '$label · $sortText',
              style: TextStyle(
                fontSize: isSenior ? 15 : 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.slateMuted,
              ),
            ),
          ),
          if (caregiverState.hasCustomFilters)
            TextButton.icon(
              onPressed: () => _clearAllFilters(caregiverState),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              icon: const Icon(Icons.close_rounded, size: 16),
              label: Text(
                'Limpiar',
                style: TextStyle(
                  fontSize: isSenior ? 14.5 : 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCaregiverCard(
    BuildContext context, {
    required CaregiverProfile caregiver,
    required double? effectiveLat,
    required double? effectiveLng,
    required bool isSenior,
  }) {
    final c = caregiver;
    final theme = Theme.of(context);
    final displayedSpecs = c.specialties.take(2).toList();

    String distanceText = c.distance;
    if (c.latitude != null &&
        c.longitude != null &&
        effectiveLat != null &&
        effectiveLng != null) {
      final dist = calculateDistance(
        effectiveLat,
        effectiveLng,
        c.latitude!,
        c.longitude!,
      );
      distanceText = 'A ${dist.toStringAsFixed(1)} km';
    }

    final trustParts = <String>[];
    if (c.hasOfficialCertification) trustParts.add('Certificación oficial');
    if (c.retentionRate >= 90) {
      trustParts.add('${c.retentionRate}% familias repiten');
    }

    final avatarSize = isSenior ? 80.0 : 72.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _openCaregiverProfile(c),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Hero(
                    tag: 'caregiver_img_${c.id}',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: c.imageUrl.trim().isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: c.imageUrl,
                              height: avatarSize,
                              width: avatarSize,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                height: avatarSize,
                                width: avatarSize,
                                color: AppTheme.backgroundNeutral,
                                child: const Icon(
                                  Icons.person,
                                  size: 36,
                                  color: AppTheme.slateMuted,
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                height: avatarSize,
                                width: avatarSize,
                                color: AppTheme.backgroundNeutral,
                                child: const Icon(
                                  Icons.person,
                                  size: 38,
                                  color: AppTheme.slateMuted,
                                ),
                              ),
                            )
                          : Container(
                              height: avatarSize,
                              width: avatarSize,
                              color: AppTheme.primarySurface,
                              child: const Icon(
                                Icons.person,
                                size: 38,
                                color: AppTheme.primary,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                c.name,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontSize: isSenior ? 19 : 17,
                                  fontWeight: FontWeight.w800,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (c.verified) ...[
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.verified_rounded,
                                color: AppTheme.primary,
                                size: 19,
                              ),
                            ],
                            if (c.isSuperCaregiver) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade100,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: Colors.amber.shade400,
                                  ),
                                ),
                                child: const Text(
                                  'Top',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          c.title,
                          style: TextStyle(
                            color: AppTheme.slateMuted,
                            fontSize: isSenior ? 15 : 13.5,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  color: AppTheme.amber,
                                  size: 18,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '${c.rating.toStringAsFixed(1)} (${c.reviewsCount})',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: isSenior ? 14.5 : 13,
                                  ),
                                ),
                              ],
                            ),
                            const Text(
                              '•',
                              style: TextStyle(color: AppTheme.slateMuted),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.near_me_rounded,
                                  size: 14,
                                  color: AppTheme.primary,
                                ),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    distanceText,
                                    style: TextStyle(
                                      fontSize: isSenior ? 14 : 12.5,
                                      color: AppTheme.slateMuted,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (displayedSpecs.isNotEmpty || trustParts.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ...displayedSpecs.map(
                      (s) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.backgroundNeutral,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.borderSubtle),
                        ),
                        child: Text(
                          s,
                          style: TextStyle(
                            fontSize: isSenior ? 13.5 : 12,
                            color: AppTheme.darkSlate,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    if (c.specialties.length > 2)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primarySurface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '+${c.specialties.length - 2} más',
                          style: TextStyle(
                            fontSize: isSenior ? 13 : 11.5,
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                if (trustParts.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.verified_user_outlined,
                        size: 15,
                        color: AppTheme.secondaryColor,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          trustParts.join(' · '),
                          style: TextStyle(
                            fontSize: isSenior ? 14 : 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.secondaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1),
              ),
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Tarifa por hora',
                          style: TextStyle(
                            fontSize: isSenior ? 13 : 11.5,
                            color: AppTheme.slateMuted,
                          ),
                        ),
                        Text(
                          '${c.pricePerHour.toStringAsFixed(0)}€ / hora',
                          style: TextStyle(
                            fontSize: isSenior ? 22 : 20,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _openCaregiverProfile(c),
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size(140, isSenior ? 52 : 46),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                      icon: const Icon(Icons.calendar_month_rounded, size: 18),
                      label: Text(
                        'Ver Horarios',
                        style: TextStyle(
                          fontSize: isSenior ? 15.5 : 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeaturedBookingCard(
    BuildContext context,
    List<Booking> confirmedBookings, {
    required bool isSenior,
  }) {
    final nextBooking = confirmedBookings.first;
    final bool isInProgress =
        nextBooking.checkInTime != null ||
        nextBooking.liveStatus == 'in_progress';
    final bool isOnTheWay = nextBooking.liveStatus == 'on_the_way';

    final String statusTag = isInProgress
        ? 'EN DOMICILIO AHORA'
        : isOnTheWay
            ? 'CUIDADOR EN CAMINO'
            : 'RESERVA CONFIRMADA';
    final IconData statusIcon = isInProgress
        ? Icons.verified_user_rounded
        : isOnTheWay
            ? Icons.directions_car_rounded
            : Icons.event_available_rounded;

    return Container(
      key: const Key('explorer_booking_featured_card'),
      padding: EdgeInsets.all(isSenior ? 16 : 15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.primary, AppTheme.secondaryColor],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.28),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 14, color: Colors.white),
                    const SizedBox(width: 5),
                    Text(
                      statusTag,
                      style: TextStyle(
                        fontSize: isSenior ? 12 : 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              if (confirmedBookings.length > 1)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Más próxima (1 de ${confirmedBookings.length})',
                    style: TextStyle(
                      fontSize: isSenior ? 12 : 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            nextBooking.caregiverName,
            style: TextStyle(
              fontSize: isSenior ? 21 : 19,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.schedule_rounded, size: 16, color: Colors.white70),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${_formatBookingFriendlyDay(nextBooking)} · ${nextBooking.slot}',
                  style: TextStyle(
                    fontSize: isSenior ? 15.5 : 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.95),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _openBookingInReservas(nextBooking),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.primary,
                    elevation: 0,
                    minimumSize: Size(0, isSenior ? 46 : 42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.calendar_month_rounded, size: 18),
                  label: Text(
                    'Ver reserva',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: isSenior ? 15 : 13.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniBookingBanner(
    BuildContext context,
    List<Booking> confirmedBookings, {
    required bool isSenior,
  }) {
    final nextBooking = confirmedBookings.first;
    final bool isInProgress =
        nextBooking.checkInTime != null ||
        nextBooking.liveStatus == 'in_progress';
    final bool isOnTheWay = nextBooking.liveStatus == 'on_the_way';

    return Container(
      key: const Key('explorer_booking_mini_banner'),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primary, AppTheme.secondaryColor],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openBookingInReservas(nextBooking),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  isInProgress
                      ? Icons.verified_user_rounded
                      : isOnTheWay
                          ? Icons.directions_car_rounded
                          : Icons.event_available_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Reserva: ${nextBooking.caregiverName} · ${_formatBookingFriendlyDay(nextBooking)} (${nextBooking.slot})',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: isSenior ? 14 : 12.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  key: const Key('explorer_booking_expand_button'),
                  tooltip: 'Ampliar reserva',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                  onPressed: () {
                    _searchFocusNode.unfocus();
                    setState(() => _isBookingBannerMinimized = false);
                  },
                  icon: const Icon(
                    Icons.unfold_more_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showFilterSheet(BuildContext context, CaregiverNotifier notifier) {
    final isSenior = context.read<ConfigNotifier>().seniorMode;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final theme = Theme.of(context);
            final clampedPrice = notifier.maxPriceFilter.clamp(6.0, 50.0);
            final priceLabel =
                clampedPrice >= 50.0 ? 'Sin límite' : '${clampedPrice.round()}€/h';
            final matchingCount = notifier.filteredCaregivers.length;
            const ratingOptions = <double>[0.0, 3.0, 4.0, 4.5];
            final currentRatingValue = ratingOptions.contains(notifier.minRatingFilter)
                ? notifier.minRatingFilter
                : 0.0;
            final currentSpecialty =
                notifier.availableSpecialties.contains(notifier.selectedSpecialty)
                    ? notifier.selectedSpecialty
                    : 'Todos';

            return SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  top: 20,
                  left: 20,
                  right: 20,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Filtrar y ordenar',
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: isSenior ? 22 : 20,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cerrar',
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 12),

                    // 1. ORDENACIÓN
                    Text(
                      'Ordenar por',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isSenior ? 18 : 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<CaregiverSortOption>(
                      isExpanded: true,
                      initialValue: notifier.sortOption,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: CaregiverSortOption.recommended,
                          child: Text(
                            'Recomendados (Verificados)',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: CaregiverSortOption.ratingDesc,
                          child: Text(
                            'Mejor valorados (Estrellas)',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: CaregiverSortOption.priceAsc,
                          child: Text(
                            'Precio: Menor a Mayor',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: CaregiverSortOption.priceDesc,
                          child: Text(
                            'Precio: Mayor a Menor',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: CaregiverSortOption.distanceAsc,
                          child: Text(
                            'Distancia: Más cercanos',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setSheetState(() => notifier.setSortOption(val));
                        }
                      },
                    ),
                    const SizedBox(height: 18),

                    // 2. ESPECIALIDAD (antes píldoras bajo el buscador)
                    Text(
                      'Tipo de cuidado / Especialidad',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isSenior ? 18 : 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: const Key('explorer_specialty_dropdown'),
                      isExpanded: true,
                      initialValue: currentSpecialty,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      items: notifier.availableSpecialties.map((spec) {
                        return DropdownMenuItem<String>(
                          value: spec,
                          child: Text(
                            spec == 'Todos' ? 'Todas las especialidades' : spec,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setSheetState(() => notifier.setSpecialty(val));
                        }
                      },
                    ),
                    const SizedBox(height: 18),

                    // 3. PRECIO MÁXIMO
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Tarifa máxima por hora',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: isSenior ? 18 : 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          priceLabel,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: isSenior ? 17 : 15,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: clampedPrice,
                      min: 6,
                      max: 50,
                      divisions: 44,
                      label: priceLabel,
                      activeColor: AppTheme.primary,
                      onChanged: (val) {
                        setSheetState(() => notifier.setMaxPriceFilter(val));
                      },
                    ),
                    const SizedBox(height: 12),

                    // 4. VALORACIÓN MÍNIMA (desplegable)
                    Text(
                      'Valoración mínima',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isSenior ? 18 : 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<double>(
                      key: const Key('explorer_rating_dropdown'),
                      isExpanded: true,
                      initialValue: currentRatingValue,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      items: ratingOptions.map((rating) {
                        final label = rating == 0.0
                            ? 'Cualquiera'
                            : '${rating.toStringAsFixed(1)} ★ o más';
                        return DropdownMenuItem<double>(
                          value: rating,
                          child: Text(
                            label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setSheetState(() => notifier.setMinRatingFilter(val));
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // 4. AMPLIAR ZONA
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Ampliar zona de búsqueda',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: isSenior ? 16.5 : 15,
                        ),
                      ),
                      subtitle: Text(
                        'Incluye cuidadores fuera de tu radio inmediato',
                        style: TextStyle(fontSize: isSenior ? 14 : 12.5),
                      ),
                      value: notifier.ignoreDistanceLimit,
                      activeTrackColor: AppTheme.primary,
                      onChanged: (val) {
                        setSheetState(
                          () => notifier.setIgnoreDistanceLimit(val),
                        );
                      },
                    ),
                    const SizedBox(height: 20),

                    // 5. ACCIONES
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.symmetric(
                                vertical: isSenior ? 16 : 14,
                              ),
                            ),
                            onPressed: () {
                              setSheetState(() => notifier.resetFilters());
                              Navigator.pop(ctx);
                            },
                            child: Text(
                              'Limpiar todo',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: isSenior ? 16 : 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(
                                vertical: isSenior ? 16 : 14,
                              ),
                            ),
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(
                              'Ver $matchingCount ${matchingCount == 1 ? 'cuidador' : 'cuidadores'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: isSenior ? 16 : 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
