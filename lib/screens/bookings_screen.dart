import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
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
        (b.status == BookingStatus.completed || b.liveStatus == 'completed' || isBookingExpired(b))
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
      b.status != BookingStatus.completed &&
      b.escrowStatus != 'released' && 
      b.escrowStatus != 'resolved_partial' &&
      !isBookingExpired(b)
    ).toList();

    final historyBookings = bookings.where((b) => 
      b.status == BookingStatus.cancelled || 
      b.status == BookingStatus.cancelledLate || 
      b.status == BookingStatus.completed ||
      b.escrowStatus == 'released' || 
      b.escrowStatus == 'resolved_partial' ||
      isBookingExpired(b)
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
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
              ),
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
                Container(
                  height: MediaQuery.of(context).size.height * 0.58,
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: AppTheme.primarySurface,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isActiveTab ? Icons.favorite_border_rounded : Icons.history_edu_rounded,
                          size: 52,
                          color: AppTheme.primary,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        isActiveTab
                            ? 'Aún no tienes cuidados activos'
                            : 'Tu historial de cuidados está vacío',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.darkSlate,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isActiveTab
                            ? (isClient
                                ? 'Reserva un cuidador verificado o publica una oferta personalizada para tu familiar.'
                                : 'Revisa el tablón de ofertas cercanas o mantén tu calendario actualizado para recibir solicitudes.')
                            : 'Aquí aparecerán todas las visitas finalizadas con su Diario del Cuidado y valoraciones.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: AppTheme.slateMuted,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
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
                        if (b.tipAmount > 0) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.amber.shade300),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('☕', style: TextStyle(fontSize: 14)),
                                const SizedBox(width: 6),
                                Text(
                                  'Propina de agradecimiento: +${b.tipAmount.toStringAsFixed(0)} € (100% íntegra)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (!isClient && isActiveTab && b.status == BookingStatus.confirmed)
                          FutureBuilder<ClientProfile?>(
                            future: _getClientProfile(b.clientId),
                            builder: (context, snap) {
                              final profile = snap.data;
                              if (profile == null || (profile.patientDetails.isEmpty && profile.homeAddress.isEmpty)) {
                                return const SizedBox.shrink();
                              }
                              return Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(top: 12),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.amber.shade300),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.medical_information_rounded, size: 17, color: Colors.amber.shade900),
                                        const SizedBox(width: 6),
                                        Text(
                                          '🩺 Ficha Rápida del Paciente',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.amber.shade900,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (profile.homeAddress.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        '📍 Domicilio: ${profile.homeAddress}',
                                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.darkSlate),
                                      ),
                                    ],
                                    if (profile.patientDetails.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        '📋 Indicaciones: ${profile.patientDetails}',
                                        style: const TextStyle(fontSize: 12.5, color: AppTheme.darkSlate),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),

                        if (b.status == BookingStatus.confirmed || b.status == BookingStatus.completed) ...[
                          const SizedBox(height: 14),
                          _buildLiveStatusStepper(b),
                          const SizedBox(height: 14),
                          _buildCareJournalSection(context, b, isClient, state, isActiveTab: isActiveTab),
                        ],

                        // Disputa activa (si existe)
                        if (b.escrowStatus == 'disputed') ...[
                          const SizedBox(height: 12),
                          _buildDisputeBanner(context, b, isClient, state),
                        ],

                        // Aviso de Incomparecencia / No-Show si transcurrió sin check-in
                        if (isClient && isBookingExpired(b) && b.checkInTime == null && b.escrowStatus != 'refunded') ...[
                          const SizedBox(height: 12),
                          _buildNoShowBanner(context, b),
                        ],

                        // Botón de Acción Principal (Contextual, Grande y Tranquilizador)
                        Builder(
                          builder: (context) {
                            final primaryBtn = _buildPrimaryActionButton(context, b, isClient, state, bookings);
                            if (primaryBtn == null) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: 14.0),
                              child: primaryBtn,
                            );
                          },
                        ),

                        // Fila Secundaria Siempre Limpia: Chat + Más opciones
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
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
                                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                                label: Text(
                                  isClient
                                      ? 'Chat con ${b.caregiverName.split(" ").first}'
                                      : 'Chat con Familia',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: () => _showBookingMoreOptionsModal(context, b, isClient, state),
                              style: IconButton.styleFrom(
                                backgroundColor: AppTheme.backgroundNeutral,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: const BorderSide(color: AppTheme.borderSubtle),
                                ),
                                padding: const EdgeInsets.all(12),
                              ),
                              tooltip: 'Más opciones de la reserva',
                              icon: const Icon(Icons.more_horiz_rounded, color: AppTheme.darkSlate),
                            ),
                          ],
                        ),
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
        explanation = 'El servicio se ha realizado correctamente y el pago ha sido liberado al cuidador (se completaron las 24h tras el fin del servicio o se liberó manualmente).';
        break;
      case 'Cancelado (Reembolsado)':
        explanation = 'El servicio fue cancelado o hubo una incidencia mayor (como un No-Show) y se ha devuelto el importe íntegro al cliente.';
        break;
      case 'Cancelado (Reembolso parcial)':
        explanation = 'La reserva fue cancelada fuera de plazo (con penalización) y se reembolsó la parte correspondiente al cliente.';
        break;
      case 'Acuerdo Resuelto (Pago ajustado)':
        explanation = 'Ambas partes alcanzaron un acuerdo satisfactorio para resolver la incidencia y los pagos se han ajustado según lo pactado.';
        break;
      case 'Disputa Abierta':
        explanation = 'Hay una incidencia en curso entre la familia y el cuidador. Los fondos permanecen en custodia hasta que se alcance un acuerdo o transcurran 24h.';
        break;
      case 'Disputa en Mediación':
        explanation = 'La incidencia ha sido escalada al equipo de Administración y Mediación de Senicare para su arbitraje definitivo.';
        break;
      case '✅ Visita Finalizada (Custodia 24h)':
        explanation = 'El cuidador ha finalizado el servicio y registrado su salida. El dinero se mantiene en custodia protegida durante 24 horas por si surge alguna duda o puedes liberarlo de inmediato.';
        break;
      case '✅ Visita Realizada (Custodia 24h)':
        explanation = 'El servicio ha finalizado según el horario previsto y el dinero se mantiene en custodia durante el periodo de garantía de 24 horas.';
        break;
      case '🟢 En domicilio (Cuidado en curso)':
        explanation = 'El cuidador ha registrado su llegada presencial (Check-in con QR/PIN) y se encuentra atendiendo al familiar en el domicilio.';
        break;
      case '🚗 Cuidador en camino':
        explanation = 'El cuidador ha avisado de que se encuentra desplazándose hacia el domicilio para iniciar el servicio.';
        break;
      case 'Caducada / No-Show':
        explanation = 'La hora del servicio ha pasado y el cuidador no llegó a fichar la entrada mediante el código QR o PIN. Se procesará la cancelación automáticamente.';
        break;
      case 'Procesando pago...':
        explanation = 'Se está validando la retención de la tarjeta del cliente a través de la pasarela de pago segura.';
        break;
      case 'Pendiente':
      case 'Pendiente de aceptación':
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
    if (b.escrowStatus == 'resolved_partial') {
      return b.status == BookingStatus.completed ? 'Acuerdo Resuelto (Pago ajustado)' : 'Cancelado (Reembolso parcial)';
    }
    if (b.escrowStatus == 'disputed') {
      return b.disputeEscalated == true ? 'Disputa en Mediación' : 'Disputa Abierta';
    }
    
    if (b.liveStatus == 'completed' || b.status == BookingStatus.completed) return '✅ Visita Finalizada (Custodia 24h)';
    if (b.checkInTime != null && !isBookingExpired(b) && b.status == BookingStatus.confirmed) return '🟢 En domicilio (Cuidado en curso)';
    if (b.checkInTime != null && b.status == BookingStatus.confirmed) return '✅ Visita Realizada (Custodia 24h)';
    if (b.liveStatus == 'on_the_way' && b.checkInTime == null && !isBookingExpired(b) && b.status == BookingStatus.confirmed) return '🚗 Cuidador en camino';
    if (isBookingExpired(b) && b.checkInTime == null && b.status == BookingStatus.confirmed) return 'Caducada / No-Show';

    switch (b.status) {
      case BookingStatus.pendingPayment: return 'Procesando pago...';
      case BookingStatus.pending: return 'Pendiente de aceptación';
      case BookingStatus.confirmed: return 'Confirmada';
      case BookingStatus.cancelled: return 'Cancelada';
      case BookingStatus.cancelledLate: return 'Cancelada (Tarde)';
      case BookingStatus.completed: return 'Completada';
    }
  }

  Color _getStatusColor(BookingStatus status) {
    switch (status) {
      case BookingStatus.pendingPayment: return Colors.orange;
      case BookingStatus.pending: return Colors.amber.shade800;
      case BookingStatus.confirmed: return Colors.green;
      case BookingStatus.cancelled: return Colors.red;
      case BookingStatus.cancelledLate: return Colors.red.shade800;
      case BookingStatus.completed: return Colors.blue;
    }
  }

  Widget _buildLiveStatusStepper(Booking b) {
    final bool step1 = true;
    final bool step2 = b.liveStatus == 'on_the_way' ||
        b.checkInTime != null ||
        b.status == BookingStatus.completed;
    final bool step3 = b.checkInTime != null ||
        b.liveStatus == 'in_progress' ||
        b.status == BookingStatus.completed;
    final bool step4 = b.status == BookingStatus.completed ||
        (b.checkInTime != null && isBookingExpired(b)) ||
        b.liveStatus == 'completed' ||
        b.escrowStatus == 'released' ||
        b.escrowStatus == 'released_manual' ||
        b.escrowStatus == 'released_auto';

    final steps = [
      {'label': 'Confirmada', 'done': step1, 'icon': Icons.event_available_rounded},
      {'label': 'En camino', 'done': step2, 'icon': Icons.directions_car_rounded},
      {'label': 'En domicilio', 'done': step3, 'icon': Icons.home_rounded},
      {'label': 'Finalizada', 'done': step4, 'icon': Icons.verified_rounded},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.backgroundNeutral,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Row(
        children: List.generate(steps.length * 2 - 1, (idx) {
          if (idx.isOdd) {
            final nextDone = steps[(idx + 1) ~/ 2]['done'] as bool;
            return Expanded(
              child: Container(
                height: 3,
                color: nextDone ? AppTheme.secondaryColor : Colors.grey.shade300,
              ),
            );
          }
          final step = steps[idx ~/ 2];
          final done = step['done'] as bool;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: done ? AppTheme.secondaryColor : Colors.grey.shade300,
                child: Icon(
                  step['icon'] as IconData,
                  size: 14,
                  color: done ? Colors.white : Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                step['label'] as String,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: done ? FontWeight.w800 : FontWeight.w500,
                  color: done ? AppTheme.darkSlate : Colors.grey.shade500,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildCareJournalSection(
    BuildContext context,
    Booking b,
    bool isClient,
    BookingNotifier state, {
    required bool isActiveTab,
  }) {
    final completedCount = b.careChecklist.where((t) => t.completed).length;
    final totalCount = b.careChecklist.length;

    const quickFamilySuggestions = [
      '💊 Dar medicación pautada',
      '🍲 Preparar comida y supervisar hidratación',
      '🚶 Paseo tranquilo de 30-40 min',
      '🧠 Conversación y estimulación cognitiva',
      '🚿 Apoyo en aseo e higiene personal',
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.primarySurface.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: const Icon(Icons.assignment_turned_in_rounded, color: AppTheme.primary, size: 22),
          title: const Text(
            'Diario y Pautas del Cuidado',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
              color: AppTheme.darkSlate,
            ),
          ),
          subtitle: Text(
            totalCount > 0
                ? '$completedCount de $totalCount tareas completadas'
                : (isClient ? 'Toca para ver o añadir tareas' : 'Sin tareas asignadas aún'),
            style: const TextStyle(fontSize: 12, color: AppTheme.slateMuted),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (b.carePhotoUrls.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: Text(
                    '📸 ${b.carePhotoUrls.length}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.darkSlate),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              const Icon(Icons.expand_more_rounded, size: 20, color: AppTheme.slateMuted),
            ],
          ),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(height: 12),
                Text(
                  isClient
                      ? 'Personaliza las tareas que necesita tu familiar. El cuidador las irá marcando en tiempo real.'
                      : 'Toca cada tarea creada por la familia cuando la completes para registrar la hora exacta.',
                  style: const TextStyle(fontSize: 12, color: AppTheme.slateMuted),
                ),
          if (b.onTheWayAt != null || b.checkInTime != null || completedCount > 0 || b.careNotes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.timeline_rounded, size: 16, color: AppTheme.secondaryColor),
                      SizedBox(width: 6),
                      Text(
                        '🕒 Cronología en Tiempo Real (Modo Tranquilidad)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.secondaryColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (b.onTheWayAt != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        '🚗 ${b.onTheWayAt!.hour.toString().padLeft(2, '0')}:${b.onTheWayAt!.minute.toString().padLeft(2, '0')} — Salida hacia el domicilio',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.darkSlate),
                      ),
                    ),
                  if (b.checkInTime != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        '📍 ${b.checkInTime!.hour.toString().padLeft(2, '0')}:${b.checkInTime!.minute.toString().padLeft(2, '0')} — Entrada verificada en casa (GPS / PIN)',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.secondaryColor),
                      ),
                    ),
                  ...b.careChecklist.where((t) => t.completed).map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        '✓ ${t.completedAt ?? 'Hecho'} — ${t.title}',
                        style: const TextStyle(fontSize: 12, color: AppTheme.darkSlate),
                      ),
                    ),
                  ),
                  if (b.careNotes.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '📝 Parte registrado: "${b.careNotes}"',
                        style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AppTheme.slateMuted),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (b.careChecklist.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                isClient
                    ? 'Aún no has añadido tareas para esta visita. Usa los botones rápidos de abajo o escribe una tarea a medida.'
                    : 'La familia aún no ha indicado tareas específicas en la checklist de esta visita.',
                style: TextStyle(
                  fontSize: 12.5,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey.shade600,
                ),
              ),
            )
          else
            ...b.careChecklist.map((item) {
              final timeFormatted = item.completedAt;
              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: (!isClient && isActiveTab)
                    ? () {
                        HapticFeedback.mediumImpact();
                        state.toggleChecklistTask(b.id, item.id);
                      }
                    : null,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: item.completed
                          ? AppTheme.secondaryColor.withValues(alpha: 0.45)
                          : Colors.grey.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        item.completed
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: item.completed ? AppTheme.secondaryColor : Colors.grey.shade400,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item.title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            decoration: item.completed ? TextDecoration.lineThrough : null,
                            color: item.completed ? Colors.grey.shade600 : AppTheme.darkSlate,
                          ),
                        ),
                      ),
                      if (timeFormatted != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.secondaryColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '✓ $timeFormatted',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.secondaryColor,
                            ),
                          ),
                        ),
                      if (isClient && isActiveTab && !item.completed)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.close_rounded, size: 17, color: Colors.grey),
                          tooltip: 'Quitar tarea',
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            state.removeChecklistTask(b.id, item.id);
                          },
                        ),
                    ],
                  ),
                ),
              );
            }),
          if (isClient && isActiveTab) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.add_rounded, size: 16, color: Colors.white),
                    backgroundColor: AppTheme.primary,
                    label: const Text(
                      'Escribir tarea a medida',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () => _showAddTaskDialog(context, b, state),
                  ),
                  const SizedBox(width: 6),
                  ...quickFamilySuggestions
                      .where((s) => !b.careChecklist.any((t) => t.title == s))
                      .map((suggestion) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ActionChip(
                              backgroundColor: Colors.white,
                              label: Text(suggestion, style: const TextStyle(fontSize: 11.5)),
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                state.addChecklistTask(b.id, suggestion);
                              },
                            ),
                          )),
                ],
              ),
            ),
          ],
          if (b.careNotes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '📝 Parte del cuidador:',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppTheme.primary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    b.careNotes,
                    style: const TextStyle(fontSize: 13, color: AppTheme.darkSlate),
                  ),
                ],
              ),
            ),
          ],
          if (b.carePhotoUrls.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.photo_camera_rounded, size: 16, color: AppTheme.primary),
                const SizedBox(width: 6),
                Text(
                  isClient
                      ? '📸 Fotos del cuidado (compartidas por ${b.caregiverName}):'
                      : '📸 Fotos compartidas con la familia (${b.carePhotoUrls.length}):',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppTheme.darkSlate),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 75,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: b.carePhotoUrls.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) => InkWell(
                  onTap: () => _showPhotoFullScreen(context, b.carePhotoUrls[i], b.caregiverName),
                  borderRadius: BorderRadius.circular(10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      children: [
                        Image.network(
                          b.carePhotoUrls[i],
                          width: 75,
                          height: 75,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 75,
                            height: 75,
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.photo_camera_back_rounded),
                          ),
                        ),
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.zoom_in_rounded, size: 14, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (!isClient && isActiveTab) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showEditCareNotesDialog(context, b, state),
                    icon: const Icon(Icons.edit_note_rounded, size: 18),
                    label: Text(
                      b.careNotes.isEmpty ? 'Añadir nota del día' : 'Editar nota',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _uploadCarePhoto(context, b, state),
                    icon: const Icon(Icons.add_a_photo_rounded, size: 16),
                    label: const Text('Foto cuidado', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    ],
    ),
    ),
    );
  }

  Widget? _buildPrimaryActionButton(
    BuildContext context,
    Booking b,
    bool isClient,
    BookingNotifier state,
    List<Booking> bookings,
  ) {
    if (isClient) {
      if (b.status == BookingStatus.confirmed && b.checkInTime == null && !isBookingExpired(b)) {
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => _showAccessCodeAndFridgeSheetModal(context, b),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.key_rounded, size: 20),
            label: Text(
              '🔑 Código de Entrada: ${b.bookingPin ?? "Ver PIN"}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.5),
            ),
          ),
        );
      }
      if (b.status == BookingStatus.confirmed && b.checkInTime != null && b.liveStatus != 'completed') {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          decoration: BoxDecoration(
            color: AppTheme.secondaryColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.3)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.home_rounded, color: AppTheme.secondaryColor, size: 20),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  '🟢 Cuidador en casa · Cuidado en curso',
                  style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.secondaryColor, fontSize: 13.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }
      if ((b.status == BookingStatus.completed ||
              (b.status == BookingStatus.confirmed && b.checkInTime != null && isBookingExpired(b))) &&
          !b.isReviewed) {
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () {
              final group = bookings
                  .where((bk) =>
                      bk.caregiverId == b.caregiverId &&
                      bk.day == b.day &&
                      !bk.isReviewed &&
                      bk.status != BookingStatus.cancelled &&
                      bk.status != BookingStatus.cancelledLate)
                  .toList();
              showDialog(
                context: context,
                builder: (ctx) => ReviewDialog(bookings: group.isNotEmpty ? group : [b]),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.amber,
              foregroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.star_rounded, size: 20),
            label: Text('⭐ Valorar a ${b.caregiverName}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          ),
        );
      }
      if (b.status == BookingStatus.pendingPayment) {
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () async {
              final confirm = await CustomDialog.showConfirmation(
                context,
                title: 'Descartar Intento',
                message: '¿Deseas descartar este intento de reserva no pagado?',
                confirmText: 'Descartar',
                isDestructive: true,
              );
              if (confirm == true) {
                state.cancelBooking(b.id, 'Intento descartado por el cliente', false);
              }
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.deepOrange.shade800,
              side: BorderSide(color: Colors.deepOrange.shade300),
              padding: const EdgeInsets.symmetric(vertical: 11),
            ),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Descartar intento no pagado'),
          ),
        );
      }
      if (b.status == BookingStatus.pending) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.hourglass_top_rounded, color: Colors.amber.shade800, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Esperando confirmación de ${b.caregiverName}',
                  style: TextStyle(fontWeight: FontWeight.w700, color: Colors.amber.shade900, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }
      return null;
    }

    // Acciones para el cuidador
    if (b.status == BookingStatus.pending) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () async {
                final confirm = await CustomDialog.showConfirmation(
                  context,
                  title: 'Rechazar Solicitud',
                  message: '¿Seguro que no puedes atender este servicio? La reserva se cancelará y los fondos se liberarán para la familia.',
                  confirmText: 'Rechazar',
                  isDestructive: true,
                );
                if (confirm == true) {
                  await state.rejectBooking(b.id);
                  if (context.mounted) {
                    CustomSnackBar.show(context, message: 'Solicitud rechazada.', type: SnackBarType.info);
                  }
                }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text('Rechazar'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: () async {
                HapticFeedback.mediumImpact();
                await state.confirmBooking(b.id);
                if (context.mounted) {
                  CustomSnackBar.show(context, message: '✅ ¡Servicio aceptado! Recuerda registrar tu llegada.', type: SnackBarType.success);
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text('Aceptar', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      );
    }
    if (b.status == BookingStatus.confirmed && b.checkInTime == null && !isBookingExpired(b)) {
      return Column(
        children: [
          if (b.liveStatus != 'on_the_way') ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  HapticFeedback.mediumImpact();
                  await state.markOnTheWay(b.id);
                  if (context.mounted) {
                    CustomSnackBar.show(
                      context,
                      message: '🚗 Familia avisada de que estás en camino al domicilio.',
                      type: SnackBarType.success,
                    );
                  }
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange.shade800,
                  side: BorderSide(color: Colors.orange.shade400, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
                icon: const Icon(Icons.directions_car_rounded, size: 18),
                label: const Text('🚗 Avisar a familia: Estoy en camino'),
              ),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ScannerScreen(booking: b),
                ));
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.qr_code_scanner, size: 18),
              label: const Text('Fichar Llegada (QR o PIN)', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      );
    }
    if (b.status == BookingStatus.confirmed && b.checkInTime != null && b.liveStatus != 'completed') {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: () async {
            final confirm = await CustomDialog.showConfirmation(
              context,
              title: 'Finalizar Servicio',
              message: '¿Confirmas que has terminado el turno y vas a salir del domicilio? Se registrará la salida y la familia recibirá el aviso.',
              confirmText: 'Finalizar y Salir',
              cancelText: 'Continuar turno',
            );
            if (confirm == true && context.mounted) {
              HapticFeedback.heavyImpact();
              await state.completeService(b.id);
              if (context.mounted) {
                CustomSnackBar.show(context, message: '🎉 ¡Servicio finalizado con éxito! Buen descanso.', type: SnackBarType.success);
              }
            }
          },
          style: FilledButton.styleFrom(
            backgroundColor: Colors.green.shade700,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
          label: const Text('🏁 Finalizar Servicio y Salir', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      );
    }
    return null;
  }

  Widget _buildDisputeBanner(BuildContext context, Booking b, bool isClient, BookingNotifier state) {
    if (!isClient && b.disputeEscalated != true) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'El cliente ha propuesto un reembolso de ${b.disputeAmount?.toStringAsFixed(2) ?? "0.00"} €.\nTu pago restante será de ${(b.cost - (b.disputeAmount ?? 0)).toStringAsFixed(2)} €.',
              style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.w600, fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      bool? confirm = await CustomDialog.showConfirmation(
                        context,
                        title: 'Rechazar Propuesta',
                        message: 'Si rechazas, el caso se escalará al equipo de Administración para su arbitraje. ¿Continuar?',
                        confirmText: 'Escalar',
                        isDestructive: true,
                      );
                      if (confirm == true) {
                        await state.escalateDispute(b.id);
                        if (context.mounted) CustomSnackBar.show(context, message: 'Disputa escalada a Administración.', type: SnackBarType.info);
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
                          if (context.mounted) CustomSnackBar.show(context, message: 'Error: $e', type: SnackBarType.error);
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
      );
    }

    if (isClient && b.disputeEscalated != true) {
      return Container(
        padding: const EdgeInsets.all(12),
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade300),
        ),
        child: Text(
          'Has propuesto un reembolso de ${b.disputeAmount?.toStringAsFixed(2) ?? "0.00"} €.\nEsperando respuesta del cuidador (máx 24h).',
          style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.w600, fontSize: 12.5),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade300),
      ),
      child: const Text(
        'Disputa escalada al equipo de Administración. Te contactaremos pronto.',
        style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600, fontSize: 12.5),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildNoShowBanner(BuildContext context, Booking b) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_off_outlined, size: 18, color: Colors.red.shade800),
              const SizedBox(width: 6),
              Text(
                'Incomparecencia / Sin Check-in',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red.shade900),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'El cuidador no registró su llegada presencial. Tu importe (${b.totalPaid.toStringAsFixed(2)} €) está asegurado y el reembolso total se tramita automáticamente.',
            style: TextStyle(fontSize: 12, color: Colors.red.shade900, height: 1.3),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _findUrgentSubstitute(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade900,
                side: BorderSide(color: Colors.red.shade300),
              ),
              icon: const Icon(Icons.flash_on_rounded, size: 16),
              label: const Text('🚨 Buscar un cuidador de sustitución hoy', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  void _showAccessCodeAndFridgeSheetModal(BuildContext context, Booking b) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '🔑 Acceso al Domicilio',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.darkSlate),
              ),
              const SizedBox(height: 6),
              Text(
                'Enséñale estos datos a ${b.caregiverName} cuando llegue a casa para validar su entrada:',
                style: const TextStyle(fontSize: 13, color: AppTheme.slateMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                decoration: BoxDecoration(
                  color: AppTheme.primarySurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    const Text(
                      'CÓDIGO PIN DE ENTRADA',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.primary, letterSpacing: 1),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      b.bookingPin ?? "----",
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 10,
                        color: AppTheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Díctale estos 4 números en persona al llegar',
                      style: TextStyle(fontSize: 12, color: AppTheme.darkSlate),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: QrImageView(
                    data: b.id,
                    version: QrVersions.auto,
                    size: 145.0,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'O también puede escanear este código QR con su móvil',
                style: TextStyle(fontSize: 11.5, color: AppTheme.slateMuted),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showFridgeSheetModal(context, b);
                  },
                  icon: const Icon(Icons.kitchen_rounded, size: 18, color: AppTheme.primary),
                  label: const Text(
                    '📄 Ver Ficha para la Nevera / Enviar WhatsApp',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primary),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.primary, width: 1.2),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBookingMoreOptionsModal(
    BuildContext context,
    Booking b,
    bool isClient,
    BookingNotifier state,
  ) {
    HapticFeedback.mediumImpact();
    final bool canCancel = isClient &&
        (b.status == BookingStatus.pending || b.status == BookingStatus.confirmed) &&
        b.checkInTime == null &&
        !isBookingExpired(b);

    final bool canDiscard = isClient && b.status == BookingStatus.pendingPayment;
    final bool canTip = isClient && b.tipAmount == 0 && (b.status == BookingStatus.completed || b.isReviewed);
    final bool canRepeat = isClient && b.status != BookingStatus.cancelled && b.status != BookingStatus.cancelledLate;
    final bool canEscrowRelease = isClient && b.escrowStatus == 'held' && b.checkInTime != null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.tune_rounded, color: AppTheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Opciones del servicio',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.darkSlate),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 18),
              if (b.status == BookingStatus.confirmed)
                ListTile(
                  leading: const Icon(Icons.event_available_rounded, color: AppTheme.primary),
                  title: const Text('Añadir a Google Calendar / Agenda', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: const Text('Guarda un recordatorio en tu calendario personal'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _addToGoogleCalendar(context, b, isClient);
                  },
                ),
              if (isClient && b.status == BookingStatus.confirmed) ...[
                ListTile(
                  leading: const Icon(Icons.share_rounded, color: AppTheme.primary),
                  title: const Text('Compartir enlace familiar', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: const Text('Envía el seguimiento del turno a otros familiares'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _shareLiveTrackingWithFamily(context, b);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.kitchen_rounded, color: AppTheme.primary),
                  title: const Text('Ficha para la Nevera', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: const Text('Resumen con teléfonos y PIN para imprimir o WhatsApp'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showFridgeSheetModal(context, b);
                  },
                ),
              ],
              if (canRepeat)
                ListTile(
                  leading: const Icon(Icons.repeat_rounded, color: AppTheme.primary),
                  title: const Text('Repetir servicio la próxima semana', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: const Text('Reserva el mismo horario con el mismo cuidador'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _repeatBookingNextWeek(context, b);
                  },
                ),
              if (isClient && b.status != BookingStatus.cancelled && b.status != BookingStatus.cancelledLate)
                ListTile(
                  leading: const Icon(Icons.receipt_long_rounded, color: AppTheme.darkSlate),
                  title: const Text('Descargar Justificante Legal', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: const Text('Documento oficial con seguro RC y horas prestadas'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showLegalReceiptDialog(context, b);
                  },
                ),
              if (canTip)
                ListTile(
                  leading: const Text('☕', style: TextStyle(fontSize: 20)),
                  title: const Text('Enviar propina de agradecimiento', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppTheme.secondaryColor)),
                  subtitle: const Text('100% íntegra para el cuidador sin comisiones'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showQuickTipDialog(context, b, state);
                  },
                ),
              if (canEscrowRelease) ...[
                ListTile(
                  leading: const Icon(Icons.check_circle_outline_rounded, color: Colors.green),
                  title: const Text('Liberar Pago al Cuidador Ahora', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.green)),
                  subtitle: const Text('Confirmar satisfacción para no esperar las 24h de custodia'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final confirm = await CustomDialog.showConfirmation(
                      context,
                      title: 'Liberar Pago al Cuidador',
                      message: '¿Confirmas que el servicio fue satisfactorio? Se transferirán inmediatamente los fondos al cuidador (${b.caregiverPayout > 0 ? b.caregiverPayout.toStringAsFixed(2) : b.cost.toStringAsFixed(2)} €).',
                      confirmText: 'Liberar Ahora',
                    );
                    if (confirm == true) {
                      await state.releaseEscrow(b.id);
                      if (context.mounted) {
                        CustomSnackBar.show(context, message: '🎉 ¡Pago liberado al cuidador con éxito! Gracias por tu confirmación.', type: SnackBarType.success);
                      }
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.warning_amber_rounded, color: Colors.deepOrange),
                  title: const Text('Tengo un problema / Abrir Incidencia', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.deepOrange)),
                  subtitle: const Text('Detener liberación automática y abrir acuerdo de resolución'),
                  onTap: () {
                    Navigator.pop(ctx);
                    showDialog(context: context, builder: (_) => DisputeDialog(booking: b));
                  },
                ),
              ],
              if (isClient && (b.status == BookingStatus.cancelled || b.status == BookingStatus.cancelledLate))
                ListTile(
                  leading: const Icon(Icons.flash_on_rounded, color: Colors.orange),
                  title: const Text('Buscar cuidador sustituto urgente', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.orange)),
                  subtitle: const Text('Encuentra profesionales disponibles hoy cerca de tu casa'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _findUrgentSubstitute(context);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.sos_rounded, color: Colors.red),
                title: const Text('Contacto de Emergencia / SOS', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.red)),
                subtitle: const Text('Llamada rápida al 112 o teléfono de contacto familiar'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showSosQuickContactModal(context, b, isClient);
                },
              ),
              if (canDiscard) ...[
                const Divider(height: 12),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                  title: const Text('Descartar intento de reserva', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.red)),
                  subtitle: const Text('Libera el horario si no vas a completar el pago'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final confirm = await CustomDialog.showConfirmation(
                      context,
                      title: 'Descartar Intento',
                      message: '¿Deseas descartar este intento de reserva no pagado?',
                      confirmText: 'Descartar',
                      isDestructive: true,
                    );
                    if (confirm == true) {
                      state.cancelBooking(b.id, 'Intento descartado por el cliente', false);
                    }
                  },
                ),
              ],
              if (canCancel) ...[
                const Divider(height: 12),
                ListTile(
                  leading: const Icon(Icons.cancel_outlined, color: Colors.red),
                  title: const Text('Cancelar Reserva', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.red)),
                  subtitle: const Text('Reembolso gratuito si faltan más de 24h'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final now = DateTime.now();
                    bool isLate = false;
                    DateTime? slotDt;
                    try {
                      final dp = b.day.split('-');
                      final tp = b.slot.split('-')[0].split(':');
                      slotDt = DateTime(int.parse(dp[0]), int.parse(dp[1]), int.parse(dp[2]), int.parse(tp[0]), int.parse(tp[1]));
                    } catch (_) {}

                    if (slotDt != null) {
                      final diffHours = slotDt.difference(now).inHours;
                      if (diffHours < 24) isLate = true;
                    }

                    bool? confirm = await CustomDialog.showConfirmation(
                      context,
                      title: 'Cancelar Reserva',
                      message: isLate
                          ? 'Al cancelar con menos de 24h de antelación, se aplicará una penalización: se te reembolsará el 45% del importe y el resto cubrirá la compensación del cuidador y los gastos de gestión.'
                          : 'Cancelación gratuita (>24h de antelación): Se te reembolsará el 100% del importe íntegramente a tu método de pago original sin ninguna penalización.',
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
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAddTaskDialog(
    BuildContext context,
    Booking b,
    BookingNotifier state,
  ) async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Añadir tarea para el cuidador'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Ej. Pastilla tensión a las 13:00, regar plantas...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                HapticFeedback.mediumImpact();
                state.addChecklistTask(b.id, ctrl.text.trim());
              }
              Navigator.pop(ctx);
            },
            child: const Text('Añadir a la Checklist'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditCareNotesDialog(
    BuildContext context,
    Booking b,
    BookingNotifier state,
  ) async {
    final ctrl = TextEditingController(text: b.careNotes);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('📝 Resumen del Cuidado'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Escribe cómo se encuentra el familiar hoy, qué ha comido, estado de ánimo...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              HapticFeedback.mediumImpact();
              state.updateCareNotes(b.id, ctrl.text.trim());
              Navigator.pop(ctx);
              CustomSnackBar.show(
                context,
                message: 'Resumen guardado en el Diario del Cuidado.',
                type: SnackBarType.success,
              );
            },
            child: const Text('Guardar Nota'),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadCarePhoto(
    BuildContext context,
    Booking b,
    BookingNotifier state,
  ) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 75);
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      final ref = FirebaseStorage.instance
          .ref()
          .child('care_journal/${b.id}/${DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      await state.addCarePhotoUrl(b.id, url);
      if (context.mounted) {
        CustomSnackBar.show(
          context,
          message: '📸 Foto subida al Diario del Cuidado para la familia.',
          type: SnackBarType.success,
        );
      }
    } catch (e) {
      if (context.mounted) {
        CustomSnackBar.show(
          context,
          message: 'No se pudo adjuntar la foto: $e',
          type: SnackBarType.error,
        );
      }
    }
  }

  Future<void> _shareLiveTrackingWithFamily(BuildContext context, Booking b) async {
    HapticFeedback.mediumImpact();
    final completed = b.careChecklist.where((t) => t.completed).length;
    final total = b.careChecklist.length;
    final pinLine = (b.checkInTime == null && (b.bookingPin?.isNotEmpty ?? false))
        ? '🔑 Código PIN de entrada (si recibes al cuidador en casa): ${b.bookingPin}\n'
        : '';
    final summaryText = '🛡️ Seguimiento SeniCare en Tiempo Real\n'
        '👩‍⚕️ Cuidador/a: ${b.caregiverName}\n'
        '📅 Fecha: ${_formatDay(b.day)} (${b.slot})\n'
        '📍 Estado: ${_getStatusText(b)}\n'
        '$pinLine'
        '📋 Checklist familiar: $completed de $total tareas completadas\n'
        '${b.careNotes.isNotEmpty ? "📝 Parte del día: ${b.careNotes}\n" : ""}'
        '🔗 Ver en vivo: https://senicare-3342d.web.app/#/tracking/${b.id}';

    await Clipboard.setData(ClipboardData(text: summaryText));
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.share_rounded, color: AppTheme.primary),
            SizedBox(width: 8),
            Expanded(child: Text('Enlace copiado para familiares')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hemos copiado el parte en tiempo real al portapapeles. Pégalo en vuestro grupo de WhatsApp familiar para que tus hermanos o familiares sigan la visita:',
              style: TextStyle(fontSize: 13, color: AppTheme.slateMuted),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.backgroundNeutral,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.borderSubtle),
              ),
              child: Text(
                summaryText,
                style: const TextStyle(fontSize: 12, height: 1.4),
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Listo'),
          ),
        ],
      ),
    );
  }

  Future<void> _showSosQuickContactModal(
    BuildContext context,
    Booking b,
    bool isClient,
  ) async {
    HapticFeedback.heavyImpact();
    final clientProfile = await _getClientProfile(b.clientId);
    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.sos_rounded, color: Colors.red.shade700, size: 26),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Contacto Rápido y Emergencias',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                        Text(
                          'Asistencia inmediata durante el servicio activo',
                          style: TextStyle(fontSize: 12.5, color: AppTheme.slateMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (clientProfile != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundNeutral,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '📍 Domicilio: ${clientProfile.homeAddress.isNotEmpty ? clientProfile.homeAddress : "No especificado"}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '🩺 Indicaciones médicas: ${clientProfile.patientDetails.isNotEmpty ? clientProfile.patientDetails : "Sin observaciones médicas registradas"}',
                        style: const TextStyle(fontSize: 13, color: AppTheme.darkSlate),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final uri = Uri.parse('tel:112');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.local_hospital_rounded),
                  label: const Text('Llamar al 112 (Emergencias Sanitarias)'),
                ),
              ),
              const SizedBox(height: 10),
              if (clientProfile != null && clientProfile.phone.isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final uri = Uri.parse('tel:${clientProfile.phone}');
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      }
                    },
                    icon: const Icon(Icons.phone_in_talk_rounded),
                    label: Text('Llamar a la familia (${clientProfile.phone})'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addToGoogleCalendar(BuildContext context, Booking b, bool isClient) async {
    HapticFeedback.selectionClick();
    try {
      final dayParts = b.day.split('-');
      final year = int.parse(dayParts[0]);
      final month = int.parse(dayParts[1]);
      final day = int.parse(dayParts[2]);

      int startHour = 9, startMin = 0, endHour = 11, endMin = 0;
      if (b.slot.contains('-')) {
        final parts = b.slot.split('-');
        final sp = parts[0].split(':');
        final ep = parts[1].split(':');
        startHour = int.parse(sp[0]);
        startMin = int.parse(sp[1]);
        endHour = int.parse(ep[0]);
        endMin = int.parse(ep[1]);
      } else if (b.slot.contains(':')) {
        final sp = b.slot.split(':');
        startHour = int.parse(sp[0]);
        startMin = int.parse(sp[1]);
        endHour = (startHour + 1).clamp(0, 23);
      }

      final startDt = DateTime(year, month, day, startHour, startMin);
      final endDt = DateTime(year, month, day, endHour, endMin);
      String fmt(DateTime dt) =>
          '${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}T${dt.hour.toString().padLeft(2, '0')}${dt.minute.toString().padLeft(2, '0')}00';

      final title = Uri.encodeComponent(
        isClient
            ? 'SeniCare: Cuidado con ${b.caregiverName}'
            : 'SeniCare: Servicio a domicilio (${b.slot})',
      );
      final details = Uri.encodeComponent(
        'Servicio confirmado en SeniCare.\n'
        'Horario: ${b.slot}\n'
        '${b.bookingPin != null ? "PIN de entrada: ${b.bookingPin}\n" : ""}'
        'Checklist familiar: ${b.careChecklist.map((t) => t.title).join(", ")}',
      );
      final url = Uri.parse(
        'https://calendar.google.com/calendar/render?action=TEMPLATE&text=$title&dates=${fmt(startDt)}/${fmt(endDt)}&details=$details',
      );
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else if (context.mounted) {
        CustomSnackBar.show(
          context,
          message: 'No se pudo abrir el calendario en este dispositivo.',
          type: SnackBarType.info,
        );
      }
    } catch (e) {
      if (context.mounted) {
        CustomSnackBar.show(
          context,
          message: 'No se pudo generar el evento de calendario: $e',
          type: SnackBarType.error,
        );
      }
    }
  }

  Future<void> _repeatBookingNextWeek(BuildContext context, Booking b) async {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: AppTheme.primarySurface,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.repeat_rounded, color: AppTheme.primary, size: 26),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Plan de Cuidado Continuo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        Text('Reserva asegurada semanal con pago protegido', style: TextStyle(fontSize: 12.5, color: AppTheme.slateMuted)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundNeutral,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.borderSubtle),
                ),
                child: const Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.shield_outlined, color: AppTheme.primary, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Escrow Semanal: No pagas todo por adelantado. Sólo se retiene el saldo 24h antes de cada visita.',
                            style: TextStyle(fontSize: 12.5, color: AppTheme.darkSlate),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.event_repeat_rounded, color: AppTheme.primary, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '0% Permanencia: Puedes pausar o cancelar cualquier semana con más de 24h sin ningún coste.',
                            style: TextStyle(fontSize: 12.5, color: AppTheme.darkSlate),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _executeRepeatBooking(context, b);
                  },
                  icon: const Icon(Icons.calendar_today_rounded, size: 18),
                  label: Text('Repetir la próxima semana con ${b.caregiverName}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _executeRepeatBooking(BuildContext context, Booking b) async {
    HapticFeedback.mediumImpact();
    try {
      final caregiver = await DependencyInjection.caregivers.getCaregiver(b.caregiverId);
      if (caregiver == null) {
        if (context.mounted) {
          CustomSnackBar.show(
            context,
            message: 'No se ha encontrado el perfil activo del cuidador.',
            type: SnackBarType.error,
          );
        }
        return;
      }

      DateTime baseDate;
      try {
        baseDate = DateFormat('yyyy-MM-dd').parse(b.day);
      } catch (_) {
        baseDate = DateTime.now();
      }
      DateTime nextDate = baseDate.add(const Duration(days: 7));
      final now = DateTime.now();
      while (nextDate.isBefore(DateTime(now.year, now.month, now.day + 1))) {
        nextDate = nextDate.add(const Duration(days: 7));
      }
      final nextDateStr =
          '${nextDate.year}-${nextDate.month.toString().padLeft(2, '0')}-${nextDate.day.toString().padLeft(2, '0')}';

      int startHour = 10;
      int endHour = 12;
      if (b.slot.contains('-')) {
        final parts = b.slot.split('-');
        startHour = int.tryParse(parts[0].split(':')[0]) ?? 10;
        endHour = int.tryParse(parts[1].split(':')[0]) ?? (startHour + 2);
      } else if (b.slot.contains(':')) {
        startHour = int.tryParse(b.slot.split(':')[0]) ?? 10;
        endHour = startHour + 1;
      }
      if (endHour <= startHour) endHour = startHour + 1;

      final slots = <TimeSlot>[];
      for (int h = startHour; h < endHour; h++) {
        slots.add(TimeSlot(
          id: 'repeat_${nextDateStr}_$h',
          dateTime: DateTime(nextDate.year, nextDate.month, nextDate.day, h, 0),
        ));
      }

      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentScreen(
            caregiver: caregiver,
            dateString: nextDateStr,
            slots: slots,
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        CustomSnackBar.show(
          context,
          message: 'Error al preparar la repetición de reserva: $e',
          type: SnackBarType.error,
        );
      }
    }
  }

  Future<void> _showQuickTipDialog(
    BuildContext context,
    Booking b,
    BookingNotifier state,
  ) async {
    double selectedTip = 5.0;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Text('☕', style: TextStyle(fontSize: 22)),
              SizedBox(width: 8),
              Expanded(child: Text('Agradecer con una propina')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'El 100% de la propina va íntegro para ${b.caregiverName}, sin ninguna comisión de plataforma.',
                style: const TextStyle(fontSize: 13, color: AppTheme.slateMuted),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [2.0, 5.0, 10.0].map((amount) {
                  final isSelected = selectedTip == amount;
                  return ChoiceChip(
                    label: Text('+${amount.toInt()} €'),
                    selected: isSelected,
                    selectedColor: AppTheme.secondaryColor.withValues(alpha: 0.2),
                    checkmarkColor: AppTheme.secondaryColor,
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isSelected ? AppTheme.secondaryColor : AppTheme.darkSlate,
                    ),
                    onSelected: (_) => setDialogState(() => selectedTip = amount),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                HapticFeedback.mediumImpact();
                await state.addTipToBooking(b.id, selectedTip);
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  CustomSnackBar.show(
                    context,
                    message: '☕ ¡Gracias! Has enviado +${selectedTip.toInt()} € íntegros a ${b.caregiverName}.',
                    type: SnackBarType.success,
                  );
                }
              },
              style: FilledButton.styleFrom(backgroundColor: AppTheme.secondaryColor),
              child: Text('Enviar +${selectedTip.toInt()} €'),
            ),
          ],
        ),
      ),
    );
  }

  void _findUrgentSubstitute(BuildContext context) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.bolt_rounded, color: Colors.red.shade700, size: 28),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sustitución Express (<2 horas)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        Text('Encuentra un cuidador verificado de inmediato', style: TextStyle(fontSize: 12.5, color: AppTheme.slateMuted)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Tu familiar no se quedará desatendido. El importe abonado permanece seguro en Escrow y puedes reasignarlo a un nuevo profesional disponible hoy mismo.',
                style: TextStyle(fontSize: 13, color: AppTheme.darkSlate, height: 1.4),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    try {
                      final caregiverNotifier = context.read<CaregiverNotifier>();
                      caregiverNotifier.resetFilters();
                      caregiverNotifier.setSortOption(CaregiverSortOption.distanceAsc);
                    } catch (_) {}
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(
                            title: const Text('🚨 Cuidadores Cercanos Disponibles Hoy'),
                          ),
                          body: const ExplorerScreen(),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.near_me_rounded),
                  label: const Text('Ver Cuidadores Cercanos Disponibles Hoy', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CreateOfferScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add_task_rounded),
                  label: const Text('Publicar Oferta Urgente en el Tablón', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showLegalReceiptDialog(BuildContext context, Booking b) async {
    HapticFeedback.selectionClick();
    final profile = await _getClientProfile(b.clientId);
    if (!context.mounted) return;
    final receiptNumber = 'SC-${b.day.replaceAll("-", "")}-${b.id.substring(0, b.id.length > 5 ? 5 : b.id.length).toUpperCase()}';
    final receiptText = '🧾 JUSTIFICANTE OFICIAL DE SERVICIO ASISTENCIAL — SENICARE\n'
        'Nº Justificante: $receiptNumber\n'
        'Plataforma: SeniCare Asistencia Domiciliaria S.L. (Directiva Europea DAC7 / RGPD Art. 9)\n'
        '────────────────────────────────────────\n'
        'Titular / Familia: ${profile?.name ?? b.clientId}\n'
        'Domicilio: ${profile?.homeAddress.isNotEmpty == true ? profile!.homeAddress : "Registrado en cuenta"}\n'
        'Profesional Sociosanitario: ${b.caregiverName} (ID: ${b.caregiverId})\n'
        'Fecha y Horario: ${_formatDay(b.day)} (${b.slot})\n'
        '────────────────────────────────────────\n'
        'Honorarios Asistenciales: ${b.cost.toStringAsFixed(2)} €\n'
        'Gestión, Seguro RC y Cobertura (3%): ${b.clientFee.toStringAsFixed(2)} €\n'
        '${b.tipAmount > 0 ? "Propina voluntaria (100% cuidador): ${b.tipAmount.toStringAsFixed(2)} €\n" : ""}'
        'TOTAL ABONADO: ${(b.totalPaid + b.tipAmount).toStringAsFixed(2)} €\n'
        'Ref. Transacción Stripe Escrow: ${b.paymentIntentId ?? "Verificada"}\n'
        'Estado: Servicio prestado y verificado en domicilio.';

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.receipt_long_rounded, color: AppTheme.primary),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Justificante Oficial de Gasto',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Válido como comprobante para ayudas a la Ley de Dependencia, seguros privados de salud o deducciones autonómicas:',
                style: TextStyle(fontSize: 12.5, color: AppTheme.slateMuted),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundNeutral,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.borderSubtle),
                ),
                child: Text(
                  receiptText,
                  style: const TextStyle(fontSize: 11.5, height: 1.45, fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: receiptText));
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                CustomSnackBar.show(
                  context,
                  message: '🧾 Justificante oficial copiado al portapapeles para guardar o imprimir.',
                  type: SnackBarType.success,
                );
              }
            },
            icon: const Icon(Icons.copy_rounded, size: 17),
            label: const Text('Copiar / Descargar'),
          ),
        ],
      ),
    );
  }

  Future<void> _showFridgeSheetModal(BuildContext context, Booking b) async {
    HapticFeedback.mediumImpact();
    final profile = await _getClientProfile(b.clientId);
    if (!context.mounted) return;

    final pinText = b.bookingPin ?? "Sin PIN";
    final home = profile?.homeAddress.isNotEmpty == true ? profile!.homeAddress : "Domicilio familiar";
    final phone = profile?.phone.isNotEmpty == true ? profile!.phone : "Teléfono familiar registrado";
    final medicalNotes = profile?.patientDetails.isNotEmpty == true ? profile!.patientDetails : "Sin pautas médicas específicas";
    final tasksList = b.careChecklist.isNotEmpty
        ? b.careChecklist.map((t) => "• ${t.title}").join("\n")
        : "• Compañía, atención general y supervisión en el hogar";

    final fridgeSheetText = '🧊 FICHA DE CUIDADOS PARA LA NEVERA · SENICARE\n'
        '================================================\n'
        '🏠 Domicilio: $home\n'
        '👩‍⚕️ Cuidador/a: ${b.caregiverName}\n'
        '📅 Fecha de Visita: ${_formatDay(b.day)} (${b.slot})\n'
        '🔑 CÓDIGO PIN DE ENTRADA: $pinText\n'
        '(Díselo al cuidador al abrir la puerta para iniciar el servicio)\n\n'
        '🚨 TELÉFONOS DE CONTACTO Y EMERGENCIAS:\n'
        '• Emergencias Médicas Nacionales: 112\n'
        '• Familia Directa: $phone\n\n'
        '💊 PAUTAS Y MEDICACIÓN:\n'
        '$medicalNotes\n\n'
        '📋 TAREAS PROGRAMADAS:\n'
        '$tasksList\n'
        '================================================\n'
        'SeniCare: Servicio con Seguro de Responsabilidad Civil y Custodia de Pago.';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.primarySurface,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                      ),
                      child: const Icon(Icons.kitchen_rounded, color: AppTheme.primary, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Ficha para la Nevera', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.darkSlate)),
                          Text('Imprime o comparte para tenerla visible en la cocina', style: TextStyle(fontSize: 12.5, color: AppTheme.slateMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.amber.shade300, width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.amber.shade100.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Text('🧲', style: TextStyle(fontSize: 18)),
                              SizedBox(width: 6),
                              Text('SENICARE · HOJA DE TURNO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.darkSlate)),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.borderSubtle),
                            ),
                            child: Text(
                              _formatDay(b.day),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5, color: AppTheme.primary),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      Text('📍 Domicilio: $home', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('👩‍⚕️ Cuidador/a: ${b.caregiverName} (${b.slot})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.primary, width: 1.5),
                        ),
                        child: Column(
                          children: [
                            const Text('🔑 CÓDIGO PIN DE ENTRADA', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                            const SizedBox(height: 4),
                            Text(
                              pinText,
                              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 8, color: AppTheme.primary),
                            ),
                            const Text('Dile estos números al cuidador cuando llegue a casa', style: TextStyle(fontSize: 11, color: AppTheme.slateMuted)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('🚨 TELÉFONOS DE CONTACTO:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.red)),
                      const SizedBox(height: 2),
                      const Text('• 112 (Emergencias Médicas / Sanitarias)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                      Text('• Familia Directa: $phone', style: const TextStyle(fontSize: 12.5)),
                      if (profile != null && profile.patientDetails.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text('💊 PAUTAS Y MEDICACIÓN:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.darkSlate)),
                        const SizedBox(height: 2),
                        Text(profile.patientDetails, style: const TextStyle(fontSize: 12.5, color: AppTheme.darkSlate)),
                      ],
                      if (b.careChecklist.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text('📋 CHECKLIST DEL SERVICIO:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.darkSlate)),
                        const SizedBox(height: 2),
                        ...b.careChecklist.map((t) => Text('• ${t.title}', style: const TextStyle(fontSize: 12.5))),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          HapticFeedback.selectionClick();
                          await Clipboard.setData(ClipboardData(text: fridgeSheetText));
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (context.mounted) {
                            CustomSnackBar.show(
                              context,
                              message: '📋 Ficha de la nevera copiada para imprimir o pegar.',
                              type: SnackBarType.success,
                            );
                          }
                        },
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text('Copiar Ficha', style: TextStyle(fontSize: 12.5)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () async {
                          HapticFeedback.mediumImpact();
                          final encoded = Uri.encodeComponent(fridgeSheetText);
                          final whatsappUrl = Uri.parse('whatsapp://send?text=$encoded');
                          final webUrl = Uri.parse('https://wa.me/?text=$encoded');
                          if (await canLaunchUrl(whatsappUrl)) {
                            await launchUrl(whatsappUrl);
                          } else if (await canLaunchUrl(webUrl)) {
                            await launchUrl(webUrl, mode: LaunchMode.externalApplication);
                          } else {
                            await Clipboard.setData(ClipboardData(text: fridgeSheetText));
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (context.mounted) {
                              CustomSnackBar.show(
                                context,
                                message: 'Copiado al portapapeles para WhatsApp.',
                                type: SnackBarType.info,
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.send_rounded, size: 16),
                        label: const Text('WhatsApp', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPhotoFullScreen(BuildContext context, String photoUrl, String caregiverName) {
    HapticFeedback.selectionClick();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: AppTheme.darkSlate,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '📸 Foto compartida por $caregiverName',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 3.5,
                    child: Image.network(
                      photoUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Padding(
                        padding: EdgeInsets.all(40),
                        child: Icon(Icons.broken_image_rounded, size: 48, color: Colors.grey),
                      ),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: Colors.grey.shade50,
                    child: const Text(
                      'Pellizca para ampliar. Las fotos del diario de cuidados quedan guardadas en el historial de la visita.',
                      style: TextStyle(fontSize: 11.5, color: AppTheme.slateMuted),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

