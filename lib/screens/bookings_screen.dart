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
                        
                        if (isActiveTab) ...[
                          const SizedBox(height: 16),
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
                                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                                  label: const Text('Chat'),
                                ),
                              ),
                              if (isClient && b.status == BookingStatus.confirmed) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _shareLiveTrackingWithFamily(context, b),
                                    icon: const Icon(Icons.share_rounded, size: 18, color: AppTheme.primary),
                                    label: const Text('Compartir', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ],
                              if (b.status == BookingStatus.confirmed) ...[
                                const SizedBox(width: 8),
                                IconButton(
                                  onPressed: () => _addToGoogleCalendar(context, b, isClient),
                                  style: IconButton.styleFrom(
                                    backgroundColor: AppTheme.primarySurface,
                                    foregroundColor: AppTheme.primary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.3)),
                                    ),
                                  ),
                                  tooltip: 'Añadir a Google Calendar / Agenda',
                                  icon: const Icon(Icons.event_available_rounded, size: 20),
                                ),
                                const SizedBox(width: 6),
                                IconButton(
                                  onPressed: () => _showSosQuickContactModal(context, b, isClient),
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.red.shade50,
                                    foregroundColor: Colors.red.shade700,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(color: Colors.red.shade200),
                                    ),
                                  ),
                                  tooltip: 'SOS / Contacto Rápido',
                                  icon: const Icon(Icons.sos_rounded, size: 22),
                                ),
                              ],
                            ],
                          ),
                          if (isClient && b.status == BookingStatus.confirmed && b.checkInTime == null) ...[
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

                          if (isClient && b.status == BookingStatus.pendingPayment)
                            Padding(
                              padding: const EdgeInsets.only(top: 12.0),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.orange.shade300),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.hourglass_top_rounded, size: 16, color: Colors.deepOrange),
                                        SizedBox(width: 6),
                                        Text(
                                          'Pago no completado',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.deepOrange),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'Si cancelaste o abandonaste la pasarela de pago, puedes descartar este intento para liberar las horas.',
                                      style: TextStyle(fontSize: 12, color: AppTheme.darkSlate),
                                    ),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton(
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
                                          foregroundColor: Colors.red.shade700,
                                          side: BorderSide(color: Colors.red.shade300),
                                        ),
                                        child: const Text('Descartar intento de reserva'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          
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
                                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                                      child: const Text('Rechazar'),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: () async {
                                        HapticFeedback.mediumImpact();
                                        await state.confirmBooking(b.id);
                                        if (context.mounted) {
                                          CustomSnackBar.show(context, message: '✅ ¡Servicio aceptado! Recuerda registrar tu llegada al domicilio.', type: SnackBarType.success);
                                        }
                                      },
                                      child: const Text('Aceptar'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          
                          if (!isClient && b.status == BookingStatus.confirmed && b.checkInTime == null && !isBookingExpired(b))
                            Padding(
                              padding: const EdgeInsets.only(top: 16.0),
                              child: Column(
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
                                        ),
                                        icon: const Icon(Icons.directions_car_rounded),
                                        label: const Text('🚗 Avisar a la familia: Estoy en camino'),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton.icon(
                                      onPressed: () {
                                        Navigator.push(context, MaterialPageRoute(
                                          builder: (_) => ScannerScreen(booking: b)
                                        ));
                                      },
                                      icon: const Icon(Icons.qr_code_scanner),
                                      label: const Text('Fichar Llegada (QR / PIN)'),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          if (!isClient && b.status == BookingStatus.confirmed && b.checkInTime != null && b.liveStatus != 'completed')
                            Padding(
                              padding: const EdgeInsets.only(top: 14.0),
                              child: SizedBox(
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
                              ),
                            ),
                        ],
                        
                        if (!isActiveTab) ...[
                          if (isClient && b.escrowStatus == 'held' && b.checkInTime != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 14.0),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.blue.shade200),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.shield_outlined, size: 18, color: Colors.blue.shade800),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Pago Protegido en Custodia (24h)',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue.shade900),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'El importe (${b.totalPaid.toStringAsFixed(2)} €) está retenido de forma segura. Se transferirá al cuidador automáticamente en 24h o puedes liberarlo ya si todo fue excelente.',
                                      style: TextStyle(fontSize: 12, color: Colors.blue.shade900, height: 1.3),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: FilledButton.icon(
                                            onPressed: () async {
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
                                            style: FilledButton.styleFrom(
                                              backgroundColor: Colors.green.shade700,
                                              padding: const EdgeInsets.symmetric(vertical: 10),
                                            ),
                                            icon: const Icon(Icons.check_circle_outline, size: 16),
                                            label: const Text('Liberar Pago Ahora', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        OutlinedButton.icon(
                                          onPressed: () {
                                            showDialog(context: context, builder: (_) => DisputeDialog(booking: b));
                                          },
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.deepOrange.shade800,
                                            side: BorderSide(color: Colors.deepOrange.shade300),
                                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                                          ),
                                          icon: const Icon(Icons.warning_amber_rounded, size: 16),
                                          label: const Text('Incidencia', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          if (isClient && isBookingExpired(b) && b.checkInTime == null && b.escrowStatus != 'refunded')
                            Padding(
                              padding: const EdgeInsets.only(top: 14.0),
                              child: Container(
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
                                      'El cuidador no registró su llegada presencial. Tu importe (${b.totalPaid.toStringAsFixed(2)} €) está asegurado y el reembolso total se tramita automáticamente sin costes.',
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
                              ),
                            ),
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
                            if (isClient && b.status != BookingStatus.cancelled && b.status != BookingStatus.cancelledLate) ...[
                              Padding(
                                padding: const EdgeInsets.only(top: 10.0),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => _repeatBookingNextWeek(context, b),
                                        icon: const Icon(Icons.repeat_rounded, size: 17, color: AppTheme.primary),
                                        label: const Text(
                                          '🔄 Repetir semana',
                                          style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 12.5),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => _showLegalReceiptDialog(context, b),
                                        icon: const Icon(Icons.receipt_long_rounded, size: 17, color: AppTheme.darkSlate),
                                        label: const Text(
                                          '🧾 Justificante Legal',
                                          style: TextStyle(color: AppTheme.darkSlate, fontWeight: FontWeight.bold, fontSize: 12.5),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (b.tipAmount == 0 && b.isReviewed)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: TextButton.icon(
                                      onPressed: () => _showQuickTipDialog(context, b, state),
                                      icon: const Text('☕', style: TextStyle(fontSize: 16)),
                                      label: const Text(
                                        'Enviar propina de agradecimiento (100% para el cuidador)',
                                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.secondaryColor),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                            if (isClient && (b.status == BookingStatus.cancelled || b.status == BookingStatus.cancelledLate))
                              Padding(
                                padding: const EdgeInsets.only(top: 10.0),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: () => _findUrgentSubstitute(context),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.orange.shade900,
                                      side: BorderSide(color: Colors.orange.shade400),
                                    ),
                                    icon: const Icon(Icons.flash_on_rounded, size: 18),
                                    label: const Text(
                                      '🚨 Buscar sustituto urgente disponible hoy',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                                    ),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primarySurface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.assignment_turned_in_rounded, color: AppTheme.primary, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Diario del Cuidado y Checklist Familiar',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: AppTheme.darkSlate,
                  ),
                ),
              ),
              if (totalCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: completedCount == totalCount
                        ? AppTheme.secondaryColor.withValues(alpha: 0.16)
                        : AppTheme.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$completedCount/$totalCount hechas',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: completedCount == totalCount
                          ? AppTheme.secondaryColor
                          : AppTheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
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
            SizedBox(
              height: 70,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: b.carePhotoUrls.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    b.carePhotoUrls[i],
                    width: 70,
                    height: 70,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 70,
                      height: 70,
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.photo_camera_back_rounded),
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
            title: const Text('🚨 Sustitución Urgente (Más Cercanos)'),
          ),
          body: const ExplorerScreen(),
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
}

