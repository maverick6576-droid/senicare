import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:senicare/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/screens/screens.dart';
import 'package:senicare/widgets/widgets.dart';
import 'dart:math';

class CaregiverDashboard extends StatefulWidget {
  const CaregiverDashboard({super.key});

  @override
  State<CaregiverDashboard> createState() => _CaregiverDashboardState();
}

class _CaregiverDashboardState extends State<CaregiverDashboard> {
  List<Map<String, dynamic>> _clientStats = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final auth = context.read<AuthNotifier>();
    final caregiverId = auth.currentCaregiver?.id ?? auth.currentUserId ?? '';
    
    if (caregiverId.isNotEmpty) {
      final stats = await DependencyInjection.stats.getCaregiverClientStats(caregiverId);
      
      for (var stat in stats) {
        final clientId = stat['clientId'] as String?;
        if (clientId != null && clientId.isNotEmpty) {
          final profile = await DependencyInjection.clients.getClient(clientId);
          if (profile != null) {
            final nameParts = profile.name.trim().split(RegExp(r'\s+'));
            final surname = nameParts.length > 1 ? nameParts[1] : profile.name;
            stat['clientName'] = surname;
          }
        }
      }

      if (mounted) {
        setState(() {
          _clientStats = stats;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthNotifier>(context);
    final bookingState = Provider.of<BookingNotifier>(context);
    final user = auth.currentCaregiver;

    return RefreshIndicator(
      onRefresh: _loadStats,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
        if (user != null) _buildProfileAlerts(user, auth),
        Container(
          padding: const EdgeInsets.all(18),
          margin: const EdgeInsets.only(bottom: 20),
          decoration: AppTheme.modernCardDecoration(
            radius: 20,
            borderColor: AppTheme.primary.withValues(alpha: 0.2),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primarySurface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.calendar_month_rounded, color: AppTheme.primary, size: 28),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tu Disponibilidad Horaria',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.darkSlate),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Elige qué días y horas puedes trabajar.',
                      style: TextStyle(fontSize: 13, color: AppTheme.slateMuted),
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
                child: const Text('Editar Horarios', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        const Text('Resumen de Actividad', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.darkSlate)),
        const SizedBox(height: 16),
        Builder(
          builder: (context) {
            final now = DateTime.now();
            final effectiveCaregiverId = user?.id ?? auth.currentUserId ?? '';

            // Seleccionar reservas pertenecientes a este cuidador
            final caregiverBookings = bookingState.bookings.where((b) {
              if (effectiveCaregiverId.isEmpty) return false;
              return b.caregiverId == effectiveCaregiverId ||
                     b.caregiverId == auth.currentUserId ||
                     b.caregiverId == user?.id;
            }).toList();

            // Un servicio se cuenta como "Realizado" (y por tanto computa en "Cobrado") si:
            // - Está completado / valorado
            // - Su pago ha sido liberado en escrow
            // - El cuidador ha realizado el check-in presencial en el domicilio
            // - O ha transcurrido en fecha estando confirmado sin disputa/cancelación/reembolso
            final completedBookings = caregiverBookings.where((b) {
              final isReleasedEscrow = b.escrowStatus == 'released' ||
                                       b.escrowStatus == 'released_manual' ||
                                       b.escrowStatus == 'released_auto' ||
                                       b.escrowStatus == 'resolved_partial';
              final isCompletedStatus = b.status == BookingStatus.completed;
              final isCheckedIn = b.checkInTime != null;
              final isReviewed = b.isReviewed;
              final isExpiredConfirmed = b.status == BookingStatus.confirmed &&
                                         b.isExpired &&
                                         b.escrowStatus != 'refunded' &&
                                         b.escrowStatus != 'cancelled' &&
                                         b.escrowStatus != 'disputed';

              return isReleasedEscrow || isCompletedStatus || isCheckedIn || isReviewed || isExpiredConfirmed;
            }).toList();

            final servicesCount = completedBookings.length;
            final totalTips = caregiverBookings.fold(0.0, (sum, b) => sum + b.tipAmount);
            final totalIncome = completedBookings.fold(0.0, (sum, b) {
              double payout = b.caregiverPayout;
              if (payout <= 0 && b.cost > 0) {
                if (b.caregiverCommissionAmount > 0) {
                  payout = b.cost - b.caregiverCommissionAmount;
                } else {
                  final rate = b.caregiverCommissionRate > 0 ? b.caregiverCommissionRate : 0.18;
                  payout = b.cost * (1.0 - rate);
                }
              }
              return sum + payout + b.tipAmount;
            });

            final inProgressBookings = caregiverBookings.where((b) {
              return b.status == BookingStatus.confirmed &&
                     b.checkInTime != null &&
                     b.liveStatus != 'completed' &&
                     !b.isExpired;
            }).toList();
            inProgressBookings.sort((a, b) => a.day.compareTo(b.day) != 0 ? a.day.compareTo(b.day) : a.slot.compareTo(b.slot));
            final activeService = inProgressBookings.isNotEmpty ? inProgressBookings.first : null;

            final pendingBookings = caregiverBookings.where((b) {
              if (b.status != BookingStatus.confirmed || b.checkInTime != null || b.isExpired) return false;
              try {
                final dayParts = b.day.contains('/') ? b.day.split('/') : b.day.split('-');
                final year = int.parse(dayParts[b.day.contains('/') ? 2 : 0]);
                final month = int.parse(dayParts[1]);
                final day = int.parse(dayParts[b.day.contains('/') ? 0 : 2]);
                final endStr = b.slot.split('-')[1].split(':');
                final endTime = DateTime(year, month, day, int.parse(endStr[0]), int.parse(endStr[1]));
                if (now.isAfter(endTime)) return false;
              } catch (_) {}
              return true;
            }).toList();
            pendingBookings.sort((a, b) => a.day.compareTo(b.day) != 0 ? a.day.compareTo(b.day) : a.slot.compareTo(b.slot));
            final nextService = pendingBookings.isNotEmpty ? pendingBookings.first : null;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: StatCard(title: 'Cobrado', value: '${totalIncome.toStringAsFixed(2)} €', icon: Icons.euro, color: Colors.green)),
                    const SizedBox(width: 16),
                    Expanded(child: StatCard(title: 'Realizado', value: servicesCount.toString(), icon: Icons.check_circle, color: Colors.blue)),
                  ],
                ),
                if (totalTips > 0) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      children: [
                        const Text('☕', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Propinas de agradecimiento recibidas (100% íntegras para ti): +${totalTips.toStringAsFixed(0)} €',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.amber.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                if (activeService != null) ...[
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.green),
                      ),
                      const SizedBox(width: 8),
                      const Text('Servicio en Curso', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildActiveServiceCard(context, activeService, bookingState),
                ] else ...[
                  const Text('Próximo Servicio', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  if (nextService == null)
                    const Text('No tienes servicios pendientes.', style: TextStyle(color: Colors.grey))
                  else
                    _buildNextServiceCard(context, nextService, bookingState),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text('Mis Clientes y Comisiones', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.darkSlate)),
            ),
            TextButton.icon(
              onPressed: () => _showCommissionTiersModal(context),
              icon: const Icon(Icons.info_outline_rounded, size: 17),
              label: const Text('Ver Tramos (18%→6%)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_isLoading)
          const Center(child: CircularProgressIndicator())
        else if (_clientStats.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppTheme.modernCardDecoration(),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '📉 Programa de Fidelidad: ¡Cuanto más cuidas a una familia, menos comisión pagas!',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppTheme.darkSlate),
                ),
                SizedBox(height: 8),
                Text('• De 1 a 20h con una familia: 18% comisión (cobras el 82%)', style: TextStyle(fontSize: 12.5, color: AppTheme.slateMuted)),
                SizedBox(height: 4),
                Text('• De 21 a 80h con la misma familia: 12% comisión (cobras el 88%)', style: TextStyle(fontSize: 12.5, color: AppTheme.slateMuted)),
                SizedBox(height: 4),
                Text('• Más de 80h acumuladas: ¡Solo 6% de comisión! (cobras el 94%)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppTheme.secondaryColor)),
              ],
            ),
          )
        else
          ..._clientStats.map((stat) {
            final hours = stat['accumulatedHours'] as int? ?? 0;
            final clientName = stat['clientName'] as String? ?? 'Familia Desconocida';
            
            double nextTierHours = 20.0;
            double currentRate = 18.0;
            if (hours > 20 && hours <= 80) {
              nextTierHours = 80.0;
              currentRate = 12.0;
            } else if (hours > 80) {
              nextTierHours = 80.0; // max tier
              currentRate = 6.0;
            }

            final progress = hours >= 80 ? 1.0 : (hours / nextTierHours);

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text('Familia: $clientName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                          child: Text('Comisión: ${currentRate.toInt()}% (Cobras ${(100 - currentRate.toInt())}%)', style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 12)),
                        )
                      ],
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.grey.shade200,
                      color: AppTheme.primary,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      hours >= 80 
                        ? '🏆 $hours horas acumuladas. ¡Tienes la Tarifa Fidelidad mínima (6% comisión)!'
                        : '$hours h acumuladas — Te faltan ${(nextTierHours.toInt() - hours).clamp(1, 80)} h con esta familia para bajar al ${hours <= 20 ? "12%" : "6%"} de comisión.',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    )
                  ],
                ),
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

  Widget _buildProfileAlerts(CaregiverProfile user, AuthNotifier auth) {
    final List<String> missingItems = [];
    
    final hasDefaultName = user.name == 'Sin nombre' || user.name.trim().isEmpty;
    final hasDefaultBio = user.bio.isEmpty || user.bio.startsWith('Nuevo cuidador registrado');
    final hasDefaultImage = user.imageUrl.isEmpty || user.imageUrl.contains('unsplash.com/photo-1573496359142-b8d87734a5a2');
    
    if (hasDefaultName) missingItems.add('Nombre completo');
    if (hasDefaultBio) missingItems.add('Biografía descriptiva');
    if (hasDefaultImage) missingItems.add('Foto de perfil');
    if (user.homeAddress.trim().isEmpty) missingItems.add('Dirección de residencia');
    if (user.pricePerHour < 6.0) missingItems.add('Tarifa horaria válida (mínimo 6€/h)');
    if (user.dniUrl.trim().isEmpty) missingItems.add('Documento de identidad (DNI/NIE)');
    if (user.criminalRecordUrl.trim().isEmpty) missingItems.add('Certificado de antecedentes penales');
    if (user.stripeAccountId == null || user.stripeAccountId!.trim().isEmpty) {
      missingItems.add('Cuenta de cobros (Stripe Connect)');
    }
    
    final isComplete = missingItems.isEmpty;
    
    if (isComplete && user.verificationStatus == 'approved') {
      return const SizedBox.shrink(); // Todo correcto y aprobado
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: isComplete ? Colors.blue.shade50 : Colors.orange.shade50,
        border: Border.all(color: isComplete ? Colors.blue.shade300 : Colors.orange.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isComplete ? Icons.hourglass_top_rounded : Icons.warning_amber_rounded,
                color: isComplete ? Colors.blue.shade700 : Colors.orange.shade800,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isComplete 
                    ? 'Perfil pendiente de aprobación'
                    : 'Completa tu perfil para empezar a trabajar',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isComplete ? Colors.blue.shade900 : Colors.orange.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            isComplete
              ? 'Hemos recibido toda tu información y el equipo de SeniCare la está revisando. En menos de 24 horas tu perfil estará activo.'
              : 'Para que los clientes puedan encontrarte y contratarte, debes rellenar los siguientes datos obligatorios:',
            style: TextStyle(
              fontSize: 14,
              color: isComplete ? Colors.blue.shade800 : Colors.orange.shade800,
            ),
          ),
          if (!isComplete) ...[
            const SizedBox(height: 12),
            ...missingItems.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: Row(
                children: [
                  const Icon(Icons.close_rounded, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(item, style: TextStyle(color: Colors.grey.shade800, fontSize: 13, fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            )),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CaregiverProfileEditScreen()),
                  ).then((_) => _loadStats()); // Recargar estadísticas cuando regrese
                },
                icon: const Icon(Icons.edit_note_rounded),
                label: const Text('Completar Perfil Ahora'),
              ),
            ),
          ],
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
                  child: Builder(builder: (context) {
                    try {
                      final date = DateTime.parse(nextService.day);
                      return Text('${DateFormat('dd/MM/yyyy').format(date)}, ${nextService.slot}', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis);
                    } catch (e) {
                      final p = nextService.day.split('-');
                      final fallback = p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : nextService.day;
                      return Text('$fallback, ${nextService.slot}', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis);
                    }
                  }),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.directions_walk, color: Colors.white),
              ],
            ),
            const SizedBox(height: 12),
            FutureBuilder<ClientProfile?>(
              future: DependencyInjection.clients.getClient(nextService.clientId),
              builder: (context, snapshot) {
                final profile = snapshot.data;
                final clientName = profile?.name ?? '';
                final nameParts = clientName.trim().split(RegExp(r'\s+'));
                final surname = nameParts.length > 1 ? nameParts[1] : clientName;
                final displayName = surname.isNotEmpty ? surname : nextService.clientId.substring(0, min(5, nextService.clientId.length));
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Servicio - Familia: $displayName', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    if (profile != null && (profile.patientDetails.isNotEmpty || profile.homeAddress.isNotEmpty)) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.medical_information_rounded, color: Colors.white, size: 16),
                                SizedBox(width: 6),
                                Text(
                                  '🩺 Ficha Rápida del Paciente',
                                  style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                            if (profile.homeAddress.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                '📍 Domicilio: ${profile.homeAddress}',
                                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                              ),
                            ],
                            if (profile.patientDetails.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                '📋 Pautas: ${profile.patientDetails}',
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
                  label: const Text('🚗 Avisar a la familia: Estoy en camino'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70, width: 1.5),
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
                        '🚗 Familia avisada: Estás en camino al domicilio',
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                label: const Text('Fichar Llegada (QR / PIN)', style: TextStyle(fontWeight: FontWeight.bold)),
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
                    color: Colors.greenAccent.shade700,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.fiber_manual_record, color: Colors.white, size: 10),
                      SizedBox(width: 6),
                      Text(
                        'EN CURSO AHORA',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Text(
                  activeService.slot,
                  style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FutureBuilder<ClientProfile?>(
              future: DependencyInjection.clients.getClient(activeService.clientId),
              builder: (context, snapshot) {
                final profile = snapshot.data;
                final clientName = profile?.name ?? '';
                final nameParts = clientName.trim().split(RegExp(r'\s+'));
                final surname = nameParts.length > 1 ? nameParts[1] : clientName;
                final displayName = surname.isNotEmpty ? surname : activeService.clientId.substring(0, min(5, activeService.clientId.length));

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Familia: $displayName',
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            Navigator.push(context, MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                clientId: activeService.clientId,
                                caregiverId: activeService.caregiverId,
                                caregiverName: activeService.caregiverName,
                              ),
                            ));
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
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (profile.homeAddress.isNotEmpty)
                              Text('📍 Domicilio: ${profile.homeAddress}', style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
                            if (profile.patientDetails.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text('📋 Pautas: ${profile.patientDetails}', style: const TextStyle(color: Colors.white, fontSize: 12.5)),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.access_time_rounded, color: Colors.white70, size: 15),
                    const SizedBox(width: 6),
                    Text(
                      'Llegada registrada: ${DateFormat('HH:mm').format(activeService.checkInTime!)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
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
                        const Text('📋 Checklist de Cuidados', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('$completedTasks/$totalTasks completadas', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
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
                                  fontSize: 12.5,
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
            const SizedBox(height: 14),
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
}
