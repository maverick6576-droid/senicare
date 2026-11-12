import 'dart:math';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/screens/screens.dart';
import 'package:senicare/widgets/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

class CaregiverDashboard extends StatefulWidget {
  const CaregiverDashboard({super.key});

  @override
  State<CaregiverDashboard> createState() => _CaregiverDashboardState();
}

class _CaregiverDashboardState extends State<CaregiverDashboard> {
  List<Map<String, dynamic>> _clientStats = [];
  final Map<String, Future<ClientProfile?>> _clientProfileCache = {};
  bool _isLoading = true;
  bool _showAllRequests = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<ClientProfile?> _getClientProfile(String clientId) {
    if (clientId.isEmpty) return Future.value(null);
    return _clientProfileCache.putIfAbsent(
      clientId,
      () => DependencyInjection.clients.getClient(clientId),
    );
  }

  Future<void> _refreshAll() async {
    final auth = context.read<AuthNotifier>();
    final bookingState = context.read<BookingNotifier>();
    _clientProfileCache.clear();
    await Future.wait([
      auth.reloadRole(),
      bookingState.refreshBookings(),
      _loadStats(),
    ]);
  }

  Future<void> _loadStats() async {
    final auth = context.read<AuthNotifier>();
    final caregiverId = auth.currentCaregiver?.id ?? auth.currentUserId ?? '';

    if (caregiverId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final stats = await DependencyInjection.stats.getCaregiverClientStats(caregiverId);

      // Resolver nombres de clientes en paralelo usando la caché
      await Future.wait(stats.map((stat) async {
        final clientId = stat['clientId'] as String?;
        if (clientId != null && clientId.isNotEmpty) {
          final profile = await _getClientProfile(clientId);
          if (profile != null) {
            stat['clientName'] = _extractFamilyName(profile, clientId);
          }
        }
      }));

      if (mounted) {
        setState(() {
          _clientStats = stats;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _extractFamilyName(ClientProfile? profile, String fallbackId) {
    final clientName = profile?.name.trim() ?? '';
    if (clientName.isEmpty) {
      return fallbackId.isNotEmpty ? fallbackId.substring(0, min(5, fallbackId.length)) : 'Familia';
    }
    final nameParts = clientName.split(RegExp(r'\s+'));
    return nameParts.length > 1 ? nameParts[1] : clientName;
  }

  String _formatFriendlyDay(String rawDay) {
    try {
      DateTime date;
      if (rawDay.contains('/')) {
        date = DateFormat('dd/MM/yyyy').parse(rawDay);
      } else {
        date = DateFormat('yyyy-MM-dd').parse(rawDay);
      }
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));
      final target = DateTime(date.year, date.month, date.day);

      if (target == today) return 'Hoy';
      if (target == tomorrow) return 'Mañana';
      return DateFormat('dd/MM/yyyy').format(date);
    } catch (_) {
      return rawDay;
    }
  }

  double _calculateCaregiverNet(Booking b) => b.netPayoutForCaregiver;

  int _compareBookingsChronologically(Booking a, Booking b) {
    final dtA = a.scheduledStartTime ?? a.createdAt;
    final dtB = b.scheduledStartTime ?? b.createdAt;
    return dtA.compareTo(dtB);
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthNotifier>(context);
    final bookingState = Provider.of<BookingNotifier>(context);
    final user = auth.currentCaregiver;
    final tutorialTargets = TutorialScope.maybeOf(context);

    final firstName = (user?.name ?? '').trim().split(RegExp(r'\s+')).firstOrNull ?? '';
    final greetingName = (firstName.isNotEmpty && firstName != 'Sin') ? firstName : 'Cuidador';

    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          // Saludo amable y claro
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hola, $greetingName',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.darkSlate,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Aquí tienes el resumen tranquilo de tus turnos e ingresos.',
                  style: TextStyle(fontSize: 13.5, color: AppTheme.slateMuted),
                ),
              ],
            ),
          ),

          if (user != null) _buildProfileAlerts(user),

