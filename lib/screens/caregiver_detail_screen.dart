import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/screens/screens.dart';
import 'package:senicare/widgets/widgets.dart';
import 'package:cached_network_image/cached_network_image.dart';

class CaregiverDetailScreen extends StatefulWidget {
  final CaregiverProfile caregiver;
  final bool isPreview;

  const CaregiverDetailScreen({
    super.key,
    required this.caregiver,
    this.isPreview = false,
  });

  @override
  State<CaregiverDetailScreen> createState() => _CaregiverDetailScreenState();
}

class _CaregiverDetailScreenState extends State<CaregiverDetailScreen> {
  DateTime _selectedDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  List<TimeSlot> _slots = [];
  final List<TimeSlot> _selectedSlots = [];
  TimeInterval? _activeInterval;
  DateTime? _customStartTime;
  DateTime? _customEndTime;
  List<Review> _reviews = [];
  bool _isLoading = false;
  bool _isLoadingReviews = false;
  bool _isPlayingVoiceIntro = false;
  double _voiceIntroProgress = 0.0;
  AudioPlayer? _voicePlayer;
  StreamSubscription<Duration>? _voicePosSub;
  StreamSubscription<void>? _voiceCompleteSub;
  Duration _voiceDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _loadSlots();
    _loadReviews();
  }

  @override
  void dispose() {
    _voicePosSub?.cancel();
    _voiceCompleteSub?.cancel();
    _voicePlayer?.dispose();
    super.dispose();
  }

  Future<void> _toggleVoiceIntro() async {
    final voiceUrl = widget.caregiver.voiceIntroUrl.trim();
    if (voiceUrl.isEmpty) return;

    HapticFeedback.selectionClick();
    _voicePlayer ??= AudioPlayer();

    if (_isPlayingVoiceIntro) {
      await _voicePlayer!.pause();
      if (mounted) setState(() => _isPlayingVoiceIntro = false);
      return;
    }

    _voicePosSub ??= _voicePlayer!.onPositionChanged.listen((pos) {
      if (!mounted) return;
      final totalMs = _voiceDuration.inMilliseconds;
      setState(() {
        _voiceIntroProgress = totalMs > 0
            ? (pos.inMilliseconds / totalMs).clamp(0.0, 1.0)
            : 0.0;
      });
    });
    _voiceCompleteSub ??= _voicePlayer!.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _isPlayingVoiceIntro = false;
        _voiceIntroProgress = 0.0;
      });
    });

    try {
      await _voicePlayer!.play(UrlSource(voiceUrl));
      final dur = await _voicePlayer!.getDuration();
      if (dur != null) _voiceDuration = dur;
      if (mounted) setState(() => _isPlayingVoiceIntro = true);
    } catch (e) {
      if (mounted) {
        setState(() => _isPlayingVoiceIntro = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo reproducir el audio de presentación: $e')),
        );
      }
    }
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
    AuthNotifier? auth;
    try {
      auth = context.watch<AuthNotifier>();
    } catch (_) {}
    final authUserId = auth?.currentUserId;
    final isOwnProfile = widget.isPreview || (authUserId != null && authUserId == c.id);

    final effectiveLat = auth?.currentClient?.latitude ?? location.latitude;
    final effectiveLng = auth?.currentClient?.longitude ?? location.longitude;
    String distanceText = c.distance;
    if (c.latitude != null && c.longitude != null && effectiveLat != null && effectiveLng != null) {
      double dist = calculateDistance(effectiveLat, effectiveLng, c.latitude!, c.longitude!);
      distanceText = 'A ${dist.toStringAsFixed(1)} km de ti';
    }

    return Scaffold(
      appBar: AppBar(title: Text(c.name)),
      body: ListView(
        children: [
          if (isOwnProfile)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: AppTheme.primarySurface,
              child: const Row(
                children: [
                  Icon(Icons.visibility_rounded, size: 18, color: AppTheme.primary),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Vista previa pública: así ven tu perfil las familias en SeniCare.',
                      style: TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            height: 220,
            width: double.infinity,
            decoration: BoxDecoration(color: Colors.grey.shade200),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Hero(
                  tag: 'caregiver_img_${c.id}',
                  child: c.imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: c.imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: Colors.grey.shade100,
                            child: const Center(child: CircularProgressIndicator()),
                          ),
                          errorWidget: (context, url, error) => const Center(
                            child: Icon(Icons.person, size: 80, color: Colors.grey),
                          ),
                        )
                      : const Center(child: Icon(Icons.person, size: 80, color: Colors.grey)),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black.withValues(alpha: 0.4), Colors.transparent],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.title, style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (c.isSuperCaregiver)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade100,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.amber.shade400),
                        ),
                        child: const Text(
                          '🏆 Supercuidador',
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppTheme.secondaryColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '🔄 El ${c.retentionRate}% de las familias repiten',
                        style: const TextStyle(
                          color: AppTheme.secondaryColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (c.isKycVerified)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified, color: Colors.green, size: 15),
                            SizedBox(width: 4),
                            Text(
                              'Identidad Verificada',
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (c.hasOfficialCertification)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.indigo.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.indigo.withValues(alpha: 0.35)),
                        ),
                        child: Text(
                          '🎓 Certificación Sociosanitaria Verificada',
                          style: TextStyle(
                            color: Colors.indigo.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
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
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: AppTheme.softTealGradient,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.shield_rounded, color: AppTheme.primary, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Protección SeniCare Incluida (Sin coste extra)',
                              style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.darkSlate, fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 6),
                      Text(
                        '• Pago seguro retenido hasta que el cuidador llega a casa.\n'
                        '• DNI/NIE y Certificado de Antecedentes revisados.\n'
                        '• Cobertura de Responsabilidad Civil y soporte ante incidencias.',
                        style: TextStyle(fontSize: 12.5, color: AppTheme.slateMuted, height: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      VideoCallModal.show(
                        context,
                        participantName: c.name,
                        participantImageUrl: c.imageUrl,
                        isCaregiver: false,
                      );
                    },
                    icon: const Icon(Icons.videocam_rounded, color: AppTheme.primary),
                    label: const Text(
                      'Entrevista previa gratuita por videollamada (15 min)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
                      side: const BorderSide(color: AppTheme.primary, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  if (c.voiceIntroUrl.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.backgroundNeutral,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.borderSubtle),
                      ),
                      child: Row(
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(24),
                            onTap: _toggleVoiceIntro,
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _isPlayingVoiceIntro ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '🎙️ Presentación en voz de ${c.name.split(" ").first}',
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppTheme.darkSlate),
                                ),
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: LinearProgressIndicator(
                                    value: _voiceIntroProgress,
                                    minHeight: 6,
                                    backgroundColor: AppTheme.primarySurface,
                                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text('Sobre mí', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(c.bio, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 24),
                Text('Reserva tu cita paso a paso', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                const Text(
                  '1. Elige el día en el calendario  →  2. Toca las horas que necesitas  →  3. Pulsa Reservar',
                  style: TextStyle(fontSize: 13, color: AppTheme.primary, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.secondaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Text('📦', style: TextStyle(fontSize: 16)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Bono Ahorro Familiar: 5% de descuento directo al seleccionar 4 o más horas.',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.secondaryColor),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: AppTheme.modernCardDecoration(),
                  child: CalendarDatePicker(
                    initialDate: _selectedDate,
                    firstDate: DateTime(
                      DateTime.now().year,
                      DateTime.now().month,
                      DateTime.now().day,
                    ),
                    lastDate: DateTime.now().add(const Duration(days: 90)),
                    onDateChanged: (date) {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _selectedDate = date;
                        _selectedSlots.clear();
                        _activeInterval = null;
                        _customStartTime = null;
                        _customEndTime = null;
                      });
                      _loadSlots();
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Builder(
                  builder: (context) {
                    if (_isLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final now = DateTime.now();
                    final intervals = FlexibleScheduleHelper.computeAvailableIntervals(
                      day: _selectedDate,
                      slots: _slots,
                      now: now,
                    );

                    if (intervals.isEmpty) {
                      return const Text('No hay horarios disponibles para este día.');
                    }

                    // Seleccionar automáticamente el primer intervalo disponible si no hay ninguno o cambió
                    TimeInterval? chosenInterval = _activeInterval;
                    if (chosenInterval == null ||
                        !intervals.any((it) =>
                            it.start == chosenInterval!.start &&
                            it.end == chosenInterval.end)) {
                      chosenInterval = intervals.first;
                    }

                    final DateTime selStart = _customStartTime != null &&
                            !_customStartTime!.isBefore(chosenInterval.start) &&
                            _customStartTime!.isBefore(chosenInterval.end)
                        ? _customStartTime!
                        : chosenInterval.start;
                    final DateTime selEnd = _customEndTime != null &&
                            !_customEndTime!.isAfter(chosenInterval.end) &&
                            _customEndTime!.isAfter(selStart)
                        ? _customEndTime!
                        : chosenInterval.end;

                    final int durationMinutes = selEnd.difference(selStart).inMinutes;
                    final double exactHours = durationMinutes / 60.0;
                    final bool validDuration = durationMinutes >= 30;
                    final bool minTwoHoursOk = c.pricePerHour >= 8 || durationMinutes >= 120;
                    final double estimatedServicePay =
                        FlexibleScheduleHelper.computeExactCost(
                      pricePerHour: c.pricePerHour,
                      durationMinutes: durationMinutes,
                      applyFourHourDiscount: true,
                    );
                    final double estimatedTotalClient =
                        ((estimatedServicePay * 1.03) * 100).roundToDouble() / 100.0;
                    final selectedInterval = TimeInterval(start: selStart, end: selEnd);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Franjas disponibles del cuidador:',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.darkSlate,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: intervals.map((interval) {
                            final isSelected = interval.start == chosenInterval!.start &&
                                interval.end == chosenInterval.end;
                            return ChoiceChip(
                              label: Text('${interval.formattedRange} (${interval.formattedDuration})'),
                              selected: isSelected,
                              onSelected: (_) {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  _activeInterval = interval;
                                  _customStartTime = interval.start;
                                  _customEndTime = interval.end;
                                });
                              },
                              backgroundColor: AppTheme.backgroundNeutral,
                              selectedColor: AppTheme.primary.withValues(alpha: 0.2),
                              side: BorderSide(
                                color: isSelected ? AppTheme.primary : Colors.grey.shade300,
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Elige tu horario exacto dentro de esa franja:',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.darkSlate,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                key: const Key('client_pick_start_time_btn'),
                                onPressed: () async {
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime: TimeOfDay.fromDateTime(selStart),
                                  );
                                  if (picked == null) return;
                                  final candidate = DateTime(
                                    _selectedDate.year,
                                    _selectedDate.month,
                                    _selectedDate.day,
                                    picked.hour,
                                    picked.minute,
                                  );
                                  if (candidate.isBefore(chosenInterval!.start) ||
                                      !candidate.isBefore(chosenInterval.end)) {
                                    if (context.mounted) {
                                      CustomSnackBar.show(
                                        context,
                                        message:
                                            'Elige una hora de inicio dentro de ${chosenInterval.formattedRange}.',
                                        type: SnackBarType.warning,
                                      );
                                    }
                                    return;
                                  }
                                  setState(() {
                                    _activeInterval = chosenInterval;
                                    _customStartTime = candidate;
                                    if (!selEnd.isAfter(candidate)) {
                                      _customEndTime = chosenInterval!.end;
                                    }
                                  });
                                },
                                icon: const Icon(Icons.login_rounded, size: 17),
                                label: Text('Desde ${TimeInterval.formatHm(selStart)}'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                key: const Key('client_pick_end_time_btn'),
                                onPressed: () async {
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime: TimeOfDay.fromDateTime(selEnd),
                                  );
                                  if (picked == null) return;
                                  final candidate = DateTime(
                                    _selectedDate.year,
                                    _selectedDate.month,
                                    _selectedDate.day,
                                    picked.hour,
                                    picked.minute,
                                  );
                                  if (!candidate.isAfter(selStart) ||
                                      candidate.isAfter(chosenInterval!.end)) {
                                    if (context.mounted) {
                                      CustomSnackBar.show(
                                        context,
                                        message:
                                            'Elige una hora de salida posterior a ${TimeInterval.formatHm(selStart)} y hasta ${chosenInterval!.endFormatted}.',
                                        type: SnackBarType.warning,
                                      );
                                    }
                                    return;
                                  }
                                  setState(() {
                                    _activeInterval = chosenInterval;
                                    _customStartTime = selStart;
                                    _customEndTime = candidate;
                                  });
                                },
                                icon: const Icon(Icons.logout_rounded, size: 17),
                                label: Text('Hasta ${TimeInterval.formatHm(selEnd)}'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          key: const Key('dynamic_salary_preview_card'),
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.primarySurface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppTheme.primary.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Horario: ${selectedInterval.formattedRange}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.darkSlate,
                                    ),
                                  ),
                                  Text(
                                    selectedInterval.formattedDuration,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Sueldo del servicio (${c.pricePerHour.toStringAsFixed(2)} €/h × ${exactHours.toStringAsFixed(2)} h${exactHours >= 4.0 ? " · -5% bono" : ""}): ${estimatedServicePay.toStringAsFixed(2)} €',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.slateMuted,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Total con cobertura plataforma (3%): ${estimatedTotalClient.toStringAsFixed(2)} €',
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (!validDuration)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Text(
                              'La duración mínima de reserva es de 30 minutos.',
                              style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold),
                            ),
                          ),
                        if (!minTwoHoursOk)
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
                        if (!(auth?.canManageFamilyPayments ?? true))
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.amber.shade300),
                            ),
                            child: const Text(
                              'Tu rol es Familiar colaborador. Solo un Administrador de la familia puede confirmar pagos y reservas.',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            key: const Key('reserve_flexible_btn'),
                            onPressed: (auth?.canManageFamilyPayments ?? true) &&
                                    validDuration &&
                                    minTwoHoursOk &&
                                    c.hasStripeAccount
                                ? () {
                                    final dateStr =
                                        '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
                                    final matchingSlots = _slots.where((s) {
                                      final sStart = s.dateTime;
                                      final sEnd = s.effectiveEndTime;
                                      return s.isAvailable &&
                                          sStart.isBefore(selEnd) &&
                                          sEnd.isAfter(selStart);
                                    }).toList();
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => PaymentScreen(
                                          caregiver: c,
                                          dateString: dateStr,
                                          slots: matchingSlots.isNotEmpty
                                              ? matchingSlots
                                              : [
                                                  TimeSlot(
                                                    id: 'flex_sel',
                                                    dateTime: selStart,
                                                    endTime: selEnd,
                                                  ),
                                                ],
                                          customStartTime: selStart,
                                          customEndTime: selEnd,
                                        ),
                                      ),
                                    );
                                  }
                                : null,
                            child: Text(
                              'Reservar ${selectedInterval.formattedDuration} · ${estimatedTotalClient.toStringAsFixed(2)} €',
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                ),
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),
                Text('Valoraciones y Desglose de Calidad', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                _buildCategoryRatingsBreakdown(c),
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
      floatingActionButton: isOwnProfile
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                final auth = context.read<AuthNotifier>();
                Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(
                  clientId: auth.effectiveClientId ?? 'unknown',
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

  Widget _buildCategoryRatingsBreakdown(CaregiverProfile c) {
    final baseScore = c.rating > 0 ? c.rating : 4.9;
    double avgPunctuality = baseScore;
    double avgEmpathy = baseScore;
    double avgCommunication = baseScore;
    double avgHygiene = baseScore;

    if (_reviews.isNotEmpty) {
      final pList = _reviews.map((r) => r.punctualityRating).toList();
      final eList = _reviews.map((r) => r.empathyRating).toList();
      final cList = _reviews.map((r) => r.communicationRating).toList();
      final hList = _reviews.map((r) => r.hygieneRating).toList();

      avgPunctuality = pList.reduce((a, b) => a + b) / pList.length;
      avgEmpathy = eList.reduce((a, b) => a + b) / eList.length;
      avgCommunication = cList.reduce((a, b) => a + b) / cList.length;
      avgHygiene = hList.reduce((a, b) => a + b) / hList.length;
    }

    final categories = [
      {'label': '⏰ Puntualidad', 'score': avgPunctuality},
      {'label': '💛 Trato y Empatía', 'score': avgEmpathy},
      {'label': '💬 Comunicación con la familia', 'score': avgCommunication},
      {'label': '✨ Higiene y Asistencia', 'score': avgHygiene},
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundNeutral,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Column(
        children: categories.map((cat) {
          final label = cat['label'] as String;
          final score = (cat['score'] as double).clamp(1.0, 5.0);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.darkSlate,
                    ),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: score / 5.0,
                      minHeight: 7,
                      backgroundColor: Colors.grey.shade300,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 28,
                  child: Text(
                    score.toStringAsFixed(1),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: AppTheme.darkSlate,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

