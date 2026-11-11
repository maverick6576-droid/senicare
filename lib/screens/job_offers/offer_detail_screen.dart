import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/firebase/firestore_stats_repository.dart';
import 'package:senicare/screens/screens.dart';
import 'package:senicare/widgets/widgets.dart';

class OfferDetailScreen extends StatefulWidget {
  final JobOffer offer;
  const OfferDetailScreen({super.key, required this.offer});

  @override
  State<OfferDetailScreen> createState() => _OfferDetailScreenState();
}

class _OfferDetailScreenState extends State<OfferDetailScreen> {
  final _msgCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  int _accumulatedHours = 0;

  @override
  void initState() {
    super.initState();
    _priceCtrl.text = widget.offer.pricePerHour.toStringAsFixed(2);
    _loadAccumulatedHours();
  }

  Future<void> _loadAccumulatedHours() async {
    final auth = context.read<AuthNotifier>();
    if (auth.currentRole == 'client') return;
    final caregiverId = auth.currentUserId;
    if (caregiverId == null || caregiverId.isEmpty) return;

    try {
      final hrs = await DependencyInjection.stats.getAccumulatedHours(
        widget.offer.clientId,
        caregiverId,
      );
      if (mounted) {
        setState(() => _accumulatedHours = hrs);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  double _effectiveCommissionRate(JobOffer offer) {
    return FirestoreStatsRepository.calculateEffectiveOfferCommissionRate(
      _accumulatedHours,
      offer.urgencyBonusRate,
    );
  }

  double _calculateNetTotal(JobOffer offer, double hourlyRate) {
    return FirestoreStatsRepository.estimateOfferNetTotal(
      totalHours: offer.totalHours,
      hourlyRate: hourlyRate,
      urgencyBonusRate: offer.urgencyBonusRate,
      accumulatedHours: _accumulatedHours,
    );
  }

  String _formatDateTimeRange(JobOffer offer) {
    final start = offer.startDate;
    final startStr =
        '${start.day.toString().padLeft(2, '0')}/${start.month.toString().padLeft(2, '0')}/${start.year} a las ${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';

    if (offer.isRecurring && offer.recurringWeeks > 0) {
      return 'Inicio: $startStr (${offer.recurringWeeks} sem., ${offer.totalHours}h totales)';
    }

    final end = start.add(Duration(hours: offer.totalHours));
    final sameDay = start.year == end.year && start.month == end.month && start.day == end.day;
    final endTimeStr = '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
    if (sameDay) {
      return 'Inicio: $startStr (hasta aprox. $endTimeStr)';
    }
    return 'Inicio: $startStr';
  }

  ({String label, Color bg, Color border, Color text}) _resolveStatusBadge(JobOffer offer) {
    if (offer.isExpired) {
      return (
        label: '⏳ Caducada',
        bg: Colors.grey.shade100,
        border: Colors.grey.shade300,
        text: Colors.grey.shade700,
      );
    }
    switch (offer.status) {
      case JobOfferStatus.open:
        return (
          label: '🟢 Abierta',
          bg: Colors.green.shade50,
          border: Colors.green.shade300,
          text: Colors.green.shade800,
        );
      case JobOfferStatus.cancelled:
        return (
          label: '🚫 Cancelada',
          bg: Colors.red.shade50,
          border: Colors.red.shade300,
          text: Colors.red.shade800,
        );
      case JobOfferStatus.inProgress:
        return (
          label: '🤝 Contratada',
          bg: Colors.blue.shade50,
          border: Colors.blue.shade300,
          text: Colors.blue.shade800,
        );
      case JobOfferStatus.completed:
        return (
          label: '✅ Finalizada',
          bg: Colors.blue.shade50,
          border: Colors.blue.shade300,
          text: Colors.blue.shade800,
        );
    }
  }

  void _openApplicationModal({
    required JobOffer offer,
    JobApplication? existingApplication,
  }) {
    final caregiver = context.read<AuthNotifier>().currentCaregiver;
    if (caregiver == null) return;

    _msgCtrl.text = existingApplication?.message ?? '';
    final initialPrice = existingApplication?.proposedPrice ?? offer.pricePerHour;
    _priceCtrl.text = initialPrice.toStringAsFixed(2);

    bool isSubmitting = false;
    String? priceError;
    String? submitError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (modalCtx, setModalState) {
          final parsedPrice = double.tryParse(_priceCtrl.text.trim().replaceAll(',', '.'));
          final commissionPct = (_effectiveCommissionRate(offer) * 100).round();
          final previewNet = (parsedPrice != null && parsedPrice > 0)
              ? _calculateNetTotal(offer, parsedPrice)
              : null;

          Future<void> submit() async {
            final cleanText = _priceCtrl.text.trim().replaceAll(',', '.');
            final price = double.tryParse(cleanText);
            if (price == null || price <= 0 || price > 200) {
              setModalState(() {
                priceError = 'Introduce un precio válido entre 1 €/h y 200 €/h.';
              });
              return;
            }

            setModalState(() {
              isSubmitting = true;
              priceError = null;
              submitError = null;
            });

            try {
              final jobNotifier = context.read<JobOfferNotifier>();
              if (existingApplication != null) {
                await jobNotifier.updateApplication(
                  offer.id,
                  existingApplication.id,
                  message: _msgCtrl.text.trim(),
                  proposedPrice: price,
                  caregiverId: caregiver.id,
                );
              } else {
                final app = JobApplication(
                  id: caregiver.id,
                  offerId: offer.id,
                  caregiverId: caregiver.id,
                  caregiverName: caregiver.name,
                  caregiverImageUrl: caregiver.imageUrl,
                  caregiverRating: caregiver.rating,
                  caregiverReviewsCount: caregiver.reviewsCount,
                  message: _msgCtrl.text.trim(),
                  proposedPrice: price,
                  appliedAt: DateTime.now(),
                );
                await jobNotifier.applyToOffer(app, offer: offer);
              }

              if (sheetCtx.mounted) {
                Navigator.pop(sheetCtx);
              }
              if (mounted) {
                CustomSnackBar.show(
                  context,
                  message: existingApplication != null
                      ? 'Propuesta actualizada correctamente.'
                      : 'Solicitud enviada a la familia.',
                  type: SnackBarType.success,
                );
              }
            } catch (e) {
              setModalState(() {
                isSubmitting = false;
                submitError = e.toString().replaceAll('Exception: ', '');
              });
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
              left: 20,
              right: 20,
              top: 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    existingApplication != null ? 'Editar tu propuesta' : 'Postularme a esta oferta',
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppTheme.darkSlate),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'La familia ofrece ${offer.pricePerHour.toStringAsFixed(2)} €/h por ${offer.totalHours}h. Puedes mantener el precio o proponer otro.',
                    style: const TextStyle(fontSize: 13.5, color: AppTheme.slateMuted, height: 1.35),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _priceCtrl,
                    decoration: InputDecoration(
                      labelText: 'Tu tarifa propuesta (€/h)',
                      border: const OutlineInputBorder(),
                      errorText: priceError,
                      suffixText: '€/h',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setModalState(() => priceError = null),
                  ),
                  if (previewNet != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.primarySurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Comisión est. ($commissionPct%):',
                            style: const TextStyle(fontSize: 12.5, color: AppTheme.slateMuted, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            'Ganarás ~${previewNet.toStringAsFixed(2)} € netos',
                            style: const TextStyle(
                              fontSize: 13.5,
                              color: AppTheme.secondaryColor,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  TextField(
                    controller: _msgCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Mensaje de presentación (opcional)',
                      hintText: 'Ej. Tengo experiencia en cuidados a domicilio y disponibilidad inmediata.',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  if (submitError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      submitError!,
                      style: TextStyle(color: Colors.red.shade700, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: isSubmitting ? null : submit,
                      child: isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                            )
                          : Text(existingApplication != null ? 'Guardar Cambios' : 'Enviar Solicitud'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _withdrawApplication(JobOffer offer, JobApplication myApp, String caregiverId) async {
    final confirm = await CustomDialog.showConfirmation(
      context,
      title: 'Retirar Solicitud',
      message: '¿Seguro que quieres retirar tu candidatura de esta oferta?',
      confirmText: 'Sí, retirar',
      cancelText: 'Mantener',
      isDestructive: true,
    );
    if (confirm != true || !mounted) return;

    try {
      await context.read<JobOfferNotifier>().withdrawApplication(offer.id, myApp.id, caregiverId);
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: 'Solicitud retirada correctamente.',
          type: SnackBarType.info,
        );
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: 'No se pudo retirar la solicitud. Inténtalo de nuevo.',
          type: SnackBarType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthNotifier>();
    final location = context.watch<LocationNotifier>();
    final isClient = auth.currentRole == 'client';
    final currentUserId = auth.currentUserId ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de Oferta')),
      body: StreamBuilder<JobOffer?>(
        stream: DependencyInjection.jobOffers.streamOffer(widget.offer.id),
        initialData: widget.offer,
        builder: (context, offerSnapshot) {
          final offer = offerSnapshot.data ?? widget.offer;

          if (isClient) {
            return StreamBuilder<List<JobApplication>>(
              stream: DependencyInjection.jobOffers.streamOfferApplications(offer.id),
              builder: (context, appsSnapshot) {
                final apps = appsSnapshot.data ?? [];
                return _buildBody(
                  context: context,
                  offer: offer,
                  isClient: true,
                  currentUserId: currentUserId,
                  caregiver: auth.currentCaregiver,
                  caregiverLat: null,
                  caregiverLng: null,
                  clientApps: apps,
                  myApp: null,
                );
              },
            );
          }

          final caregiver = auth.currentCaregiver;
          return StreamBuilder<JobApplication?>(
            stream: DependencyInjection.jobOffers.streamCaregiverApplicationForOffer(offer.id, currentUserId),
            builder: (context, myAppSnapshot) {
              return _buildBody(
                context: context,
                offer: offer,
                isClient: false,
                currentUserId: currentUserId,
                caregiver: caregiver,
                caregiverLat: caregiver?.latitude ?? location.latitude,
                caregiverLng: caregiver?.longitude ?? location.longitude,
                clientApps: const [],
                myApp: myAppSnapshot.data,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildBody({
    required BuildContext context,
    required JobOffer offer,
    required bool isClient,
    required String currentUserId,
    required CaregiverProfile? caregiver,
    required double? caregiverLat,
    required double? caregiverLng,
    required List<JobApplication> clientApps,
    required JobApplication? myApp,
  }) {
    final badge = _resolveStatusBadge(offer);
    final commissionPct = (_effectiveCommissionRate(offer) * 100).round();
    final estimatedNet = _calculateNetTotal(offer, offer.pricePerHour);
    final distanceKm = (!isClient && caregiverLat != null && caregiverLng != null)
        ? calculateDistance(caregiverLat, caregiverLng, offer.clientLatitude, offer.clientLongitude)
        : null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: AppTheme.modernCardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isClient) ...[
                          Text(
                            offer.familyLabel,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                        Text(
                          offer.title,
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.darkSlate,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: badge.bg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: badge.border),
                    ),
                    child: Text(
                      badge.label,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: badge.text),
                    ),
                  ),
                ],
              ),
              if (distanceKm != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.primarySurface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '📍 A ${distanceKm.toStringAsFixed(1)} km de tu ubicación',
                    style: const TextStyle(color: AppTheme.primary, fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                offer.description,
                style: const TextStyle(fontSize: 14.5, color: AppTheme.slateMuted, height: 1.45),
              ),
              if (offer.isUrgent) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.flash_on_rounded, color: Colors.orange.shade800),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isClient
                              ? '⚡ Oferta Urgente: destacada prioritariamente y con comisión reducida para atraer más cuidadores rápido.'
                              : '⚡ ¡Oferta Urgente! Tu comisión de plataforma se reduce en 10 puntos (comisión estimada: $commissionPct%, cobras el ${100 - commissionPct}% neto).',
                          style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.w700, fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Divider(height: 1),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primarySurface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.euro_rounded, color: AppTheme.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${offer.pricePerHour.toStringAsFixed(2)} €/h  •  Total oferta: ${(offer.totalHours * offer.pricePerHour).toStringAsFixed(2)} €',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.darkSlate),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${offer.totalHours}h en total (${offer.isRecurring ? "Servicio recurrente" : "Servicio puntual"})',
                          style: const TextStyle(fontSize: 12.5, color: AppTheme.slateMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (!isClient) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primarySurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Lo que ganarás tú (estimado)',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.darkSlate),
                            ),
                            Text(
                              'Tras comisión SeniCare ($commissionPct%)',
                              style: const TextStyle(fontSize: 11.5, color: AppTheme.slateMuted),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '~${estimatedNet.toStringAsFixed(2)} € netos',
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.secondaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primarySurface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.calendar_today_rounded, color: AppTheme.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _formatDateTimeRange(offer),
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.darkSlate),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (!isClient) ...[
          const SizedBox(height: 18),
          _buildCaregiverActionSection(
            context: context,
            offer: offer,
            caregiver: caregiver,
            currentUserId: currentUserId,
            myApp: myApp,
          ),
        ],
        if (isClient) ...[
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Candidatos Interesados',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.darkSlate),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primarySurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${clientApps.length}',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.primary, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (clientApps.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: AppTheme.modernCardDecoration(),
              child: const Column(
                children: [
                  Icon(Icons.hourglass_top_rounded, size: 40, color: AppTheme.primary),
                  SizedBox(height: 10),
                  Text(
                    'Avisando a los cuidadores verificados de tu zona',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.darkSlate),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'En cuanto un profesional se postule, verás aquí su valoración, su propuesta económica y podrás revisar su perfil antes de contratar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: AppTheme.slateMuted, height: 1.4),
                  ),
                ],
              ),
            )
          else
            ...clientApps.map(
              (app) => Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () async {
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => const Center(child: CircularProgressIndicator()),
                    );
                    final selectedCaregiver = await DependencyInjection.caregivers.getCaregiver(app.caregiverId);
                    if (context.mounted) {
                      Navigator.pop(context);
                      if (selectedCaregiver != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => CaregiverDetailScreen(caregiver: selectedCaregiver)),
                        );
                      } else {
                        CustomSnackBar.show(
                          context,
                          message: 'No se pudo cargar el perfil del cuidador.',
                          type: SnackBarType.error,
                        );
                      }
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            ClipOval(
                              child: app.caregiverImageUrl.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: app.caregiverImageUrl,
                                      width: 42,
                                      height: 42,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, _, _) => Container(
                                        width: 42,
                                        height: 42,
                                        color: AppTheme.primarySurface,
                                        child: const Icon(Icons.person, color: AppTheme.primary),
                                      ),
                                    )
                                  : Container(
                                      width: 42,
                                      height: 42,
                                      color: AppTheme.primarySurface,
                                      child: const Icon(Icons.person, color: AppTheme.primary),
                                    ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(app.caregiverName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  Row(
                                    children: [
                                      const Icon(Icons.star, color: Colors.amber, size: 16),
                                      Text(' ${app.caregiverRating.toStringAsFixed(1)} (${app.caregiverReviewsCount})'),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${app.proposedPrice.toStringAsFixed(2)} €/h',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary, fontSize: 16),
                            ),
                          ],
                        ),
                        if (app.message.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text('"${app.message}"', style: const TextStyle(fontStyle: FontStyle.italic)),
                          ),
                        const SizedBox(height: 12),
                        if (offer.status == JobOfferStatus.open &&
                            !offer.isExpired &&
                            app.status == JobApplicationStatus.pending)
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => JobOfferPaymentScreen(offer: offer, application: app),
                                  ),
                                );
                              },
                              child: const Text('Aceptar Cuidador'),
                            ),
                          )
                        else if (app.status == JobApplicationStatus.accepted)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(8),
                            color: Colors.green.shade100,
                            child: const Text(
                              '✓ Cuidador Aceptado',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                            ),
                          )
                        else if (app.status == JobApplicationStatus.rejected)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(8),
                            color: Colors.grey.shade200,
                            child: const Text(
                              '✗ Rechazado',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (offer.status == JobOfferStatus.open) ...[
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final confirm = await CustomDialog.showConfirmation(
                    context,
                    title: 'Retirar Oferta',
                    message:
                        '¿Estás seguro de que deseas retirar esta oferta? Se cerrará la convocatoria y los cuidadores ya no podrán postularse.',
                    confirmText: 'Retirar Oferta',
                    cancelText: 'Mantener',
                    isDestructive: true,
                  );
                  if (confirm == true && context.mounted) {
                    await context.read<JobOfferNotifier>().cancelOffer(offer.id);
                    if (context.mounted) {
                      CustomSnackBar.show(context, message: 'Oferta retirada correctamente', type: SnackBarType.info);
                      Navigator.pop(context);
                    }
                  }
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade300),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Retirar / Cancelar Oferta'),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildCaregiverActionSection({
    required BuildContext context,
    required JobOffer offer,
    required CaregiverProfile? caregiver,
    required String currentUserId,
    required JobApplication? myApp,
  }) {
    if (myApp != null &&
        (myApp.status == JobApplicationStatus.accepted || offer.acceptedCaregiverId == currentUserId)) {
      return _buildCaregiverStateBox(
        icon: Icons.celebration_rounded,
        color: Colors.green.shade800,
        bgColor: Colors.green.shade50,
        borderColor: Colors.green.shade300,
        title: '¡Enhorabuena, la familia te ha elegido!',
        message:
            'Tu servicio ya está confirmado con pago protegido. Abre la pestaña Inicio o Reservas para ver el domicilio, el PIN de entrada y la lista de cuidados.',
      );
    }

    if (myApp != null && myApp.status == JobApplicationStatus.rejected) {
      return _buildCaregiverStateBox(
        icon: Icons.info_outline_rounded,
        color: AppTheme.slateMuted,
        bgColor: Colors.grey.shade100,
        borderColor: Colors.grey.shade300,
        title: 'Candidatura no seleccionada',
        message: 'La familia eligió a otro profesional para este cuidado. Sigue consultando nuevas ofertas en tu zona.',
      );
    }

    if (offer.status != JobOfferStatus.open || offer.isExpired) {
      final reason = offer.status == JobOfferStatus.cancelled
          ? 'La familia ha retirado esta oferta.'
          : offer.isExpired
              ? 'La fecha de inicio de esta oferta ya ha pasado.'
              : 'Esta oferta ya ha sido cubierta por otro cuidador.';
      return _buildCaregiverStateBox(
        icon: Icons.lock_clock_rounded,
        color: AppTheme.slateMuted,
        bgColor: Colors.grey.shade100,
        borderColor: Colors.grey.shade300,
        title: 'Convocatoria cerrada',
        message: reason,
      );
    }

    if (myApp != null && myApp.status == JobApplicationStatus.pending) {
      final proposedNet = _calculateNetTotal(offer, myApp.proposedPrice);
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.teal.shade50,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.teal.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.teal.shade800, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Solicitud enviada a la familia',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.teal.shade900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Tu tarifa propuesta: ${myApp.proposedPrice.toStringAsFixed(2)} €/h (~${proposedNet.toStringAsFixed(2)} € netos).',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.teal.shade900),
            ),
            if (myApp.message.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Tu mensaje: "${myApp.message.trim()}"',
                style: TextStyle(fontSize: 13.5, fontStyle: FontStyle.italic, color: Colors.teal.shade800),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      minimumSize: const Size(0, 46),
                    ),
                    onPressed: () => _openApplicationModal(offer: offer, existingApplication: myApp),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Editar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade300),
                      minimumSize: const Size(0, 46),
                    ),
                    onPressed: () => _withdrawApplication(offer, myApp, currentUserId),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Retirar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (caregiver == null) {
      return const SizedBox.shrink();
    }

    if (caregiver.accountStatus == 'suspended') {
      return _buildCaregiverStateBox(
        icon: Icons.block_rounded,
        color: Colors.red.shade800,
        bgColor: Colors.red.shade50,
        borderColor: Colors.red.shade300,
        title: 'No puedes postularte ahora',
        message: 'Tu cuenta está suspendida por incomparecencias repetidas (No-Show).',
      );
    }

    if (caregiver.blockedUntil != null && caregiver.blockedUntil!.isAfter(DateTime.now())) {
      final until = caregiver.blockedUntil!;
      final untilStr =
          '${until.day.toString().padLeft(2, '0')}/${until.month.toString().padLeft(2, '0')}/${until.year}';
      return _buildCaregiverStateBox(
        icon: Icons.timer_off_outlined,
        color: Colors.orange.shade900,
        bgColor: Colors.orange.shade50,
        borderColor: Colors.orange.shade300,
        title: 'Postulación bloqueada temporalmente',
        message: 'Podrás volver a aplicar a ofertas a partir del $untilStr.',
      );
    }

    final isVerified = caregiver.verified || caregiver.verificationStatus == 'approved';
    if (!isVerified) {
      final isRejected = caregiver.verificationStatus == 'rejected';
      return _buildCaregiverStateBox(
        icon: isRejected ? Icons.error_outline_rounded : Icons.verified_user_outlined,
        color: isRejected ? Colors.red.shade800 : Colors.orange.shade900,
        bgColor: isRejected ? Colors.red.shade50 : Colors.orange.shade50,
        borderColor: isRejected ? Colors.red.shade300 : Colors.orange.shade300,
        title: isRejected ? 'Verificación rechazada' : 'Perfil pendiente de verificación',
        message: isRejected
            ? 'Actualiza tu DNI o antecedentes penales en Mi Perfil para poder postularte a ofertas.'
            : 'Para seguridad de las familias, tu perfil debe ser aprobado antes de poder enviarte como candidato.',
        actionLabel: 'Revisar Mi Perfil',
        onAction: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const CaregiverProfileEditScreen()));
        },
      );
    }

    if (!caregiver.hasStripeAccount) {
      return _buildCaregiverStateBox(
        icon: Icons.account_balance_outlined,
        color: Colors.orange.shade900,
        bgColor: Colors.orange.shade50,
        borderColor: Colors.orange.shade300,
        title: 'Falta tu cuenta de cobro',
        message: 'Configura tu cuenta bancaria (Stripe) en Mi Perfil para poder recibir los pagos de tus servicios.',
        actionLabel: 'Configurar en Mi Perfil',
        onAction: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const CaregiverProfileEditScreen()));
        },
      );
    }

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: () => _openApplicationModal(offer: offer),
        icon: const Icon(Icons.send_rounded, size: 18),
        label: const Text('Postularme a este cuidado'),
      ),
    );
  }

  Widget _buildCaregiverStateBox({
    required IconData icon,
    required Color color,
    required Color bgColor,
    required Color borderColor,
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(message, style: TextStyle(fontSize: 13.5, color: color, height: 1.4)),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: onAction,
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: Text(actionLabel),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
