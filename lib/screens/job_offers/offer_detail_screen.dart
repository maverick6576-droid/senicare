import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/widgets/widgets.dart';
import 'package:senicare/screens/screens.dart';
import 'package:cached_network_image/cached_network_image.dart';

class OfferDetailScreen extends StatefulWidget {
  final JobOffer offer;
  const OfferDetailScreen({super.key, required this.offer});

  @override
  State<OfferDetailScreen> createState() => _OfferDetailScreenState();
}

class _OfferDetailScreenState extends State<OfferDetailScreen> {
  final _msgCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _priceCtrl.text = widget.offer.pricePerHour.toString();
  }

  void _apply(BuildContext context) {
    final caregiver = context.read<AuthNotifier>().currentCaregiver;
    if (caregiver == null) return;
    
    if (caregiver.accountStatus == 'suspended') {
      CustomSnackBar.show(context, message: 'Tu cuenta está suspendida por incomparecencias repetidas (No-Show).', type: SnackBarType.error);
      return;
    }
    
    if (caregiver.blockedUntil != null && caregiver.blockedUntil!.isAfter(DateTime.now())) {
      CustomSnackBar.show(context, message: 'Estás penalizado por incomparecencia (No-Show). Podrás volver a aplicar el ${caregiver.blockedUntil!.day.toString().padLeft(2, '0')}/${caregiver.blockedUntil!.month.toString().padLeft(2, '0')}/${caregiver.blockedUntil!.year}.', type: SnackBarType.warning);
      return;
    }

    if (!caregiver.hasStripeAccount) {
      CustomSnackBar.show(context, message: 'Debes configurar tu cuenta bancaria (Stripe) en tu perfil para poder aplicar a ofertas.', type: SnackBarType.error);
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Solicitar esta oferta', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _msgCtrl,
              decoration: const InputDecoration(labelText: 'Mensaje de presentación (opcional)', border: OutlineInputBorder()),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _priceCtrl,
              decoration: const InputDecoration(labelText: 'Tu precio propuesto (€/h)', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  final auth = context.read<AuthNotifier>();
                  final caregiver = auth.currentCaregiver;
                  if (caregiver == null) return;
                  
                  final app = JobApplication(
                    id: '',
                    offerId: widget.offer.id,
                    caregiverId: caregiver.id,
                    caregiverName: caregiver.name,
                    caregiverImageUrl: caregiver.imageUrl,
                    caregiverRating: caregiver.rating,
                    caregiverReviewsCount: caregiver.reviewsCount,
                    message: _msgCtrl.text,
                    proposedPrice: double.tryParse(_priceCtrl.text) ?? widget.offer.pricePerHour,
                    appliedAt: DateTime.now(),
                  );
                  
                  await context.read<JobOfferNotifier>().applyToOffer(app);
                  if (mounted) {
                    Navigator.pop(context); // replaced ctx to use valid context
                    CustomSnackBar.show(context, message: 'Solicitud enviada al cliente', type: SnackBarType.info);
                  }
                },
                child: const Text('Enviar Solicitud'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthNotifier>();
    final isClient = auth.currentRole == 'client';
    final currentUserId = auth.currentUserId;

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de Oferta')),
      body: StreamBuilder<List<JobApplication>>(
        stream: DependencyInjection.jobOffers.streamOfferApplications(widget.offer.id),
        builder: (context, snapshot) {
          final apps = snapshot.data ?? [];
          final hasApplied = apps.any((app) => app.caregiverId == currentUserId);

          return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: AppTheme.modernCardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.offer.title,
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppTheme.darkSlate),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.offer.description,
                  style: const TextStyle(fontSize: 14, color: AppTheme.slateMuted, height: 1.4),
                ),
                if (widget.offer.isUrgent) ...[
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
                                : '⚡ ¡Oferta Urgente! Bonificación especial: tu comisión de plataforma se reduce un 10% (cobras hasta el 92% neto de tu tarifa).',
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
                            '${widget.offer.pricePerHour.toStringAsFixed(2)} €/h  •  Total est.: ${(widget.offer.totalHours * widget.offer.pricePerHour).toStringAsFixed(2)} €',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.darkSlate),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${widget.offer.totalHours}h en total (${widget.offer.isRecurring ? "Servicio recurrente" : "Servicio puntual"})',
                            style: const TextStyle(fontSize: 12.5, color: AppTheme.slateMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
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
                        'Inicio: ${widget.offer.startDate.day.toString().padLeft(2, '0')}/${widget.offer.startDate.month.toString().padLeft(2, '0')}/${widget.offer.startDate.year} a las ${widget.offer.startDate.hour.toString().padLeft(2, '0')}:${widget.offer.startDate.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.darkSlate),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (!isClient && widget.offer.status == JobOfferStatus.open && !widget.offer.isExpired)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: hasApplied 
                  ? FilledButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.check_circle),
                      label: const Text('Solicitud Enviada'),
                    )
                  : FilledButton.icon(
                      onPressed: () => _apply(context),
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: const Text('Postularme a este cuidado'),
                    ),
            ),
          
          if (isClient) ...[
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Candidatos Interesados', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.darkSlate)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primarySurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${apps.length}',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.primary, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (apps.isEmpty)
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
              ...apps.map((app) => Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () async {
                    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
                    final caregiver = await DependencyInjection.caregivers.getCaregiver(app.caregiverId);
                    if (context.mounted) {
                      Navigator.pop(context);
                      if (caregiver != null) {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => CaregiverDetailScreen(caregiver: caregiver)));
                      } else {
                        CustomSnackBar.show(context, message: 'No se pudo cargar el perfil del cuidador.', type: SnackBarType.error);
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
                          Text('${app.proposedPrice} €/h', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary, fontSize: 16)),
                        ],
                      ),
                      if (app.message.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text('"${app.message}"', style: const TextStyle(fontStyle: FontStyle.italic)),
                        ),
                      const SizedBox(height: 12),
                      if (widget.offer.status == JobOfferStatus.open && !widget.offer.isExpired && app.status == JobApplicationStatus.pending)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.push(context, MaterialPageRoute(
                                builder: (_) => JobOfferPaymentScreen(offer: widget.offer, application: app),
                              ));
                            },
                            child: const Text('Aceptar Cuidador'),
                          ),
                        )
                      else if (app.status == JobApplicationStatus.accepted)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          color: Colors.green.shade100,
                          child: const Text('✓ Cuidador Aceptado', textAlign: TextAlign.center, style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                        )
                      else if (app.status == JobApplicationStatus.rejected)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          color: Colors.grey.shade200,
                          child: const Text('✗ Rechazado', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                        )
                    ],
                  ),
                ),
              ),
              )),
          ]
        ],
      );
      }),
    );
  }
}




