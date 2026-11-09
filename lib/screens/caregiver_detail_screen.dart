import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/screens/screens.dart';
import 'package:cached_network_image/cached_network_image.dart';

class CaregiverDetailScreen extends StatefulWidget {
  final CaregiverProfile caregiver;
  const CaregiverDetailScreen({super.key, required this.caregiver});

  @override
  State<CaregiverDetailScreen> createState() => _CaregiverDetailScreenState();
}

class _CaregiverDetailScreenState extends State<CaregiverDetailScreen> {
  DateTime _selectedDate = DateTime.now();
  List<TimeSlot> _slots = [];
  List<TimeSlot> _selectedSlots = [];
  List<Review> _reviews = [];
  bool _isLoading = false;
  bool _isLoadingReviews = false;

  @override
  void initState() {
    super.initState();
    _loadSlots();
    _loadReviews();
  }

  bool _hasMoreReviews = true;

  Future<void> _loadReviews({bool loadMore = false}) async {
    if (_isLoadingReviews || !_hasMoreReviews && loadMore) return;
    
    setState(() => _isLoadingReviews = true);
    final newReviews = await DependencyInjection.reviews.fetchReviewsForCaregiver(
      widget.caregiver.id, 
      refresh: !loadMore
    );
    
    if (mounted) {
      setState(() {
        if (!loadMore) {
          _reviews = newReviews;
        } else {
          _reviews.addAll(newReviews);
        }
        _hasMoreReviews = newReviews.isNotEmpty;
        _isLoadingReviews = false;
      });
    }
  }

  Future<void> _loadSlots() async {
    setState(() => _isLoading = true);
    final dateStr = '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
    final slots = await DependencyInjection.caregivers.fetchTimeSlots(widget.caregiver.id, dateStr);
    
    // Sort slots by time
    slots.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    
    if (mounted) {
      setState(() {
        _slots = slots;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.caregiver;
    final location = context.watch<LocationNotifier>();
    
    String distanceText = c.distance;
    if (c.latitude != null && c.longitude != null && location.latitude != null && location.longitude != null) {
      double dist = calculateDistance(location.latitude!, location.longitude!, c.latitude!, c.longitude!);
      distanceText = 'A ${dist.toStringAsFixed(1)} km de ti';
    }

    return Scaffold(
      appBar: AppBar(title: Text(c.name)),
      body: ListView(
        children: [
          Container(
            height: 200, width: double.infinity,
            decoration: BoxDecoration(color: Colors.black87, image: DecorationImage(image: CachedNetworkImageProvider(c.imageUrl), fit: BoxFit.cover, colorFilter: const ColorFilter.mode(Colors.black54, BlendMode.darken))),
            child: Center(child: CircleAvatar(radius: 30, backgroundColor: Colors.white.withOpacity(0.8), child: const Icon(Icons.play_arrow, color: AppTheme.primary, size: 40))),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.title, style: theme.textTheme.titleLarge),
                if (c.isKycVerified) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified, color: Colors.green, size: 16),
                        SizedBox(width: 4),
                        Text('Identidad Verificada por Stripe', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star, color: AppTheme.amber, size: 20),
                        const SizedBox(width: 4),
                        Text('${c.rating.toStringAsFixed(1)} (${c.reviewsCount} reseñas)', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.location_on, color: Colors.grey, size: 20),
                        Flexible(child: Text(distanceText, style: const TextStyle(color: Colors.grey), overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Sobre mí', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(c.bio, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 24),
                Text('Reserva tu cita', style: theme.textTheme.titleMedium),
                const SizedBox(height: 16),
                CalendarDatePicker(
                  initialDate: _selectedDate,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 90)),
                  onDateChanged: (date) {
                    setState(() {
                      _selectedDate = date;
                      _selectedSlots.clear();
                    });
                    _loadSlots();
                  },
                ),
                const SizedBox(height: 16),
                Builder(
                  builder: (context) {
                    final now = DateTime.now();
                    final isToday = _selectedDate.year == now.year && _selectedDate.month == now.month && _selectedDate.day == now.day;
                    
                    final availableSlots = _slots.where((s) {
                      if (!s.isAvailable) return false;
                      if (isToday) {
                        return s.dateTime.isAfter(now.add(const Duration(hours: 2)));
                      }
                      return true;
                    }).toList();

                    if (_isLoading) return const Center(child: CircularProgressIndicator());
                    if (availableSlots.isEmpty) return const Text('No hay horarios disponibles para este día.');
                    
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8, runSpacing: 8,
                          children: availableSlots.map((slot) {
                            final timeStr = '${slot.dateTime.hour.toString().padLeft(2, '0')}:${slot.dateTime.minute.toString().padLeft(2, '0')}';
                            final isSelected = _selectedSlots.contains(slot);
                            return FilterChip(
                              label: Text(timeStr),
                              selected: isSelected,
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedSlots.add(slot);
                                    _selectedSlots.sort((a, b) => a.dateTime.compareTo(b.dateTime));
                                  } else {
                                    _selectedSlots.remove(slot);
                                  }
                                });
                              },
                              backgroundColor: AppTheme.backgroundNeutral,
                              selectedColor: AppTheme.primary.withValues(alpha: 0.2),
                              checkmarkColor: AppTheme.primary,
                              side: BorderSide(color: isSelected ? AppTheme.primary : Colors.grey.shade300),
                            );
                          }).toList(),
                        ),
                        if (_selectedSlots.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          if (c.pricePerHour < 8 && _selectedSlots.length < 2)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Text(
                                'Por favor, selecciona un mínimo de 2 horas para poder reservar con esta tarifa.',
                                style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          if (!c.hasStripeAccount)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Text(
                                'Este cuidador no tiene cuenta bancaria configurada.',
                                style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: (c.pricePerHour >= 8 || _selectedSlots.length >= 2) && c.hasStripeAccount ? () {
                                final dateStr = '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
                                Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentScreen(caregiver: c, dateString: dateStr, slots: _selectedSlots)));
                              } : null,
                              child: Text('Reservar ${_selectedSlots.length} hora${_selectedSlots.length > 1 ? 's' : ''}'),
                            ),
                          )
                        ]
                      ],
                    );
                  }
                ),
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),
                Text('Reseñas de Clientes', style: theme.textTheme.titleMedium),
                const SizedBox(height: 16),
                if (_isLoadingReviews)
                  const Center(child: CircularProgressIndicator())
                else if (_reviews.isEmpty)
                  const Text('Este cuidador aún no tiene reseñas.', style: TextStyle(color: Colors.grey))
                else
                  ..._reviews.map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.account_circle, color: Colors.grey),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    r.clientName,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Row(
                                  children: List.generate(
                                    5,
                                    (index) => Icon(
                                      index < r.rating.round() ? Icons.star : Icons.star_border,
                                      color: Colors.amber,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (r.comment.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text('"${r.comment}"', style: const TextStyle(fontStyle: FontStyle.italic)),
                            ]
                          ],
                        ),
                      )),
                if (_hasMoreReviews && _reviews.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: OutlinedButton(
                        onPressed: () => _loadReviews(loadMore: true),
                        child: const Text('Cargar más reseñas'),
                      ),
                    ),
                  ),
              ],
            ),
          )
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final auth = context.read<AuthNotifier>();
          Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(
            clientId: auth.currentUserId ?? 'unknown',
            caregiverId: c.id,
            caregiverName: c.name,
          )));
        },
        label: const Text('Contactar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.chat, color: Colors.white),
        backgroundColor: AppTheme.primary,
      ),
    );
  }
}

