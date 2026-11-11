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

    final seniorMode = context.watch<ConfigNotifier>().seniorMode;

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
                  seniorMode: seniorMode,
                  currentUserId: currentUserId,
                  clientName: auth.currentClient?.name,
                  caregiver: auth.currentCaregiver,
                  caregiverLat: null,
                  caregiverLng: null,
                  clientApps: apps,
                  isLoadingClientApps: appsSnapshot.connectionState == ConnectionState.waiting && !appsSnapshot.hasData,
                  clientAppsError: appsSnapshot.hasError ? 'No pudimos cargar las candidaturas. Revisa tu conexión.' : null,
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
                seniorMode: seniorMode,
                currentUserId: currentUserId,
                clientName: auth.currentClient?.name,
                caregiver: caregiver,
                caregiverLat: caregiver?.latitude ?? location.latitude,
                caregiverLng: caregiver?.longitude ?? location.longitude,
                clientApps: const [],
                isLoadingClientApps: false,
                clientAppsError: null,
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
    required bool seniorMode,
    required String currentUserId,
    required String? clientName,
    required CaregiverProfile? caregiver,
    required double? caregiverLat,
    required double? caregiverLng,
    required List<JobApplication> clientApps,
    required bool isLoadingClientApps,
    required String? clientAppsError,
    required JobApplication? myApp,
  }) {
    final badge = _resolveStatusBadge(offer);
    final commissionPct = (_effectiveCommissionRate(offer) * 100).round();
    final estimatedNet = _calculateNetTotal(offer, offer.pricePerHour);
    final distanceKm = (!isClient && caregiverLat != null && caregiverLng != null)
        ? calculateDistance(caregiverLat, caregiverLng, offer.clientLatitude, offer.clientLongitude)
        : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 72),
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
          const SizedBox(height: 20),
          _buildClientStatusGuide(
            context: context,
            offer: offer,
            clientApps: clientApps,
            seniorMode: seniorMode,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Candidatos Interesados',
                  style: TextStyle(
                    fontSize: seniorMode ? 20 : 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.darkSlate,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primarySurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${clientApps.length}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary,
                    fontSize: seniorMode ? 15 : 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (clientAppsError != null)
            _buildClientMessageBox(
              icon: Icons.error_outline_rounded,
              iconColor: Colors.red.shade600,
              title: 'No pudimos cargar las candidaturas',
              subtitle: clientAppsError,
              seniorMode: seniorMode,
            )
          else if (isLoadingClientApps)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (clientApps.isEmpty)
            _buildClientMessageBox(
              icon: Icons.hourglass_top_rounded,
              iconColor: AppTheme.primary,
              title: 'Avisando a cuidadores verificados de tu zona',
              subtitle:
                  'En cuanto un profesional responda, podrás ver su perfil, hablar por chat o contratarle con pago protegido.',
              seniorMode: seniorMode,
            )
          else
            ..._sortedClientApps(clientApps).map(
              (app) => _buildClientCandidateCard(
                context: context,
                offer: offer,
                app: app,
                currentUserId: currentUserId,
                clientName: clientName,
                seniorMode: seniorMode,
              ),
            ),
          if (offer.isExpired || offer.status == JobOfferStatus.cancelled) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: seniorMode ? 54 : 48,
              child: FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => CreateOfferScreen(initialOffer: offer)),
                ),
                icon: const Icon(Icons.replay_rounded),
                label: Text(
                  'Volver a Publicar Oferta',
                  style: TextStyle(fontSize: seniorMode ? 16.5 : 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
          if (offer.status == JobOfferStatus.open) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: seniorMode ? 52 : 46,
              child: OutlinedButton.icon(
                onPressed: () => _confirmCancelOffer(context, offer),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade300),
                ),
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: Text(
                  offer.isExpired ? 'Cerrar Oferta Caducada' : 'Retirar / Cancelar Oferta',
                  style: TextStyle(fontSize: seniorMode ? 15.5 : 14, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
        ],
      ],
    );
  }

  List<JobApplication> _sortedClientApps(List<JobApplication> apps) {
    int rank(JobApplicationStatus s) {
      switch (s) {
        case JobApplicationStatus.accepted:
          return 0;
        case JobApplicationStatus.pending:
          return 1;
        case JobApplicationStatus.rejected:
          return 2;
      }
    }

    final sorted = List<JobApplication>.from(apps);
    sorted.sort((a, b) {
      final r = rank(a.status).compareTo(rank(b.status));
      if (r != 0) return r;
      return b.appliedAt.compareTo(a.appliedAt);
    });
    return sorted;
  }

  Widget _buildClientStatusGuide({
    required BuildContext context,
    required JobOffer offer,
    required List<JobApplication> clientApps,
    required bool seniorMode,
  }) {
    final pendingCount = clientApps.where((a) => a.status == JobApplicationStatus.pending).length;
    late final Color bg;
    late final Color border;
    late final Color fg;
    late final IconData icon;
    late final String title;
    late final String subtitle;

    if (offer.status == JobOfferStatus.inProgress) {
      bg = Colors.green.shade50;
      border = Colors.green.shade200;
      fg = Colors.green.shade900;
      icon = Icons.verified_rounded;
      title = 'Cuidador confirmado y reserva asegurada';
      subtitle = 'Puedes hablar con tu cuidador por chat debajo o revisar los detalles en la pestaña Reservas.';
    } else if (offer.isExpired) {
      bg = Colors.grey.shade100;
      border = Colors.grey.shade300;
      fg = AppTheme.darkSlate;
      icon = Icons.event_busy_rounded;
      title = 'La fecha de esta oferta ya pasó';
      subtitle = 'Si sigues necesitando ayuda, pulsa "Volver a Publicar Oferta" con los mismos datos en un toque.';
    } else if (offer.status == JobOfferStatus.cancelled) {
      bg = Colors.red.shade50;
      border = Colors.red.shade200;
      fg = Colors.red.shade900;
      icon = Icons.cancel_rounded;
      title = 'Oferta retirada';
      subtitle = 'Esta convocatoria está cerrada. Puedes volver a publicarla cuando la necesites.';
    } else if (pendingCount > 0) {
      bg = Colors.amber.shade50;
      border = Colors.amber.shade300;
      fg = Colors.amber.shade900;
      icon = Icons.people_alt_rounded;
      title = 'Tienes $pendingCount candidatura${pendingCount == 1 ? '' : 's'} para revisar';
      subtitle = 'Chatea gratis con quien quieras o elige al cuidador ideal para confirmar la reserva.';
    } else {
      bg = AppTheme.primarySurface;
      border = AppTheme.primary.withValues(alpha: 0.25);
      fg = AppTheme.darkSlate;
      icon = Icons.campaign_rounded;
      title = 'Oferta visible para cuidadores cercanos';
      subtitle = 'Recibirás aquí las propuestas. Publicar es gratis hasta que contrates.';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: seniorMode ? 24 : 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: seniorMode ? 15.5 : 14,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: seniorMode ? 14 : 12.5,
                    color: fg.withValues(alpha: 0.88),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClientMessageBox({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool seniorMode,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: AppTheme.modernCardDecoration(),
      child: Column(
        children: [
          Icon(icon, size: 40, color: iconColor),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: seniorMode ? 17 : 15,
              color: AppTheme.darkSlate,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: seniorMode ? 14.5 : 13,
              color: AppTheme.slateMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClientCandidateCard({
    required BuildContext context,
    required JobOffer offer,
    required JobApplication app,
    required String currentUserId,
    required String? clientName,
    required bool seniorMode,
  }) {
    final totalService = app.proposedPrice * offer.totalHours;
    final totalWithFee = totalService * (1 + offer.clientFeeRate);
    final diffPerHour = app.proposedPrice - offer.pricePerHour;
    final firstName = app.caregiverName.trim().split(' ').first;
    final isAccepted = app.status == JobApplicationStatus.accepted;
    final isRejected = app.status == JobApplicationStatus.rejected;
    final canChoose =
        offer.status == JobOfferStatus.open && !offer.isExpired && app.status == JobApplicationStatus.pending;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isAccepted ? Colors.green.shade300 : Colors.grey.shade200,
          width: isAccepted ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _openCandidateProfile(context, app.caregiverId),
              child: Row(
                children: [
                  ClipOval(
                    child: app.caregiverImageUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: app.caregiverImageUrl,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => Container(
                              width: 48,
                              height: 48,
                              color: AppTheme.primarySurface,
                              child: const Icon(Icons.person, color: AppTheme.primary),
                            ),
                          )
                        : Container(
                            width: 48,
                            height: 48,
                            color: AppTheme.primarySurface,
                            child: const Icon(Icons.person, color: AppTheme.primary),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app.caregiverName,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: seniorMode ? 17.5 : 15.5,
                            color: AppTheme.darkSlate,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.star_rounded, color: Colors.amber, size: 17),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                '${app.caregiverRating.toStringAsFixed(1)} (${app.caregiverReviewsCount} reseñas)',
                                style: TextStyle(
                                  fontSize: seniorMode ? 14 : 12.5,
                                  color: AppTheme.slateMuted,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${app.proposedPrice.toStringAsFixed(2)} €/h',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primary,
                          fontSize: seniorMode ? 17 : 15.5,
                        ),
                      ),
                      Text(
                        'Total ${totalService.toStringAsFixed(0)} €',
                        style: TextStyle(
                          fontSize: seniorMode ? 13 : 11.5,
                          color: AppTheme.slateMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (diffPerHour.abs() >= 0.01) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: diffPerHour < 0 ? Colors.green.shade50 : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  diffPerHour < 0
                      ? 'Propone ${diffPerHour.abs().toStringAsFixed(2)} €/h menos que tu oferta'
                      : 'Propone +${diffPerHour.toStringAsFixed(2)} €/h sobre tu oferta',
                  style: TextStyle(
                    fontSize: seniorMode ? 13 : 11.5,
                    fontWeight: FontWeight.w700,
                    color: diffPerHour < 0 ? Colors.green.shade800 : Colors.orange.shade900,
                  ),
                ),
              ),
            ],
            if (app.message.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundNeutral,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '"${app.message}"',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    fontSize: seniorMode ? 15 : 13.5,
                    color: AppTheme.darkSlate,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openCandidateProfile(context, app.caregiverId),
                    icon: const Icon(Icons.person_search_rounded, size: 18),
                    label: const Text('Ver perfil'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openCandidateChat(
                      context: context,
                      clientId: currentUserId,
                      clientName: clientName,
                      app: app,
                    ),
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 17),
                    label: const Text('Chatear'),
                  ),
                ),
              ],
            ),
            if (canChoose) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: seniorMode ? 50 : 44,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => JobOfferPaymentScreen(offer: offer, application: app),
                      ),
                    );
                  },
                  icon: const Icon(Icons.verified_user_rounded, size: 18),
                  label: Text(
                    'Elegir a $firstName (${totalWithFee.toStringAsFixed(2)} €)',
                    style: TextStyle(
                      fontSize: seniorMode ? 15.5 : 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: TextButton(
                  onPressed: () => _confirmRejectApplication(context, offer.id, app),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.slateMuted),
                  child: Text(
                    'Descartar candidatura',
                    style: TextStyle(fontSize: seniorMode ? 14 : 12.5),
                  ),
                ),
              ),
            ] else if (isAccepted) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Text(
                  '✓ Cuidador confirmado para este cuidado',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.green.shade800,
                    fontWeight: FontWeight.w800,
                    fontSize: seniorMode ? 15 : 13.5,
                  ),
                ),
              ),
            ] else if (isRejected) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Candidatura descartada',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: seniorMode ? 14 : 12.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openCandidateProfile(BuildContext context, String caregiverId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    CaregiverProfile? selectedCaregiver;
    try {
      selectedCaregiver = await DependencyInjection.caregivers.getCaregiver(caregiverId);
    } catch (_) {
      selectedCaregiver = null;
    } finally {
      if (context.mounted) {
        Navigator.pop(context);
      }
    }

    if (!context.mounted) return;
    if (selectedCaregiver != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => CaregiverDetailScreen(caregiver: selectedCaregiver!)),
      );
    } else {
      CustomSnackBar.show(
        context,
        message: 'No pudimos abrir el perfil de este cuidador.',
        type: SnackBarType.error,
      );
    }
  }

  void _openCandidateChat({
    required BuildContext context,
    required String clientId,
    required String? clientName,
    required JobApplication app,
  }) {
    if (clientId.isEmpty) {
      CustomSnackBar.show(
        context,
        message: 'Inicia sesión para poder abrir el chat.',
        type: SnackBarType.error,
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          clientId: clientId,
          caregiverId: app.caregiverId,
          caregiverName: app.caregiverName,
          caregiverImageUrl: app.caregiverImageUrl,
          clientName: clientName,
        ),
      ),
    );
  }

  Future<void> _confirmRejectApplication(
    BuildContext context,
    String offerId,
    JobApplication app,
  ) async {
    final confirm = await CustomDialog.showConfirmation(
      context,
      title: 'Descartar candidatura',
      message: '¿Quieres descartar la propuesta de ${app.caregiverName}? Podrás seguir viendo al resto de candidatos.',
      confirmText: 'Descartar',
      cancelText: 'Mantener',
      isDestructive: true,
    );
    if (confirm != true || !context.mounted) return;
    try {
      await context.read<JobOfferNotifier>().rejectApplication(offerId, app.id);
      if (context.mounted) {
        CustomSnackBar.show(
          context,
          message: 'Candidatura descartada.',
          type: SnackBarType.info,
        );
      }
    } catch (_) {
      if (context.mounted) {
        CustomSnackBar.show(
          context,
          message: 'No pudimos actualizar la candidatura. Inténtalo de nuevo.',
          type: SnackBarType.error,
        );
      }
    }
  }

  Future<void> _confirmCancelOffer(BuildContext context, JobOffer offer) async {
    final confirm = await CustomDialog.showConfirmation(
      context,
      title: '¿Retirar esta oferta?',
      message:
          '¿Seguro que quieres retirar esta oferta? Se cerrará la convocatoria y no recibirás más candidatos.',
      confirmText: 'Sí, retirar',
      cancelText: 'Mantener',
      isDestructive: true,
    );
    if (confirm != true || !context.mounted) return;
    try {
      await context.read<JobOfferNotifier>().cancelOffer(offer.id);
      if (context.mounted) {
        CustomSnackBar.show(
          context,
          message: 'Oferta retirada correctamente.',
          type: SnackBarType.info,
        );
        Navigator.pop(context);
      }
    } catch (_) {
      if (context.mounted) {
        CustomSnackBar.show(
          context,
          message: 'No pudimos retirar la oferta. Revisa tu conexión e inténtalo de nuevo.',
          type: SnackBarType.error,
        );
      }
    }
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
