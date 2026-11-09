import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/screens/screens.dart';
import 'package:senicare/widgets/widgets.dart';
import 'package:qr_flutter/qr_flutter.dart';

class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key});

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  final ScrollController _scrollActive = ScrollController();
  final ScrollController _scrollHistory = ScrollController();
  final Map<String, Future<ClientProfile?>> _clientFutures = {};

  Future<ClientProfile?> _getClientProfile(String clientId) {
    if (!_clientFutures.containsKey(clientId)) {
      _clientFutures[clientId] = DependencyInjection.clients.getClient(clientId);
    }
    return _clientFutures[clientId]!;
  }

  String _formatDay(String d) {
    try {
      final p = d.split('-');
      if (p.length == 3) return '${p[2]}/${p[1]}/${p[0]}';
    } catch (_) {}
    return d;
  }

  @override
  void initState() {
    super.initState();
    _scrollActive.addListener(_onScroll);
    _scrollHistory.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollActive.hasClients && _scrollActive.position.pixels >= _scrollActive.position.maxScrollExtent - 200) {
      context.read<BookingNotifier>().loadMoreBookings();
    }
    if (_scrollHistory.hasClients && _scrollHistory.position.pixels >= _scrollHistory.position.maxScrollExtent - 200) {
      context.read<BookingNotifier>().loadMoreBookings();
    }
  }

  @override
  void dispose() {
    _scrollActive.dispose();
    _scrollHistory.dispose();
    super.dispose();
  }

  bool _isReviewPopupShowing = false;
  final Set<String> _dismissedReviewGroups = {};

  void _checkPendingReviews(List<Booking> bookings) {
    if (_isReviewPopupShowing) return;
    
    // Find pending reviews: completed/expired, unreviewed, not cancelled, client only
    final pending = bookings.where((b) => 
        !b.isReviewed &&
        !b.reviewPromptDismissed &&
        b.status != BookingStatus.cancelled && 
        b.status != BookingStatus.cancelledLate &&
        b.escrowStatus != 'disputed' &&
        isBookingExpired(b)
    ).toList();
    
    if (pending.isEmpty) return;
    
    // Group by caregiverId and day
    final Map<String, List<Booking>> grouped = {};
    for (var b in pending) {
      final key = '${b.caregiverId}_${b.day}';
      if (!grouped.containsKey(key)) grouped[key] = [];
      grouped[key]!.add(b);
    }
    
    // Get all unexpired active bookings to check if they still have hours left today
    final unexpired = bookings.where((b) => 
        b.status != BookingStatus.cancelled && 
        b.status != BookingStatus.cancelledLate &&
        !isBookingExpired(b)
    ).toList();
    
    for (var entry in grouped.entries) {
      final group = entry.value;
      final first = group.first;
      
      // Check if there is an unexpired booking for this caregiver and day
      final hasUnexpired = unexpired.any((b) => b.caregiverId == first.caregiverId && b.day == first.day);
      
      if (!hasUnexpired) {
        final key = '${first.caregiverId}_${first.day}';
        if (_dismissedReviewGroups.contains(key)) continue;

        _isReviewPopupShowing = true;
        showDialog(
          context: context,
          barrierDismissible: true,
          builder: (ctx) => ReviewDialog(bookings: group),
        ).then((_) {
          _isReviewPopupShowing = false;
          _dismissedReviewGroups.add(key);
        });
        break; // Only show one popup at a time
      }
    }
  }

  bool isBookingExpired(Booking b) => b.isExpired;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthNotifier>();
    final bookingState = context.watch<BookingNotifier>();
    final isClient = auth.currentRole == 'client';
    final bookings = List<Booking>.from(bookingState.bookings);
    bookings.sort((a, b) => b.createdAt.compareTo(a.createdAt)); 
    bookings.sort((a, b) => a.day.compareTo(b.day) != 0 ? a.day.compareTo(b.day) : a.slot.compareTo(b.slot));
    
    final activeBookings = bookings.where((b) => 
      b.status != BookingStatus.cancelled && 
      b.status != BookingStatus.cancelledLate && 
      b.escrowStatus != 'released' && 
      b.escrowStatus != 'resolved_partial' &&
      !isBookingExpired(b) &&
      b.checkInTime == null
    ).toList();

    final historyBookings = bookings.where((b) => 
      b.status == BookingStatus.cancelled || 
      b.status == BookingStatus.cancelledLate || 
      b.escrowStatus == 'released' || 
      b.escrowStatus == 'resolved_partial' ||
      isBookingExpired(b) ||
      b.checkInTime != null
    ).toList();
    
    historyBookings.sort((a, b) => b.day.compareTo(a.day) != 0 ? b.day.compareTo(a.day) : b.slot.compareTo(a.slot));

    if (isClient) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _checkPendingReviews(bookings);
      });
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: Column(
          children: [
            Container(
              color: Colors.white,
              child: const TabBar(
                labelColor: AppTheme.primary,
                unselectedLabelColor: AppTheme.slateMuted,
                indicatorColor: AppTheme.primary,
                indicatorWeight: 3,
                labelStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                tabs: [
                  Tab(text: 'Reservas Activas'),
                  Tab(text: 'Historial'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildBookingsList(context, activeBookings, isClient, auth, bookingState, isActiveTab: true, controller: _scrollActive),
                  _buildBookingsList(context, historyBookings, isClient, auth, bookingState, isActiveTab: false, controller: _scrollHistory),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookingsList(BuildContext context, List<Booking> bookings, bool isClient, AuthNotifier auth, BookingNotifier state, {required bool isActiveTab, required ScrollController controller}) {
    return RefreshIndicator(
      onRefresh: state.refreshBookings,
      child: bookings.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.6,
                  child: const Center(child: Text('No hay reservas en esta sección')),
                )
              ],
            )
          : ListView.builder(
              controller: controller,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: bookings.length,
              itemBuilder: (context, index) {
                final b = bookings[index];
                
                final dateFormat = DateFormat('yyyy-MM-dd');
                DateTime? slotDateTime;
                try {
                  final dayDate = dateFormat.parse(b.day);
                  if (b.slot.contains('-')) {
                    final startStr = b.slot.split('-')[0];
                    final timeParts = startStr.split(':');
                    slotDateTime = DateTime(dayDate.year, dayDate.month, dayDate.day, int.parse(timeParts[0]), int.parse(timeParts[1]));
                  } else {
                    final timeParts = b.slot.split(':');
                    slotDateTime = DateTime(dayDate.year, dayDate.month, dayDate.day, int.parse(timeParts[0]), int.parse(timeParts[1]));
                  }
                } catch (e) {
                  // Ignore
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            isClient ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const CircleAvatar(
                                  child: Icon(Icons.person),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(b.caregiverName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                      const SizedBox(height: 4),
                                      Text('${_formatDay(b.day)} a las ${b.slot}', style: const TextStyle(color: Colors.grey)),
                                    ],
                                  ),
                                ),
                              ],
                            ) : FutureBuilder<ClientProfile?>(
                                future: _getClientProfile(b.clientId),
                                builder: (context, snapshot) {
                                  final isLoading = snapshot.connectionState == ConnectionState.waiting;
                                  final clientName = snapshot.data?.name ?? 'Desconocida';
                                  final nameParts = clientName.trim().split(RegExp(r'\s+'));
                                  final surname = nameParts.length > 1 ? nameParts[1] : clientName;
                                  
                                  String avatarText = '';
                                  if (nameParts.length > 1 && nameParts[1].isNotEmpty) {
                                    avatarText += nameParts[1][0].toUpperCase();
                                    if (nameParts.length > 2 && nameParts[2].isNotEmpty) {
                                      avatarText += nameParts[2][0].toUpperCase();
                                    }
                                  } else if (nameParts.isNotEmpty && nameParts[0].isNotEmpty) {
                                    avatarText = nameParts[0][0].toUpperCase();
                                  }

                                  return Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: Colors.blue.shade100,
                                        foregroundColor: Colors.blue.shade900,
                                        child: isLoading || avatarText.isEmpty
                                            ? const Icon(Icons.person, color: Colors.blue)
                                            : Text(avatarText, style: const TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Familia: ${isLoading ? "..." : surname}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                            const SizedBox(height: 4),
                                            Text('${_formatDay(b.day)} a las ${b.slot}', style: const TextStyle(color: Colors.grey)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                                },
                            ),
                            const SizedBox(height: 12),
                            InkWell(
                              onTap: () => _showStatusExplanation(context, b),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _getStatusColor(b.status).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: _getStatusColor(b.status).withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.info_outline, size: 14, color: _getStatusColor(b.status)),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        _getStatusText(b),
                                        style: TextStyle(color: _getStatusColor(b.status), fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(child: Text('Cuidados a domicilio')),
                            const SizedBox(width: 8),
                            Text('${b.totalPaid.toStringAsFixed(2)} €', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primary)),
                          ],
                        ),
                        
                        if (isActiveTab) ...[
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => ChatScreen(
                                    clientId: b.clientId, 
                                    caregiverId: b.caregiverId, 
                                    caregiverName: b.caregiverName
                                  )
                                ));
                              },
                              icon: const Icon(Icons.chat_bubble_outline),
                              label: const Text('Contactar por Chat'),
                            ),
                          ),
                          if (isClient && b.status == BookingStatus.confirmed) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.primarySurface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.verified_user_outlined, size: 18, color: AppTheme.primary),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Cuando el cuidador llegue a tu domicilio, enséñale el Código PIN de 4 números o el QR para registrar su entrada.',
                                      style: TextStyle(fontSize: 12.5, color: AppTheme.darkSlate, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: () {
                                      showDialog(context: context, builder: (_) => AlertDialog(
                                        title: const Text('Código QR de Entrada'),
                                          content: SizedBox(
                                            width: 220,
                                            height: 240,
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Text(
                                                  'El cuidador debe escanear este cuadro desde su móvil al llegar:',
                                                  style: TextStyle(fontSize: 13, color: AppTheme.slateMuted),
                                                  textAlign: TextAlign.center,
                                                ),
                                                const SizedBox(height: 12),
                                                Center(
                                                  child: QrImageView(
                                                    data: b.id,
                                                    version: QrVersions.auto,
                                                    size: 180.0,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))
                                        ],
                                      ));
                                    },
                                    icon: const Icon(Icons.qr_code, size: 18),
                                    label: const Text('Código QR'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: () {
                                      showDialog(context: context, builder: (_) => AlertDialog(
                                        title: const Text('Código PIN de Entrada'),
                                          content: SizedBox(
                                            width: 220,
                                            height: 130,
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                const Text(
                                                  'Dile estos 4 números al cuidador cuando llegue a casa:',
                                                  style: TextStyle(fontSize: 13, color: AppTheme.slateMuted),
                                                  textAlign: TextAlign.center,
                                                ),
                                                const SizedBox(height: 12),
                                                Text(
                                                  b.bookingPin ?? "Sin PIN", 
                                                  style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold, letterSpacing: 6, color: AppTheme.primary),
                                                ),
                                              ],
                                            ),
                                          ),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))
                                        ],
                                      ));
                                    },
                                    icon: const Icon(Icons.pin, size: 18),
                                    label: const Text('Código PIN'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppTheme.darkSlate,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          
                          if (isClient && (b.status == BookingStatus.pending || b.status == BookingStatus.confirmed) && b.checkInTime == null && !isBookingExpired(b))
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: SizedBox(
                                width: double.infinity,
                                child: TextButton(
                                  onPressed: () async {
                                    final now = DateTime.now();
                                    bool isLate = false;
                                    if (slotDateTime != null) {
                                      final diffHours = slotDateTime.difference(now).inHours;
                                      if (diffHours < 24) isLate = true;
                                    }
                                    
                                    bool? confirm = await CustomDialog.showConfirmation(
                                      context,
                                      title: 'Cancelar Reserva',
                                      message: isLate 
                                          ? 'Al cancelar con menos de 24h de antelación, se aplicará una penalización: se te reembolsará el 45% del importe y el resto cubrirá la compensación del cuidador y los gastos de gestión.'
                                          : '¿Estás seguro de que quieres cancelar esta reserva? Se te reembolsará el importe pagado descontando un 5% (mínimo 1.00€) en concepto de costes de pasarela y gestión.',
                                      cancelText: 'Mantener',
                                      confirmText: 'Cancelar Reserva',
                                      isDestructive: true,
                                    );

                                    if (confirm == true) {
                                      state.cancelBooking(b.id, 'Cancelado por el cliente', isLate);
                                      if (context.mounted) {
                                        CustomSnackBar.show(context, message: 'Reserva cancelada', type: SnackBarType.info);
                                      }
                                    }
                                  },
                                  child: const Text('Cancelar Reserva', style: TextStyle(color: Colors.red)),
                                ),
                              ),
                            ),
                          
                          if (!isClient && b.status == BookingStatus.pending)
                            Padding(
                              padding: const EdgeInsets.only(top: 16.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => state.rejectBooking(b.id),
                                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                                      child: const Text('Rechazar'),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: () => state.confirmBooking(b.id),
                                      child: const Text('Aceptar'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          
                          if (!isClient && b.status == BookingStatus.confirmed && b.checkInTime == null && !isBookingExpired(b))
                            Padding(
                              padding: const EdgeInsets.only(top: 16.0),
                              child: SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: () {
                                    Navigator.push(context, MaterialPageRoute(
                                      builder: (_) => ScannerScreen(booking: b)
                                    ));
                                  },
                                  icon: const Icon(Icons.qr_code_scanner),
                                  label: const Text('Fichar Llegada'),
                                ),
                              ),
                            ),
                        ],
                        
                        if (!isActiveTab) ...[
                            if ((b.status == BookingStatus.completed || (b.status == BookingStatus.confirmed && b.checkInTime != null && isBookingExpired(b))) && isClient && !b.isReviewed)
                            Padding(
                              padding: const EdgeInsets.only(top: 16.0),
                              child: SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: () {
                                    final group = bookings.where((bk) => bk.caregiverId == b.caregiverId && bk.day == b.day && !bk.isReviewed && bk.status != BookingStatus.cancelled && bk.status != BookingStatus.cancelledLate).toList();
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => ReviewDialog(bookings: group.isNotEmpty ? group : [b])
                                    );
                                  },
                                  icon: const Icon(Icons.star),
                                  label: const Text('Dejar una Reseña'),
                                ),
                              ),
                            ),
                          
                          if (b.escrowStatus == 'disputed' && !isClient && b.disputeEscalated != true)
                            Padding(
                              padding: const EdgeInsets.only(top: 16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                                    child: Text(
                                      'El cliente ha abierto una disputa proponiendo un reembolso de ${b.disputeAmount?.toStringAsFixed(2) ?? "0.00"} €.\nTu pago restante será de ${(b.cost - (b.disputeAmount ?? 0)).toStringAsFixed(2)} € (menos comisiones).',
                                      style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: () async {
                                            bool? confirm = await CustomDialog.showConfirmation(
                                              context,
                                              title: 'Rechazar Propuesta',
                                              message: 'Si rechazas, el caso se escalará al equipo de Administración y ellos decidirán el resultado final. ¿Continuar?',
                                              confirmText: 'Escalar',
                                              isDestructive: true,
                                            );
                                            if (confirm == true) {
                                              await state.escalateDispute(b.id);
                                              if (context.mounted) CustomSnackBar.show(context, message: 'Disputa escalada', type: SnackBarType.info);
                                            }
                                          },
                                          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                                          child: const Text('Rechazar (Escalar)'),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: FilledButton(
                                          onPressed: () async {
                                            bool? confirm = await CustomDialog.showConfirmation(
                                              context,
                                              title: 'Aceptar Propuesta',
                                              message: 'Al aceptar, se aplicarán los pagos acordados y la reserva quedará resuelta definitivamente. ¿Continuar?',
                                              confirmText: 'Aceptar',
                                            );
                                            if (confirm == true) {
                                              try {
                                                await state.acceptDisputeProposal(b.id);
                                                if (context.mounted) CustomSnackBar.show(context, message: 'Propuesta aceptada, pago en proceso.', type: SnackBarType.success);
                                              } catch (e) {
                                                if (context.mounted) CustomSnackBar.show(context, message: 'Error al procesar acuerdo: $e', type: SnackBarType.error);
                                              }
                                            }
                                          },
                                          style: FilledButton.styleFrom(backgroundColor: Colors.green),
                                          child: const Text('Aceptar Propuesta'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            
                          if (b.escrowStatus == 'disputed' && isClient && b.disputeEscalated != true)
                            Padding(
                              padding: const EdgeInsets.only(top: 16.0),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                width: double.infinity,
                                decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                                child: Text(
                                  'Has propuesto un reembolso de ${b.disputeAmount?.toStringAsFixed(2) ?? "0.00"} €.\nEsperando la respuesta del cuidador (máx 24h).',
                                  style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.w600),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                            
                          if (b.escrowStatus == 'disputed' && b.disputeEscalated == true)
                            Padding(
                              padding: const EdgeInsets.only(top: 16.0),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                width: double.infinity,
                                decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                                child: const Text(
                                  'Disputa escalada al equipo de Administración. Te contactaremos pronto.',
                                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                        ]
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _showStatusExplanation(BuildContext context, Booking b) {
    final statusText = _getStatusText(b);
    String explanation = '';
    
    switch (statusText) {
      case 'Completado (Pagado)':
        explanation = 'El servicio se ha realizado correctamente y el pago ha sido liberado al cuidador (se completaron las 24h tras el fin del servicio o se resolvió de mutuo acuerdo).';
        break;
      case 'Cancelado (Reembolsado)':
        explanation = 'El servicio fue cancelado o hubo una incidencia mayor (como un No-Show) y se ha devuelto el importe correspondiente al cliente.';
        break;
      case 'Cancelado (Parcial)':
        explanation = 'La reserva fue cancelada fuera de plazo o hubo una resolución de disputa que implicó un reembolso o pago parcial.';
        break;
      case 'Realizada (En espera)':
        explanation = 'El cuidador ha finalizado el servicio, pero el dinero se mantiene retenido de forma segura (Escrow) durante 24 horas por si surge alguna incidencia.';
        break;
      case 'Caducada / No-Show':
        explanation = 'La hora del servicio ha pasado y el cuidador no llegó a fichar la entrada mediante el código QR o PIN. Se procesará la cancelación automáticamente.';
        break;
      case 'Procesando pago...':
        explanation = 'Se está validando la retención de la tarjeta del cliente a través de la pasarela de pago segura.';
        break;
      case 'Pendiente':
        explanation = 'El pago está asegurado pero el cuidador todavía tiene que aceptar la solicitud de servicio para confirmarla.';
        break;
      case 'Confirmada':
        explanation = 'El cuidador ha aceptado el servicio. Ahora solo queda esperar al día y hora acordados para realizar el fichaje presencial (Check-in).';
        break;
      case 'Cancelada':
        explanation = 'El servicio ha sido cancelado antes de tiempo sin penalización.';
        break;
      case 'Cancelada (Tarde)':
        explanation = 'El servicio ha sido cancelado fuera de plazo (con menos de 24h de antelación), lo cual acarrea una penalización.';
        break;
      case 'Completada':
        explanation = 'El servicio ha terminado y todo el flujo de pagos ha concluido correctamente.';
        break;
      default:
        explanation = 'Este es el estado actual de la reserva.';
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.info_outline, color: AppTheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(statusText, style: const TextStyle(fontSize: 18))),
          ],
        ),
        content: Text(explanation),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido')),
        ],
      ),
    );
  }

  String _getStatusText(Booking b) {
    if (b.escrowStatus == 'released' || b.escrowStatus == 'released_manual' || b.escrowStatus == 'released_auto') return 'Completado (Pagado)';
    if (b.escrowStatus == 'refunded') return 'Cancelado (Reembolsado)';
    if (b.escrowStatus == 'resolved_partial') return 'Cancelado (Parcial)';
    
    if (b.checkInTime != null && b.status == BookingStatus.confirmed) return 'Realizada (En espera)';
    if (isBookingExpired(b) && b.checkInTime == null && b.status == BookingStatus.confirmed) return 'Caducada / No-Show';

    switch (b.status) {
      case BookingStatus.pendingPayment: return 'Procesando pago...';
      case BookingStatus.pending: return 'Pendiente';
      case BookingStatus.confirmed: return 'Confirmada';
      case BookingStatus.cancelled: return 'Cancelada';
      case BookingStatus.cancelledLate: return 'Cancelada (Tarde)';
      case BookingStatus.completed: return 'Completada';
    }
  }

  Color _getStatusColor(BookingStatus status) {
    switch (status) {
      case BookingStatus.pendingPayment: return Colors.orange;
      case BookingStatus.pending: return Colors.orange;
      case BookingStatus.confirmed: return Colors.green;
      case BookingStatus.cancelled: return Colors.red;
      case BookingStatus.cancelledLate: return Colors.red;
      case BookingStatus.completed: return Colors.blue;
    }
  }
}

