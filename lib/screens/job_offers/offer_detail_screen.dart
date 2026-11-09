import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/screens/job_offers/job_offer_payment_screen.dart';
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
          Text(widget.offer.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(widget.offer.description),
          const SizedBox(height: 16),
          if (widget.offer.isUrgent)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  const Icon(Icons.flash_on, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(child: Text(isClient ? 'Oferta Urgente: Atraerá a más cuidadores' : '¡URGENTE! Ganas un +10% de comisión extra si te aceptan.', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))),
                ],
              ),
            ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.euro),
            title: Text('${widget.offer.pricePerHour} €/h (Total estimado: ${widget.offer.totalHours * widget.offer.pricePerHour}€)'),
            subtitle: Text(widget.offer.isRecurring ? 'Servicio recurrente' : 'Servicio puntual'),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_today),
            title: Text('Inicio: ${widget.offer.startDate.day.toString().padLeft(2, '0')}/${widget.offer.startDate.month.toString().padLeft(2, '0')}/${widget.offer.startDate.year} ${widget.offer.startDate.hour.toString().padLeft(2, '0')}:${widget.offer.startDate.minute.toString().padLeft(2, '0')}'),
          ),
          if (!isClient && widget.offer.status == JobOfferStatus.open && !widget.offer.isExpired)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: hasApplied 
                  ? FilledButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.check_circle),
                      label: const Text('Solicitud Enviada'),
                    )
                  : FilledButton(
                      onPressed: () => _apply(context),
                      child: const Text('Solicitar este trabajo'),
                    ),
            ),
          
          if (isClient) ...[
            const Divider(height: 32),
            const Text('Solicitudes Recibidas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            if (apps.isEmpty)
              const Text('Aún no hay cuidadores interesados.')
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
                            CircleAvatar(backgroundImage: CachedNetworkImageProvider(app.caregiverImageUrl)),
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
              )).toList(),
          ]
        ],
      );
      }),
    );
  }
}