          // Acceso rápido a Disponibilidad Horaria (compacto y limpio)
          Container(
            key: tutorialTargets?.dashboardAvailabilityKey,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: AppTheme.modernCardDecoration(
              radius: 18,
              borderColor: AppTheme.primary.withValues(alpha: 0.2),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primarySurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.calendar_month_rounded, color: AppTheme.primary, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tu Disponibilidad',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.darkSlate),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Define qué días y horas puedes trabajar.',
                        style: TextStyle(fontSize: 12.5, color: AppTheme.slateMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const CaregiverCalendarScreen()));
                  },
                  child: const Text('Horarios', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),

          Builder(
            builder: (context) {
              final effectiveCaregiverId = user?.id ?? auth.currentUserId ?? '';

              final caregiverBookings = bookingState.bookings.where((b) {
                if (effectiveCaregiverId.isEmpty) return false;
                return b.caregiverId == effectiveCaregiverId ||
                    b.caregiverId == auth.currentUserId ||
                    b.caregiverId == user?.id;
              }).toList();

              // Servicios válidos realizados (excluye cancelados, reembolsados, disputados y No-Shows sin check-in)
              final validCompletedBookings = caregiverBookings.where((b) {
                if (b.status == BookingStatus.cancelled ||
                    b.status == BookingStatus.pending ||
                    b.status == BookingStatus.pendingPayment) {
                  return false;
                }
                if (b.escrowStatus == 'refunded' ||
                    b.escrowStatus == 'cancelled' ||
                    b.escrowStatus == 'disputed') {
                  return false;
                }

                final isReleasedEscrow = b.escrowStatus == 'released' ||
                    b.escrowStatus == 'released_manual' ||
                    b.escrowStatus == 'released_auto' ||
                    b.escrowStatus == 'resolved_partial';
                final isCompletedStatus = b.status == BookingStatus.completed;
                final isCheckedIn = b.checkInTime != null;
                final isReviewed = b.isReviewed;

                // Nota: si un servicio confirmó y caducó SIN check-in, fue No-Show y NO cuenta.
                return isReleasedEscrow || isCompletedStatus || isCheckedIn || isReviewed;
              }).toList();

              double releasedIncome = 0.0;
              double heldIncome = 0.0;
              double totalTips = 0.0;

              for (final b in validCompletedBookings) {
                final net = _calculateCaregiverNet(b);
                totalTips += b.tipAmount;

                final isReleased = b.escrowStatus == 'released' ||
                    b.escrowStatus == 'released_manual' ||
                    b.escrowStatus == 'released_auto' ||
                    b.escrowStatus == 'resolved_partial';

                if (isReleased) {
                  releasedIncome += net + b.tipAmount;
                } else {
                  heldIncome += net + b.tipAmount;
                }
              }

              // Disputas abiertas pendientes de respuesta del cuidador
              final openDisputes = caregiverBookings
                  .where((b) => b.escrowStatus == 'disputed' && b.disputeEscalated != true)
                  .toList();

              // Servicio en curso: fichado y sin marcar salida aún (no desaparece aunque pase su hora fin)
              final inProgressBookings = caregiverBookings.where((b) {
                return b.status == BookingStatus.confirmed &&
                    b.checkInTime != null &&
                    b.liveStatus != 'completed' &&
                    b.escrowStatus != 'refunded' &&
                    b.escrowStatus != 'disputed';
              }).toList()
                ..sort(_compareBookingsChronologically);
              final activeService = inProgressBookings.isNotEmpty ? inProgressBookings.first : null;

              // Próximo servicio pendiente de llegada
              final upcomingBookings = caregiverBookings.where((b) {
                return b.status == BookingStatus.confirmed &&
                    b.checkInTime == null &&
                    !b.isExpired;
              }).toList()
                ..sort(_compareBookingsChronologically);
              final nextService = upcomingBookings.isNotEmpty ? upcomingBookings.first : null;

              // Solicitudes pendientes de aceptar/rechazar
              final incomingRequests = caregiverBookings.where((b) {
                return b.status == BookingStatus.pending && !b.isExpired;
              }).toList()
                ..sort(_compareBookingsChronologically);

              final String incomeSubtitle;
              if (heldIncome > 0) {
                incomeSubtitle = '+${heldIncome.toStringAsFixed(2)} € en custodia (24h)';
              } else if (totalTips > 0) {
                incomeSubtitle = 'Incluye +${totalTips.toStringAsFixed(0)} € en propinas';
              } else {
                incomeSubtitle = 'Ingresos netos liberados';
              }

              final String servicesSubtitle = upcomingBookings.isNotEmpty
                  ? '${upcomingBookings.length} próximo${upcomingBookings.length > 1 ? "s" : ""} confirmado${upcomingBookings.length > 1 ? "s" : ""}'
                  : 'Servicios completados';

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    key: tutorialTargets?.dashboardStatsKey,
                    children: [
                      Expanded(
                        child: StatCard(
                          title: 'Cobrado',
                          value: '${releasedIncome.toStringAsFixed(2)} €',
                          subtitle: incomeSubtitle,
                          icon: Icons.euro_rounded,
                          color: Colors.green.shade700,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StatCard(
                          title: 'Realizados',
                          value: validCompletedBookings.length.toString(),
                          subtitle: servicesSubtitle,
                          icon: Icons.check_circle_rounded,
                          color: AppTheme.primary,
                        ),
                      ),
                    ],
                  ),

                  if (openDisputes.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildOpenDisputesAlert(context, openDisputes, bookingState),
                  ],

                  if (incomingRequests.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildIncomingRequestsBanner(context, incomingRequests, bookingState),
                  ],

                  const SizedBox(height: 24),
                  Column(
                    key: tutorialTargets?.dashboardServiceFlowKey,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (activeService != null) ...[
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.green),
                            ),
                            const SizedBox(width: 8),
                            const Text('Servicio en Curso', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.darkSlate)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildActiveServiceCard(context, activeService, bookingState),
                      ] else ...[
                        const Text('Próximo Servicio', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.darkSlate)),
                        const SizedBox(height: 12),
                        if (nextService == null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: AppTheme.modernCardDecoration(radius: 16),
                            child: const Row(
                              children: [
                                Icon(Icons.event_available_rounded, color: AppTheme.slateMuted, size: 22),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'No tienes servicios programados próximamente.',
                                    style: TextStyle(color: AppTheme.slateMuted, fontSize: 13.5),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          _buildNextServiceCard(context, nextService, bookingState),
                      ],
                    ],
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 24),
          Row(
            key: tutorialTargets?.dashboardCommissionsKey,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text('Mis Familias y Comisiones', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppTheme.darkSlate)),
              ),
              TextButton.icon(
                onPressed: () => _showCommissionTiersModal(context),
                icon: const Icon(Icons.info_outline_rounded, size: 17),
                label: const Text('Tramos (18%→6%)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
          else if (_clientStats.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: AppTheme.modernCardDecoration(radius: 16),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '📉 Cuanto más cuidas a una familia, menos comisión pagas',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppTheme.darkSlate),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Empiezas cobrando el 82% y al superar 80 horas con la misma familia pasas al 94% neto (solo 6% de comisión).',
                    style: TextStyle(fontSize: 12.5, color: AppTheme.slateMuted, height: 1.35),
                  ),
                ],
              ),
            )
          else
            ..._clientStats.map((stat) {
              final hours = stat['accumulatedHours'] as int? ?? 0;
              final clientName = stat['clientName'] as String? ?? 'Familia';

              double nextTierHours = 20.0;
              double currentRate = 18.0;
              if (hours > 20 && hours <= 80) {
                nextTierHours = 80.0;
                currentRate = 12.0;
              } else if (hours > 80) {
                nextTierHours = 80.0;
                currentRate = 6.0;
              }

              final progress = hours >= 80 ? 1.0 : (hours / nextTierHours).clamp(0.0, 1.0);

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: AppTheme.modernCardDecoration(radius: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text('Familia $clientName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5), overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: AppTheme.primarySurface, borderRadius: BorderRadius.circular(10)),
                          child: Text('Cobras ${100 - currentRate.toInt()}%', style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.grey.shade200,
                      color: AppTheme.primary,
                      minHeight: 7,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      hours >= 80
                          ? '🏆 $hours h acumuladas · Tarifa máxima (solo 6% comisión)'
                          : '$hours h acumuladas · Te faltan ${(nextTierHours.toInt() - hours).clamp(1, 80)} h para cobrar el ${hours <= 20 ? "88%" : "94%"}',
                      style: const TextStyle(color: AppTheme.slateMuted, fontSize: 12.5),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  void _showCommissionTiersModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.trending_down_rounded, color: AppTheme.primary, size: 24),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Tramos de Comisión por Fidelidad',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'En SeniCare premiamos tu continuidad con cada familia. Cuantas más horas acumules con un mismo cliente, mayor porcentaje íntegro recibes:',
              style: TextStyle(fontSize: 13, color: AppTheme.slateMuted, height: 1.4),
            ),
            const SizedBox(height: 14),
            const Text('• Tramo Inicial (1 a 20 horas): 18% comisión → Recibes el 82% neto.', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text('• Tramo Continuidad (21 a 80 horas): 12% comisión → Recibes el 88% neto.', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text('• 🏆 Tramo Fidelidad (+80 horas): ¡Solo 6% de comisión! → Recibes el 94% neto.', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppTheme.secondaryColor)),
            const SizedBox(height: 8),
            const Text('• ☕ Propinas de agradecimiento: 0% comisión (100% íntegras para ti).', style: TextStyle(fontSize: 13, color: AppTheme.darkSlate)),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendido'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileAlerts(CaregiverProfile user) {
    final List<String> missingItems = [];

    final hasDefaultName = user.name == 'Sin nombre' || user.name.trim().isEmpty;
    final hasDefaultBio = user.bio.isEmpty || user.bio.startsWith('Nuevo cuidador registrado');
    final hasDefaultImage = user.imageUrl.isEmpty || user.imageUrl.contains('unsplash.com/photo-1573496359142-b8d87734a5a2');

    if (hasDefaultName) missingItems.add('Nombre completo');
    if (hasDefaultBio) missingItems.add('Biografía');
    if (hasDefaultImage) missingItems.add('Foto de perfil');
    if (user.homeAddress.trim().isEmpty) missingItems.add('Dirección');
    if (user.pricePerHour < 6.0) missingItems.add('Tarifa (mínimo 6€/h)');
    if (user.dniUrl.trim().isEmpty) missingItems.add('DNI/NIE');
    if (user.criminalRecordUrl.trim().isEmpty) missingItems.add('Antecedentes penales');
    if (user.stripeAccountId == null || user.stripeAccountId!.trim().isEmpty) {
      missingItems.add('Cuenta de cobros');
    }

    final isComplete = missingItems.isEmpty;
    final isRejected = user.verificationStatus == 'rejected';

    if (isComplete && user.verificationStatus == 'approved') {
      return const SizedBox.shrink();
    }

    final Color bgColor = isRejected
        ? Colors.red.shade50
        : (isComplete ? Colors.blue.shade50 : Colors.orange.shade50);
    final Color borderColor = isRejected
        ? Colors.red.shade300
        : (isComplete ? Colors.blue.shade200 : Colors.orange.shade300);
    final Color accentColor = isRejected
        ? Colors.red.shade800
        : (isComplete ? Colors.blue.shade800 : Colors.orange.shade900);

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isRejected
                    ? Icons.error_outline_rounded
                    : (isComplete ? Icons.hourglass_top_rounded : Icons.assignment_late_outlined),
                color: accentColor,
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isRejected
                      ? 'Verificación rechazada — Revisa tus datos'
                      : (isComplete ? 'Perfil pendiente de aprobación' : 'Completa tu perfil para trabajar'),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: accentColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isRejected
                ? 'Tu verificación de documentos necesita corrección (imagen borrosa o documento caducado). Actualiza tus datos para revisarlo de nuevo.'
                : (isComplete
                    ? 'Hemos recibido toda tu información. El equipo de SeniCare la revisará en menos de 24 horas.'
                    : 'Faltan por completar: ${missingItems.join(" • ")}.'),
            style: TextStyle(fontSize: 13, color: accentColor, height: 1.35),
          ),
          if (!isComplete || isRejected) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: isRejected ? Colors.red.shade700 : Colors.orange.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CaregiverProfileEditScreen()),
                  ).then((_) => _refreshAll());
                },
                icon: const Icon(Icons.edit_note_rounded, size: 18),
                label: Text(isRejected ? 'Revisar y Corregir Perfil' : 'Completar Perfil Ahora'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOpenDisputesAlert(BuildContext context, List<Booking> disputes, BookingNotifier bookingState) {
    final dispute = disputes.first;
    final proposedRefund = dispute.disputeAmount ?? 0.0;
    final remaining = (dispute.cost - proposedRefund).clamp(0.0, dispute.cost);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.gavel_rounded, color: Colors.red.shade800, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Incidencia abierta (${disputes.length})',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Colors.red.shade900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'El cliente propone un reembolso de ${proposedRefund.toStringAsFixed(2)} € (recibirías ${remaining.toStringAsFixed(2)} € brutos menos comisión). Tienes 24h para responder:',
            style: TextStyle(fontSize: 12.5, color: Colors.red.shade900, height: 1.35),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final confirm = await CustomDialog.showConfirmation(
                      context,
                      title: 'Escalar a Mediación',
                      message: 'Si rechazas, el equipo de Administración de SeniCare mediará en el caso. ¿Continuar?',
                      confirmText: 'Escalar',
                      isDestructive: true,
                    );
                    if (confirm == true) {
                      await bookingState.escalateDispute(dispute.id);
                      if (context.mounted) {
                        CustomSnackBar.show(context, message: 'Incidencia escalada a Administración.', type: SnackBarType.info);
                      }
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade800,
                    side: BorderSide(color: Colors.red.shade300),
                  ),
                  child: const Text('Rechazar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () async {
                    final confirm = await CustomDialog.showConfirmation(
                      context,
                      title: 'Aceptar Acuerdo',
                      message: 'Se aplicará el ajuste pactado y se liberará tu pago restante de inmediato. ¿Confirmar?',
                      confirmText: 'Aceptar',
                    );
                    if (confirm == true) {
                      try {
                        await bookingState.acceptDisputeProposal(dispute.id);
                        if (context.mounted) {
                          CustomSnackBar.show(context, message: 'Acuerdo aceptado. Pago en proceso.', type: SnackBarType.success);
                        }
                      } catch (e) {
                        if (context.mounted) {
                          CustomSnackBar.show(context, message: 'Error al procesar acuerdo: $e', type: SnackBarType.error);
                        }
                      }
                    }
                  },
                  style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                  child: const Text('Aceptar Acuerdo'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNextServiceCard(BuildContext context, Booking nextService, BookingNotifier bookingState) {
    return Card(
      color: AppTheme.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '📅 ${_formatFriendlyDay(nextService.day)} • ${nextService.slot}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '+${_calculateCaregiverNet(nextService).toStringAsFixed(0)} € netos',
                  style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FutureBuilder<ClientProfile?>(
              future: _getClientProfile(nextService.clientId),
              builder: (context, snapshot) {
                final profile = snapshot.data;
                final displayName = _extractFamilyName(profile, nextService.clientId);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Familia $displayName',
                            style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  clientId: nextService.clientId,
                                  caregiverId: nextService.caregiverId,
                                  caregiverName: nextService.caregiverName,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white),
                          tooltip: 'Chat con la familia',
                        ),
                      ],
                    ),
                    if (profile != null && (profile.patientDetails.isNotEmpty || profile.homeAddress.isNotEmpty)) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (profile.homeAddress.isNotEmpty)
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '📍 ${profile.homeAddress}',
                                      style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: () => _openMaps(profile.homeAddress),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.24),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.navigation_rounded, color: Colors.white, size: 12),
                                          SizedBox(width: 4),
                                          Text('Cómo llegar', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            if (profile.patientDetails.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                '🩺 Pautas: ${profile.patientDetails}',
                                style: const TextStyle(color: Colors.white, fontSize: 12.5),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            if (nextService.liveStatus != 'on_the_way') ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    HapticFeedback.mediumImpact();
                    await bookingState.markOnTheWay(nextService.id);
                    if (context.mounted) {
                      CustomSnackBar.show(
                        context,
                        message: '🚗 La familia ha recibido el aviso de que estás en camino.',
                        type: SnackBarType.success,
                      );
                    }
                  },
                  icon: const Icon(Icons.directions_car_rounded, size: 18, color: Colors.white),
                  label: const Text('🚗 Avisar: Estoy en camino'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ] else ...[
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade800,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.directions_car_rounded, color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Familia avisada: Estás en camino al domicilio',
                        style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ScannerScreen(booking: nextService)));
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 19),
                label: const Text('Fichar Llegada (QR / PIN)', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveServiceCard(BuildContext context, Booking activeService, BookingNotifier bookingState) {
    final completedTasks = activeService.careChecklist.where((t) => t.completed).length;
    final totalTasks = activeService.careChecklist.length;
    final isOvertime = activeService.isExpired;

    return Card(
      color: const Color(0xFF0F4C3A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isOvertime ? Colors.orange.shade700 : Colors.greenAccent.shade700,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.fiber_manual_record, color: Colors.white, size: 10),
                      const SizedBox(width: 6),
                      Text(
                        isOvertime ? 'PENDIENTE DE SALIDA' : 'EN CURSO AHORA',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${_formatFriendlyDay(activeService.day)} · ${activeService.slot}',
                  style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12.5),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FutureBuilder<ClientProfile?>(
              future: _getClientProfile(activeService.clientId),
              builder: (context, snapshot) {
                final profile = snapshot.data;
                final displayName = _extractFamilyName(profile, activeService.clientId);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Familia $displayName',
                            style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          onPressed: () => _showSosQuickModal(context, activeService, profile),
                          style: IconButton.styleFrom(backgroundColor: Colors.red.shade700),
                          icon: const Icon(Icons.sos_rounded, color: Colors.white, size: 20),
                          tooltip: 'Emergencia / 112 / Familia',
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  clientId: activeService.clientId,
                                  caregiverId: activeService.caregiverId,
                                  caregiverName: activeService.caregiverName,
                                ),
                              ),
                            );
                          },
                          style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.14)),
                          icon: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white, size: 20),
                          tooltip: 'Chat con la familia',
                        ),
                      ],
                    ),
                    if (profile != null && (profile.patientDetails.isNotEmpty || profile.homeAddress.isNotEmpty)) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (profile.homeAddress.isNotEmpty)
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '📍 ${profile.homeAddress}',
                                      style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: () => _openMaps(profile.homeAddress),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.22),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.navigation_rounded, color: Colors.white, size: 12),
                                          SizedBox(width: 4),
                                          Text('Maps', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            if (profile.patientDetails.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text('🩺 Pautas: ${profile.patientDetails}', style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            if (activeService.checkInTime != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.access_time_rounded, color: Colors.white70, size: 15),
                  const SizedBox(width: 6),
                  Text(
                    'Llegada registrada a las ${DateFormat('HH:mm').format(activeService.checkInTime!)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
            if (activeService.careChecklist.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('📋 Tareas del Cuidado', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('$completedTasks/$totalTasks hechas', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...activeService.careChecklist.map((item) => InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        bookingState.toggleChecklistTask(activeService.id, item.id);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              item.completed ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                              size: 18,
                              color: item.completed ? Colors.greenAccent : Colors.white60,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.title,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  decoration: item.completed ? TextDecoration.lineThrough : null,
                                  decorationColor: Colors.white70,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )),
                  ],
                ),
              ),
            ],
            if (activeService.careNotes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '📝 Parte diario: "${activeService.careNotes}"',
                  style: const TextStyle(color: Colors.white, fontSize: 12.5, fontStyle: FontStyle.italic),
                ),
              ),
            ],
            if (activeService.carePhotoUrls.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 68,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: activeService.carePhotoUrls.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (ctx, i) {
                    final url = activeService.carePhotoUrls[i];
                    return GestureDetector(
                      onTap: () => _showPhotoFullScreen(context, url),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          url,
                          width: 68,
                          height: 68,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 68,
                            height: 68,
                            color: Colors.white24,
                            child: const Icon(Icons.photo_rounded, color: Colors.white),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showEditCareNotesDialog(context, activeService, bookingState),
                    icon: const Icon(Icons.edit_note_rounded, size: 17, color: Colors.white),
                    label: Text(
                      activeService.careNotes.isEmpty ? 'Nota del día' : 'Editar nota',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12.5),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white60),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickAndUploadPhoto(context, activeService, bookingState),
                    icon: const Icon(Icons.add_a_photo_rounded, size: 16, color: Colors.white),
                    label: Text(
                      activeService.carePhotoUrls.isEmpty
                          ? 'Subir foto'
                          : 'Foto (${activeService.carePhotoUrls.length})',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12.5),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white60),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
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
                    await bookingState.completeService(activeService.id);
                    if (context.mounted) {
                      CustomSnackBar.show(context, message: '🎉 ¡Servicio finalizado con éxito! Buen descanso.', type: SnackBarType.success);
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.green.shade900,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
                label: const Text('🏁 Finalizar Servicio y Salir', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditCareNotesDialog(
    BuildContext context,
    Booking b,
    BookingNotifier state,
  ) async {
    final ctrl = TextEditingController(text: b.careNotes);
    try {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('📝 Resumen del Cuidado'),
          content: TextField(
            controller: ctrl,
            maxLines: 4,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Cómo se encuentra el familiar hoy, comidas, estado de ánimo...',
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
                CustomSnackBar.show(context, message: '📝 Parte diario guardado.', type: SnackBarType.success);
              },
              child: const Text('Guardar Nota'),
            ),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }
  }

  void _showPhotoFullScreen(BuildContext context, String photoUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: InteractiveViewer(
            child: Image.network(photoUrl, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  void _showSosQuickModal(BuildContext context, Booking booking, ClientProfile? profile) {
    HapticFeedback.heavyImpact();
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
                    child: Icon(Icons.sos_rounded, color: Colors.red.shade700, size: 28),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Emergencia en Domicilio', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        Text('Llamada rápida y pautas médicas activas', style: TextStyle(fontSize: 12.5, color: AppTheme.slateMuted)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (profile != null) ...[
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
                        '📍 Domicilio: ${profile.homeAddress.isNotEmpty ? profile.homeAddress : "No especificado"}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      if (profile.patientDetails.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          '🩺 Pautas médicas: ${profile.patientDetails}',
                          style: const TextStyle(fontSize: 12.5, color: AppTheme.darkSlate),
                        ),
                      ],
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.local_hospital_rounded),
                  label: const Text('Llamar al 112 (Emergencias Médicas)', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              if (profile != null && profile.phone.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final uri = Uri.parse('tel:${profile.phone}');
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.phone_in_talk_rounded),
                    label: Text('Llamar a la Familia (${profile.phone})', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openMaps(String address) async {
    if (address.isEmpty) return;
    final query = Uri.encodeComponent(address);
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildIncomingRequestsBanner(BuildContext context, List<Booking> requests, BookingNotifier bookingState) {
    final visibleRequests = _showAllRequests ? requests : requests.take(2).toList();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.shade300, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.amber.shade100,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                Icon(Icons.notifications_active_rounded, color: Colors.amber.shade900, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tienes ${requests.length} solicitud${requests.length > 1 ? "es" : ""} por responder',
                    style: TextStyle(
                      color: Colors.amber.shade900,
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...visibleRequests.map((req) {
                  return FutureBuilder<ClientProfile?>(
                    future: _getClientProfile(req.clientId),
                    builder: (context, snap) {
                      final profile = snap.data;
                      final displayName = _extractFamilyName(profile, req.clientId);
                      final payout = _calculateCaregiverNet(req);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    'Familia $displayName',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '+${payout.toStringAsFixed(1)} € netos',
                                    style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '📅 ${_formatFriendlyDay(req.day)} · ⏰ ${req.slot}',
                              style: const TextStyle(fontSize: 12.5, color: AppTheme.darkSlate),
                            ),
                            if (profile != null && profile.homeAddress.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                '📍 ${profile.homeAddress}',
                                style: const TextStyle(fontSize: 12, color: AppTheme.slateMuted),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () async {
                                      final confirm = await CustomDialog.showConfirmation(
                                        context,
                                        title: 'Rechazar Solicitud',
                                        message: '¿Seguro que deseas rechazar este servicio?',
                                        confirmText: 'Rechazar',
                                        isDestructive: true,
                                      );
                                      if (confirm == true) {
                                        await bookingState.rejectBooking(req.id);
                                        if (context.mounted) {
                                          CustomSnackBar.show(context, message: 'Solicitud rechazada.', type: SnackBarType.info);
                                        }
                                      }
                                    },
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red.shade700,
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      minimumSize: const Size(0, 36),
                                      side: BorderSide(color: Colors.red.shade200),
                                    ),
                                    child: const Text('Rechazar', style: TextStyle(fontSize: 12.5)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: FilledButton.icon(
                                    onPressed: () async {
                                      HapticFeedback.mediumImpact();
                                      await bookingState.confirmBooking(req.id);
                                      if (context.mounted) {
                                        CustomSnackBar.show(
                                          context,
                                          message: '✅ ¡Servicio aceptado! Recuerda registrar tu llegada al domicilio.',
                                          type: SnackBarType.success,
                                        );
                                      }
                                    },
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppTheme.primary,
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      minimumSize: const Size(0, 36),
                                    ),
                                    icon: const Icon(Icons.check_rounded, size: 16),
                                    label: const Text('Aceptar Servicio', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  );
                }),
                if (requests.length > 2)
                  Center(
                    child: TextButton.icon(
                      onPressed: () => setState(() => _showAllRequests = !_showAllRequests),
                      icon: Icon(_showAllRequests ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18),
                      label: Text(
                        _showAllRequests
                            ? 'Mostrar menos'
                            : 'Ver las ${requests.length} solicitudes pendientes',
                        style: TextStyle(color: Colors.amber.shade900, fontWeight: FontWeight.bold, fontSize: 12.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndUploadPhoto(
    BuildContext context,
    Booking b,
    BookingNotifier bookingState,
  ) async {
    HapticFeedback.selectionClick();
    final uploaderUid =
        context.read<AuthNotifier>().currentUserId ?? b.caregiverId;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('📸 Foto-Momento de Tranquilidad', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text(
                'Comparte una foto real del cuidado o paseo para dar tranquilidad a la familia.',
                style: TextStyle(fontSize: 13, color: AppTheme.slateMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded, color: AppTheme.primary),
                title: const Text('Hacer foto con la cámara'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: AppTheme.primary),
                title: const Text('Elegir de la galería'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source, imageQuality: 75);
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      final ref = FirebaseStorage.instance
          .ref()
          .child('care_journal/${b.id}/${DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref.putData(
        bytes,
        SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {
            'uploaderUid': uploaderUid,
            'clientId': b.clientId,
            'caregiverId': b.caregiverId,
          },
        ),
      );
      final String photoUrl = await ref.getDownloadURL();

      await bookingState.addCarePhotoUrl(b.id, photoUrl);
      if (context.mounted) {
        CustomSnackBar.show(
          context,
          message: '📸 ¡Foto subida al Diario del Cuidado! La familia ya puede verla.',
          type: SnackBarType.success,
        );
      }
    } catch (e) {
      if (context.mounted) {
        CustomSnackBar.show(
          context,
          message: 'No se pudo subir la foto. Comprueba tu conexión e inténtalo de nuevo.',
          type: SnackBarType.error,
        );
      }
    }
  }
}
