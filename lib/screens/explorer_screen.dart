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
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    final initialQuery = context.read<CaregiverNotifier>().searchQuery;
    _searchController = TextEditingController(text: initialQuery);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final caregiverState = context.watch<CaregiverNotifier>();
    final locationState = context.watch<LocationNotifier>();
    final auth = context.watch<AuthNotifier>();
    final configState = context.watch<ConfigNotifier>();
    final bookingState = context.watch<BookingNotifier>();
    final isSenior = configState.seniorMode;

    final activeClientBookings = bookingState.bookings
        .where((b) => b.isActive && b.status == BookingStatus.confirmed)
        .toList();

    return Scaffold(
      body: Column(
        children: [
          _buildHeader(
            context,
            auth: auth,
            caregiverState: caregiverState,
            isSenior: isSenior,
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: caregiverState.refreshCaregivers,
              child: _buildBody(
                context,
                caregiverState: caregiverState,
                locationState: locationState,
                auth: auth,
                activeClientBookings: activeClientBookings,
                isSenior: isSenior,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context, {
    required AuthNotifier auth,
    required CaregiverNotifier caregiverState,
    required bool isSenior,
  }) {
    final theme = Theme.of(context);
    final clientAddress = auth.currentClient?.homeAddress.trim() ?? '';
    final locationLabel = auth.currentRole == 'client' && clientAddress.isNotEmpty
        ? clientAddress
        : 'Tu zona actual';
    final filterCount = caregiverState.activeFilterSheetCount;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppTheme.primarySurface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  color: AppTheme.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  locationLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: isSenior ? 16 : 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(0, isSenior ? 44 : 38),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                icon: const Icon(Icons.map_outlined, size: 17),
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
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _searchController,
                  builder: (context, value, _) {
                    return TextField(
                      controller: _searchController,
                      onChanged: (q) => _onSearchChanged(caregiverState, q),
                      style: TextStyle(fontSize: isSenior ? 17 : 15),
                      decoration: InputDecoration(
                        hintText: 'Buscar cuidador, zona o cuidado...',
                        hintStyle: TextStyle(fontSize: isSenior ? 16 : 14),
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
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
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
                  minimumSize: Size(0, isSenior ? 52 : 46),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.tune_rounded, size: 20),
                label: Text(
                  filterCount > 0 ? 'Filtros ($filterCount)' : 'Filtrar',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: isSenior ? 15 : 13.5,
                  ),
                ),
                onPressed: () => _showFilterSheet(context, caregiverState),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: FilterChip(
                    avatar: Icon(
                      Icons.near_me_rounded,
                      size: 16,
                      color: caregiverState.sortOption ==
                              CaregiverSortOption.distanceAsc
                          ? Colors.white
                          : AppTheme.primary,
                    ),
                    selected: caregiverState.sortOption ==
                        CaregiverSortOption.distanceAsc,
                    showCheckmark: false,
                    backgroundColor: AppTheme.primarySurface,
                    selectedColor: AppTheme.primary,
                    side: BorderSide(
                      color: AppTheme.primary.withValues(alpha: 0.3),
                    ),
                    label: Text(
                      'Más cercanos',
                      style: TextStyle(
                        fontSize: isSenior ? 14.5 : 13,
                        fontWeight: FontWeight.w700,
                        color: caregiverState.sortOption ==
                                CaregiverSortOption.distanceAsc
                            ? Colors.white
                            : AppTheme.primary,
                      ),
                    ),
                    onSelected: (selected) {
                      HapticFeedback.selectionClick();
                      caregiverState.setSortOption(
                        selected
                            ? CaregiverSortOption.distanceAsc
                            : CaregiverSortOption.recommended,
                      );
                    },
                  ),
                ),
                ...caregiverState.availableSpecialties.map((spec) {
                  final isSelected = caregiverState.selectedSpecialty == spec;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: FilterChip(
                      label: Text(
                        spec,
                        style: TextStyle(
                          fontSize: isSenior ? 14.5 : 13,
                        ),
                      ),
                      selected: isSelected,
                      onSelected: (_) {
                        HapticFeedback.selectionClick();
                        caregiverState.toggleSpecialty(spec);
                      },
                      selectedColor: AppTheme.primary.withValues(alpha: 0.16),
                      checkmarkColor: AppTheme.primary,
                      labelStyle: TextStyle(
                        color: isSelected
                            ? AppTheme.primary
                            : AppTheme.darkSlate,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required CaregiverNotifier caregiverState,
    required LocationNotifier locationState,
    required AuthNotifier auth,
    required List<Booking> activeClientBookings,
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
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (activeClientBookings.isNotEmpty)
                _buildWeeklyCareSummaryBanner(
                  context,
                  activeClientBookings,
                  isSenior: isSenior,
                ),
              _buildAssistantBanner(context, caregiverState, isSenior: isSenior),
              _buildResultsSummaryRow(
                caregiverState,
                count: results.length,
                isSenior: isSenior,
              ),
            ],
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

        return _buildCaregiverCard(
          context,
          caregiver: results[cgIndex],
          effectiveLat: effectiveLat,
          effectiveLng: effectiveLng,
          isSenior: isSenior,
        );
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

  Widget _buildAssistantBanner(
    BuildContext context,
    CaregiverNotifier caregiverState, {
    required bool isSenior,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          GuidedMatchingWizard.show(
            context,
            caregivers: caregiverState.caregivers,
            onSelectCaregiver: _openCaregiverProfile,
            onApplyFilters: (specs, maxRate) {
              caregiverState.setMaxPriceFilter(maxRate.clamp(6.0, 50.0));
              caregiverState.setSpecialty(
                specs.isNotEmpty ? specs.first : 'Todos',
              );
            },
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.primarySurface.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.primary.withValues(alpha: 0.24),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                color: AppTheme.primary,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '¿No sabes a quién elegir?',
                      style: TextStyle(
                        fontSize: isSenior ? 16 : 14,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.darkSlate,
                      ),
                    ),
                    Text(
                      'Te recomendamos 3 cuidadores ideales en 3 pasos',
                      style: TextStyle(
                        fontSize: isSenior ? 14 : 12.5,
                        color: AppTheme.slateMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 15,
                color: AppTheme.primary,
              ),
            ],
          ),
        ),
      ),
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
                        Row(
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
                            const SizedBox(width: 8),
                            const Text(
                              '•',
                              style: TextStyle(color: AppTheme.slateMuted),
                            ),
                            const SizedBox(width: 8),
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

  Widget _buildWeeklyCareSummaryBanner(
    BuildContext context,
    List<Booking> activeBookings, {
    required bool isSenior,
  }) {
    final sorted = List<Booking>.from(activeBookings)
      ..sort((a, b) {
        int rank(Booking bk) {
          if (bk.checkInTime != null || bk.liveStatus == 'in_progress') {
            return 0;
          }
          if (bk.liveStatus == 'on_the_way') return 1;
          return 2;
        }

        return rank(a).compareTo(rank(b));
      });

    final nextBooking = sorted.first;
    final bool isInProgress =
        nextBooking.checkInTime != null ||
        nextBooking.liveStatus == 'in_progress';
    final bool isOnTheWay = nextBooking.liveStatus == 'on_the_way';

    Color statusColor = AppTheme.primary;
    String statusLabel =
        'Próxima visita: ${nextBooking.day} (${nextBooking.slot})';
    if (isInProgress) {
      statusColor = AppTheme.secondaryColor;
      statusLabel =
          'En domicilio ahora con ${nextBooking.caregiverName}';
    } else if (isOnTheWay) {
      statusColor = Colors.orange.shade800;
      statusLabel =
          '${nextBooking.caregiverName} está en camino al domicilio';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(
                  title: const Text('Resumen y Diario del Cuidado'),
                ),
                body: const BookingsScreen(),
              ),
            ),
          );
        },
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isInProgress
                    ? Icons.verified_user_rounded
                    : isOnTheWay
                        ? Icons.directions_car_rounded
                        : Icons.event_available_rounded,
                color: statusColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Resumen semanal (${activeBookings.length} ${activeBookings.length == 1 ? 'reserva activa' : 'reservas activas'})',
                    style: TextStyle(
                      fontSize: isSenior ? 13.5 : 12,
                      fontWeight: FontWeight.w800,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: isSenior ? 16 : 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.darkSlate,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 15,
              color: statusColor,
            ),
          ],
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
                    const SizedBox(height: 20),

                    // 2. PRECIO MÁXIMO
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

                    // 3. VALORACIÓN MÍNIMA
                    Text(
                      'Valoración mínima',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isSenior ? 18 : 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [0.0, 3.0, 4.0, 4.5].map((rating) {
                        final isSelected = notifier.minRatingFilter == rating;
                        final label = rating == 0.0 ? 'Cualquiera' : '$rating ★';
                        return ChoiceChip(
                          label: Text(
                            label,
                            style: TextStyle(fontSize: isSenior ? 15 : 13.5),
                          ),
                          selected: isSelected,
                          selectedColor:
                              AppTheme.primary.withValues(alpha: 0.2),
                          checkmarkColor: AppTheme.primary,
                          labelStyle: TextStyle(
                            color: isSelected
                                ? AppTheme.primary
                                : AppTheme.darkSlate,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                          onSelected: (val) {
                            if (val) {
                              setSheetState(
                                () => notifier.setMinRatingFilter(rating),
                              );
                            }
                          },
                        );
                      }).toList(),
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
