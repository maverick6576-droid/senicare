import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:senicare/models/models.dart';
import 'package:flutter/material.dart';
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
    final caregiverId = (auth.currentRole == 'caregiver' && auth.currentCaregiver == null) ? 'c1' : auth.currentUserId ?? '';
    
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
        const Text('Resumen de Actividad', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Builder(
          builder: (context) {
            final now = DateTime.now();
            final effectiveCaregiverId = user?.id ?? auth.currentUserId ?? 'c1';

            // Seleccionar reservas pertenecientes a este cuidador
            final caregiverBookings = bookingState.bookings.where((b) {
              return b.caregiverId == effectiveCaregiverId ||
                     b.caregiverId == auth.currentUserId ||
                     b.caregiverId == user?.id ||
                     b.caregiverId == 'c1';
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
            final totalIncome = completedBookings.fold(0.0, (sum, b) {
              double payout = b.caregiverPayout;
              if (payout <= 0 && b.cost > 0) {
                if (b.caregiverCommissionAmount > 0) {
                  payout = b.cost - b.caregiverCommissionAmount;
                } else {
                  payout = b.cost * 0.85; // 15% comisión por defecto si payout es 0 en datos antiguos/mock
                }
              }
              return sum + payout;
            });

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
                const SizedBox(height: 24),
                const Text('Próximo Servicio', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                if (nextService == null)
                  const Text('No tienes servicios pendientes.', style: TextStyle(color: Colors.grey))
                else
                  Card(
                    color: AppTheme.primary,
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
                                    return Text('${DateFormat('dd/MM/yyyy').format(date)}, ${nextService.slot}', style: const TextStyle(color: Colors.white70), overflow: TextOverflow.ellipsis);
                                  } catch (e) {
                                    final p = nextService.day.split('-');
                                    final fallback = p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : nextService.day;
                                    return Text('$fallback, ${nextService.slot}', style: const TextStyle(color: Colors.white70), overflow: TextOverflow.ellipsis);
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
                              final clientName = snapshot.data?.name ?? '';
                              final nameParts = clientName.trim().split(RegExp(r'\s+'));
                              final surname = nameParts.length > 1 ? nameParts[1] : clientName;
                              final displayName = surname.isNotEmpty ? surname : nextService.clientId.substring(0, min(5, nextService.clientId.length));
                              return Text('Servicio - Familia: $displayName', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold));
                            },
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => ScannerScreen(booking: nextService)));
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppTheme.primary),
                            child: const Text('Fichar Llegada'),
                          )
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        const Text('Mis Clientes y Comisiones', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        if (_isLoading)
          const Center(child: CircularProgressIndicator())
        else if (_clientStats.isEmpty)
          const Text('Aún no tienes clientes recurrentes. ¡Completa servicios para bajar tu comisión!')
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
                          child: Text('Comisión: ${currentRate.toInt()}%', style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
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
                        ? '$hours horas acumuladas. ¡Estás en la comisión mínima (6%)!'
                        : '$hours horas de ${nextTierHours.toInt()} necesarias para bajar de comisión.',
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
}
