import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/screens/screens.dart';

class ExplorerScreen extends StatefulWidget {
  const ExplorerScreen({super.key});

  @override
  State<ExplorerScreen> createState() => _ExplorerScreenState();
}

class _ExplorerScreenState extends State<ExplorerScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
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
    final theme = Theme.of(context);

    return Scaffold(
      body: Column(
        children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on, color: AppTheme.primary, size: 20),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  auth.currentRole == 'client' && auth.currentClient?.homeAddress != null && auth.currentClient!.homeAddress.isNotEmpty
                      ? auth.currentClient!.homeAddress
                      : 'Madrid, ES', 
                  style: theme.textTheme.bodyMedium,
                  softWrap: true,
                  maxLines: 3,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.map, color: AppTheme.primary),
                tooltip: 'Ver en Mapa',
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => MapScreen()));
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: caregiverState.setSearchQuery,
                  decoration: InputDecoration(
                    hintText: 'Buscar cuidadores...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.all(12),
                    ),
                    icon: const Icon(Icons.tune, color: AppTheme.primary),
                    tooltip: 'Filtrar y Ordenar',
                    onPressed: () => _showFilterSheet(context, caregiverState),
                  ),
                  if (caregiverState.sortOption != CaregiverSortOption.recommended ||
                      caregiverState.maxPriceFilter < 50.0 ||
                      caregiverState.minRatingFilter > 0.0)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: CircleAvatar(
                        radius: 8,
                        backgroundColor: Colors.redAccent,
                        child: const Text(
                          '!',
                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: caregiverState.availableSpecialties.map((spec) {
              final isSelected = caregiverState.selectedSpecialty == spec;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: FilterChip(
                  label: Text(spec),
                  selected: isSelected,
                  onSelected: (val) => caregiverState.setSpecialty(spec),
                  selectedColor: AppTheme.primary.withValues(alpha: 0.2),
                  checkmarkColor: AppTheme.primary,
                  labelStyle: TextStyle(
                    color: isSelected ? AppTheme.primary : AppTheme.darkSlate,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              );
            }).toList(),
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
                            height: 300,
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
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search_off_rounded, size: 80, color: Colors.grey.shade300),
                                const SizedBox(height: 16),
                                Text(
                                  'No encontramos cuidadores',
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.grey.shade600),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Prueba a usar otros filtros o buscar en otra zona.',
                                  style: TextStyle(color: Colors.grey.shade500),
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
                        itemCount: caregiverState.filteredCaregivers.length + (caregiverState.isFetchingCaregivers ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == caregiverState.filteredCaregivers.length) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }
                          final c = caregiverState.filteredCaregivers[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          child: Column(
                            children: [
                              ClipRRect(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                                child: CachedNetworkImage(
                                  imageUrl: c.imageUrl,
                                  height: 160,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Shimmer.fromColors(
                                    baseColor: Colors.grey.shade300,
                                    highlightColor: Colors.grey.shade100,
                                    child: Container(height: 160, color: Colors.white),
                                  ),
                                  errorWidget: (context, url, error) => Container(
                                    height: 160,
                                    color: Colors.grey.shade200,
                                    child: Icon(Icons.person, size: 64, color: Colors.grey.shade400),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  c.name,
                                                  style: theme.textTheme.titleMedium,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              if (c.verified) const Icon(Icons.verified, color: Colors.blue, size: 18),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Row(children: [const Icon(Icons.star, color: AppTheme.amber, size: 20), const SizedBox(width: 4), Text('${c.rating.toStringAsFixed(1)} (${c.reviewsCount})', style: const TextStyle(fontWeight: FontWeight.bold))])
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(c.title, style: TextStyle(color: Colors.grey.shade600, fontSize: 15)),
                                    const SizedBox(height: 8),
                                    Builder(
                                        builder: (context) {
                                          String distanceText = c.distance;
                                          final effectiveLat = auth.currentClient?.latitude ?? locationState.latitude;
                                          final effectiveLng = auth.currentClient?.longitude ?? locationState.longitude;
                                          if (c.latitude != null && c.longitude != null && effectiveLat != null && effectiveLng != null) {
                                            double dist = calculateDistance(effectiveLat, effectiveLng, c.latitude!, c.longitude!);
                                            distanceText = 'A ${dist.toStringAsFixed(1)} km de ti';
                                          }
                                        return Row(
                                          children: [
                                            const Icon(Icons.location_on, size: 16, color: Colors.redAccent),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                distanceText,
                                                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ]
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    Wrap(
                                      spacing: 6, runSpacing: 6,
                                      children: c.specialties.map((s) => Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(color: AppTheme.backgroundNeutral, borderRadius: BorderRadius.circular(8)),
                                        child: Text(s, style: const TextStyle(fontSize: 12, color: AppTheme.darkSlate, fontWeight: FontWeight.w500)),
                                      )).toList(),
                                    ),
                                    const SizedBox(height: 20),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('${c.pricePerHour.toStringAsFixed(0)}€/h', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                                        ElevatedButton(
                                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CaregiverDetailScreen(caregiver: c))),
                                          style: ElevatedButton.styleFrom(minimumSize: Size(130, configState.seniorMode ? 56 : 44)),
                                          child: const Text('Ver Perfil'),
                                        )
                                      ],
                                    )
                                  ],
                                ),
                              )
                            ],
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

