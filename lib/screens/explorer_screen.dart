import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      context.read<CaregiverNotifier>().loadMoreCaregivers();
    }
  }

  @override
  Widget build(BuildContext context) {
    final caregiverState = context.watch<CaregiverNotifier>();
    final locationState = context.watch<LocationNotifier>();
    final auth = context.watch<AuthNotifier>();
    final configState = context.watch<ConfigNotifier>();
    final bookingState = context.watch<BookingNotifier>();
    final theme = Theme.of(context);

    final activeClientBookings = bookingState.bookings
        .where((b) => b.isActive && b.status == BookingStatus.confirmed)
        .toList();

    return Scaffold(
      body: Column(
        children: [
          Container(
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
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppTheme.primarySurface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.location_on_rounded, color: AppTheme.primary, size: 18),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        auth.currentRole == 'client' && auth.currentClient?.homeAddress != null && auth.currentClient!.homeAddress.isNotEmpty
                            ? auth.currentClient!.homeAddress
                            : 'Madrid, ES',
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      icon: const Icon(Icons.map_outlined, size: 16),
                      label: const Text('Mapa', style: TextStyle(fontSize: 13)),
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const MapScreen()));
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: caregiverState.setSearchQuery,
                        decoration: InputDecoration(
                          hintText: 'Buscar por nombre o especialidad...',
                          prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.primary),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    caregiverState.setSearchQuery('');
                                    setState(() {});
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: AppTheme.backgroundNeutral,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppTheme.borderSubtle)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppTheme.borderSubtle)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: AppTheme.primarySurface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.3)),
                            ),
                            padding: const EdgeInsets.all(12),
                          ),
                          icon: const Icon(Icons.tune_rounded, color: AppTheme.primary),
                          tooltip: 'Filtrar por precio o valoración',
                          onPressed: () => _showFilterSheet(context, caregiverState),
                        ),
                        if (caregiverState.sortOption != CaregiverSortOption.recommended ||
                            caregiverState.maxPriceFilter < 50.0 ||
                            caregiverState.minRatingFilter > 0.0)
                          const Positioned(
                            top: -4,
                            right: -4,
                            child: CircleAvatar(
                              radius: 8,
                              backgroundColor: Colors.redAccent,
                              child: Text(
                                '!',
                                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                      ],
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
                        child: ActionChip(
                          avatar: Icon(
                            Icons.near_me_rounded,
                            size: 16,
                            color: caregiverState.sortOption == CaregiverSortOption.distanceAsc
                                ? Colors.white
                                : AppTheme.primary,
                          ),
                          backgroundColor: caregiverState.sortOption == CaregiverSortOption.distanceAsc
                              ? AppTheme.primary
                              : AppTheme.primarySurface,
                          side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.3)),
                          label: Text(
                            'Más cercanos hoy',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: caregiverState.sortOption == CaregiverSortOption.distanceAsc
                                  ? Colors.white
                                  : AppTheme.primary,
                            ),
                          ),
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            if (caregiverState.sortOption == CaregiverSortOption.distanceAsc) {
                              caregiverState.setSortOption(CaregiverSortOption.recommended);
                            } else {
                              caregiverState.resetFilters();
                              caregiverState.setSortOption(CaregiverSortOption.distanceAsc);
                              CustomSnackBar.show(
                                context,
                                message: 'Mostrando cuidadores verificados más cercanos disponibles.',
                                type: SnackBarType.info,
                              );
                            }
                          },
                        ),
                      ),
                      ...caregiverState.availableSpecialties.map((spec) {
                        final isSelected = caregiverState.selectedSpecialty == spec;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: FilterChip(
                            label: Text(spec),
                            selected: isSelected,
                            onSelected: (val) {
                              HapticFeedback.selectionClick();
                              caregiverState.setSpecialty(spec);
                            },
                            selectedColor: AppTheme.primary.withValues(alpha: 0.16),
                            checkmarkColor: AppTheme.primary,
                            labelStyle: TextStyle(
                              color: isSelected ? AppTheme.primary : AppTheme.darkSlate,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: caregiverState.refreshCaregivers,
              child: caregiverState.caregivers.isEmpty && caregiverState.isFetchingCaregivers
                  ? ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: 3,
                      itemBuilder: (context, index) {
                        return Shimmer.fromColors(
                          baseColor: Colors.grey.shade300,
                          highlightColor: Colors.grey.shade100,
                          child: Card(
                            margin: const EdgeInsets.only(bottom: 16),
                            child: Container(
                              height: 200,
                              width: double.infinity,
                              color: Colors.white,
                            ),
                          ),
                        );
                      },
                    )
                  : caregiverState.filteredCaregivers.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            Container(
                              height: MediaQuery.of(context).size.height * 0.4,
                              alignment: Alignment.center,
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.search_off_rounded, size: 72, color: Colors.grey.shade300),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No encontramos cuidadores con esos filtros',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.grey.shade600),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Prueba a restablecer filtros o publica una oferta para que los cuidadores te contacten.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.grey.shade500),
                                  ),
                                  const SizedBox(height: 20),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 10,
                                    alignment: WrapAlignment.center,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: () {
                                          _searchController.clear();
                                          caregiverState.setSearchQuery('');
                                          caregiverState.setSpecialty('Todos');
                                          caregiverState.resetFilters();
                                          setState(() {});
                                        },
                                        icon: const Icon(Icons.refresh_rounded, size: 18),
                                        label: const Text('Restablecer Filtros'),
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
                                        ),
                                        icon: const Icon(Icons.add_task_rounded, size: 18),
                                        label: const Text('Publicar Oferta de Empleo'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: 1 + caregiverState.filteredCaregivers.length + (caregiverState.isFetchingCaregivers ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (activeClientBookings.isNotEmpty)
                                    _buildWeeklyCareSummaryBanner(context, activeClientBookings),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(14),
                                      onTap: () {
                                        GuidedMatchingWizard.show(
                                          context,
                                          caregivers: caregiverState.caregivers,
                                          onSelectCaregiver: (selected) {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => CaregiverDetailScreen(caregiver: selected),
                                              ),
                                            );
                                          },
                                          onApplyFilters: (specs, maxRate) {
                                            caregiverState.setMaxPriceFilter(maxRate);
                                            if (specs.isNotEmpty) {
                                              caregiverState.setSpecialty(specs.first);
                                            }
                                          },
                                        );
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primarySurface.withValues(alpha: 0.7),
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.22)),
                                        ),
                                        child: const Row(
                                          children: [
                                            Icon(Icons.auto_awesome_rounded, color: AppTheme.primary, size: 20),
                                            SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                '¿Necesitas ayuda? Encuentra tu cuidador ideal en 3 pasos',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppTheme.darkSlate,
                                                ),
                                              ),
                                            ),
                                            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppTheme.primary),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }

                            final cgIndex = index - 1;
                            if (cgIndex == caregiverState.filteredCaregivers.length) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            final c = caregiverState.filteredCaregivers[cgIndex];
                            final displayedSpecs = c.specialties.take(3).toList();

                            return Card(
                              margin: const EdgeInsets.only(bottom: 14),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(22),
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CaregiverDetailScreen(caregiver: c))),
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
                                              child: CachedNetworkImage(
                                                imageUrl: c.imageUrl,
                                                height: 76,
                                                width: 76,
                                                fit: BoxFit.cover,
                                                placeholder: (context, url) => Shimmer.fromColors(
                                                  baseColor: Colors.grey.shade300,
                                                  highlightColor: Colors.grey.shade100,
                                                  child: Container(height: 76, width: 76, color: Colors.white),
                                                ),
                                                errorWidget: (context, url, error) => Container(
                                                  height: 76,
                                                  width: 76,
                                                  color: AppTheme.backgroundNeutral,
                                                  child: const Icon(Icons.person, size: 40, color: AppTheme.slateMuted),
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
                                                        style: theme.textTheme.titleMedium,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                    if (c.verified) ...[
                                                      const SizedBox(width: 6),
                                                      const Icon(Icons.verified_rounded, color: AppTheme.primary, size: 18),
                                                    ],
                                                    if (c.isSuperCaregiver) ...[
                                                      const SizedBox(width: 6),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: Colors.amber.shade100,
                                                          borderRadius: BorderRadius.circular(6),
                                                          border: Border.all(color: Colors.amber.shade400),
                                                        ),
                                                        child: const Text(
                                                          '🏆 Top',
                                                          style: TextStyle(
                                                            fontSize: 10,
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
                                                  style: const TextStyle(color: AppTheme.slateMuted, fontSize: 13.5, fontWeight: FontWeight.w500),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 6),
                                                Builder(
                                                  builder: (context) {
                                                    String distanceText = c.distance;
                                                    final effectiveLat = auth.currentClient?.latitude ?? locationState.latitude;
                                                    final effectiveLng = auth.currentClient?.longitude ?? locationState.longitude;
                                                    if (c.latitude != null && c.longitude != null && effectiveLat != null && effectiveLng != null) {
                                                      double dist = calculateDistance(effectiveLat, effectiveLng, c.latitude!, c.longitude!);
                                                      distanceText = 'A ${dist.toStringAsFixed(1)} km';
                                                    }
                                                    return Row(
                                                      children: [
                                                        const Icon(Icons.star_rounded, color: AppTheme.amber, size: 17),
                                                        const SizedBox(width: 3),
                                                        Text(
                                                          '${c.rating.toStringAsFixed(1)} (${c.reviewsCount})',
                                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        const Text('•', style: TextStyle(color: AppTheme.slateMuted)),
                                                        const SizedBox(width: 8),
                                                        const Icon(Icons.near_me_rounded, size: 13, color: AppTheme.primary),
                                                        const SizedBox(width: 3),
                                                        Text(
                                                          distanceText,
                                                          style: const TextStyle(fontSize: 12, color: AppTheme.slateMuted, fontWeight: FontWeight.w600),
                                                        ),
                                                      ],
                                                    );
                                                  },
                                                ),
                                                if (c.hasOfficialCertification || c.retentionRate >= 90) ...[
                                                  const SizedBox(height: 6),
                                                  Row(
                                                    children: [
                                                      if (c.hasOfficialCertification)
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                                          decoration: BoxDecoration(
                                                            color: Colors.indigo.shade50,
                                                            borderRadius: BorderRadius.circular(6),
                                                          ),
                                                          child: Text(
                                                            '🎓 Certificación Oficial',
                                                            style: TextStyle(
                                                              fontSize: 10.5,
                                                              fontWeight: FontWeight.w700,
                                                              color: Colors.indigo.shade800,
                                                            ),
                                                          ),
                                                        ),
                                                      if (c.hasOfficialCertification && c.retentionRate >= 90)
                                                        const SizedBox(width: 6),
                                                      if (c.retentionRate >= 90)
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                                          decoration: BoxDecoration(
                                                            color: AppTheme.secondaryColor.withValues(alpha: 0.1),
                                                            borderRadius: BorderRadius.circular(6),
                                                          ),
                                                          child: Text(
                                                            '🔄 ${c.retentionRate}% repiten',
                                                            style: const TextStyle(
                                                              fontSize: 10.5,
                                                              fontWeight: FontWeight.w700,
                                                              color: AppTheme.secondaryColor,
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (displayedSpecs.isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: [
                                            ...displayedSpecs.take(2).map(
                                              (s) => Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.backgroundNeutral,
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: AppTheme.borderSubtle),
                                                ),
                                                child: Text(
                                                  s,
                                                  style: const TextStyle(fontSize: 11.5, color: AppTheme.darkSlate, fontWeight: FontWeight.w600),
                                                ),
                                              ),
                                            ),
                                            if (c.specialties.length > 2)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.primarySurface,
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  '+${c.specialties.length - 2} más',
                                                  style: const TextStyle(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.w700),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                      const Padding(
                                        padding: EdgeInsets.symmetric(vertical: 12),
                                        child: Divider(height: 1),
                                      ),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text('Tarifa por hora', style: TextStyle(fontSize: 11, color: AppTheme.slateMuted)),
                                              Text(
                                                '${c.pricePerHour.toStringAsFixed(0)}€ / hora',
                                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.primary),
                                              ),
                                            ],
                                          ),
                                          ElevatedButton.icon(
                                            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CaregiverDetailScreen(caregiver: c))),
                                            style: ElevatedButton.styleFrom(
                                              minimumSize: Size(150, configState.seniorMode ? 54 : 44),
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                            ),
                                            icon: const Icon(Icons.calendar_month_rounded, size: 18),
                                            label: const Text('Ver Horarios'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildWeeklyCareSummaryBanner(
    BuildContext context,
    List<Booking> activeBookings,
  ) {
    final nextBooking = activeBookings.first;
    final bool isInProgress = nextBooking.checkInTime != null ||
        nextBooking.liveStatus == 'in_progress';
    final bool isOnTheWay = nextBooking.liveStatus == 'on_the_way';
    final int completedTasks =
        nextBooking.careChecklist.where((t) => t.completed).length;
    final int totalTasks = nextBooking.careChecklist.length;

    Color statusColor = AppTheme.primary;
    String statusLabel = '📅 Próxima visita: ${nextBooking.day} (${nextBooking.slot})';
    if (isInProgress) {
      statusColor = AppTheme.secondaryColor;
      statusLabel = '🟢 En domicilio ahora con ${nextBooking.caregiverName}';
    } else if (isOnTheWay) {
      statusColor = Colors.orange.shade800;
      statusLabel = '🚗 ${nextBooking.caregiverName} está en camino al domicilio';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 1.5),
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
                    'Resumen Semanal (${activeBookings.length} ${activeBookings.length == 1 ? 'reserva activa' : 'reservas activas'})',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    statusLabel,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.darkSlate,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (totalTasks > 0) ...[
                    const SizedBox(height: 3),
                    Text(
                      '📋 $completedTasks de $totalTasks tareas completadas',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.slateMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.arrow_forward_ios_rounded, size: 15, color: statusColor),
          ],
        ),
      ),
    );
  }

  void _showFilterSheet(BuildContext context, CaregiverNotifier notifier) {
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
            return Padding(
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
                      Text(
                        'Filtrar y Ordenar',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 12),
                  
                  // 1. ORDENACIÓN
                  const Text('Ordenar por', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<CaregiverSortOption>(
                    initialValue: notifier.sortOption,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: CaregiverSortOption.recommended,
                        child: Text('Recomendados (KyC + Valoración)'),
                      ),
                      DropdownMenuItem(
                        value: CaregiverSortOption.ratingDesc,
                        child: Text('Mejor Valorados (Estrellas)'),
                      ),
                      DropdownMenuItem(
                        value: CaregiverSortOption.priceAsc,
                        child: Text('Precio: Menor a Mayor'),
                      ),
                      DropdownMenuItem(
                        value: CaregiverSortOption.priceDesc,
                        child: Text('Precio: Mayor a Menor'),
                      ),
                      DropdownMenuItem(
                        value: CaregiverSortOption.distanceAsc,
                        child: Text('Distancia: Más cercanos'),
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
                      const Text('Tarifa máxima por hora', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('${notifier.maxPriceFilter.round()}€/h', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
                    ],
                  ),
                  Slider(
                    value: notifier.maxPriceFilter,
                    min: 6,
                    max: 50,
                    divisions: 44,
                    label: '${notifier.maxPriceFilter.round()}€/h',
                    activeColor: AppTheme.primary,
                    onChanged: (val) {
                      setSheetState(() => notifier.setMaxPriceFilter(val));
                    },
                  ),
                  const SizedBox(height: 16),

                  // 3. VALORACIÓN MÍNIMA
                  const Text('Valoración mínima', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [0.0, 3.0, 4.0, 4.5].map((rating) {
                      final isSelected = notifier.minRatingFilter == rating;
                      final label = rating == 0.0 ? 'Cualquiera' : '$rating ★';
                      return ChoiceChip(
                        label: Text(label),
                        selected: isSelected,
                        selectedColor: AppTheme.primary.withValues(alpha: 0.2),
                        checkmarkColor: AppTheme.primary,
                        labelStyle: TextStyle(
                          color: isSelected ? AppTheme.primary : AppTheme.darkSlate,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        onSelected: (val) {
                          if (val) {
                            setSheetState(() => notifier.setMinRatingFilter(rating));
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  // 4. ACCIONES
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () {
                            setSheetState(() => notifier.resetFilters());
                            Navigator.pop(ctx);
                          },
                          child: const Text('Limpiar Todo'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Aplicar Filtros'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

