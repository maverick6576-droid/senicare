import 'package:flutter/material.dart';
import '../core/core.dart';
import '../models/booking.dart';
import '../models/client_profile.dart';

/// Tarjeta desplegable reutilizable con la información básica del cuidado para cuidadores.
/// Se utiliza tanto en solicitudes pendientes del Inicio como en la pestaña Reservas.
class CareBasicInfoCard extends StatefulWidget {
  final Booking booking;
  final ClientProfile? clientProfile;
  final bool isLoadingClient;
  final bool initiallyExpanded;
  final bool seniorMode;
  final bool showDirectionsButton;
  final VoidCallback? onOpenMaps;

  const CareBasicInfoCard({
    super.key,
    required this.booking,
    required this.clientProfile,
    this.isLoadingClient = false,
    this.initiallyExpanded = false,
    this.seniorMode = false,
    this.showDirectionsButton = false,
    this.onOpenMaps,
  });

  @override
  State<CareBasicInfoCard> createState() => _CareBasicInfoCardState();
}

class _CareBasicInfoCardState extends State<CareBasicInfoCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  List<String> _resolveChecklistTitles(ClientProfile? profile) {
    if (widget.booking.careChecklist.isNotEmpty) {
      return widget.booking.careChecklist
          .map((e) => e.title.trim())
          .where((t) => t.isNotEmpty)
          .toList();
    }
    if (profile != null && profile.defaultCareChecklist.isNotEmpty) {
      return profile.defaultCareChecklist
          .map((e) => e.trim())
          .where((t) => t.isNotEmpty)
          .toList();
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.clientProfile;
    final checklist = _resolveChecklistTitles(profile);
    final hasAnyDetail = profile != null &&
        (profile.careRecipientName.trim().isNotEmpty ||
            profile.mobilityLevel.trim().isNotEmpty ||
            profile.cognitiveNeeds.trim().isNotEmpty ||
            profile.dietNotes.trim().isNotEmpty ||
            profile.patientDetails.trim().isNotEmpty ||
            profile.homeAddress.trim().isNotEmpty ||
            profile.homeAccessNotes.trim().isNotEmpty ||
            profile.emergencyPhone.trim().isNotEmpty ||
            checklist.isNotEmpty);

    final titleSize = widget.seniorMode ? 14.5 : 13.0;
    final bodySize = widget.seniorMode ? 13.5 : 12.5;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: Key('toggle_care_info_${widget.booking.id}'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.medical_information_rounded,
                    size: 18,
                    color: Colors.amber.shade900,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Información básica del cuidado',
                          style: TextStyle(
                            fontSize: titleSize,
                            fontWeight: FontWeight.w800,
                            color: Colors.amber.shade900,
                          ),
                        ),
                        if (!_expanded && profile != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            _buildCollapsedHint(profile, checklist.length),
                            style: TextStyle(
                              fontSize: bodySize - 0.5,
                              color: AppTheme.slateMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _expanded ? 'Ocultar' : 'Desplegar',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.amber.shade900,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          _expanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 16,
                          color: Colors.amber.shade900,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(height: 1, color: Colors.amber.shade200),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: widget.isLoadingClient && profile == null
                  ? Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Cargando información del cuidado...',
                          style: TextStyle(
                            fontSize: bodySize,
                            color: AppTheme.slateMuted,
                          ),
                        ),
                      ],
                    )
                  : !hasAnyDetail && checklist.isEmpty
                      ? Text(
                          'La familia aún no ha completado detalles adicionales del cuidado en su ficha.',
                          style: TextStyle(
                            fontSize: bodySize,
                            color: AppTheme.slateMuted,
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (profile != null &&
                                profile.careRecipientName.trim().isNotEmpty)
                              _InfoRow(
                                icon: Icons.person_outline_rounded,
                                label: 'Persona a cuidar',
                                value: profile.careRecipientName.trim(),
                                fontSize: bodySize,
                              ),
                            if (profile != null &&
                                profile.mobilityLevel.trim().isNotEmpty)
                              _InfoRow(
                                icon: Icons.accessible_forward_rounded,
                                label: 'Movilidad',
                                value: profile.mobilityLevel.trim(),
                                fontSize: bodySize,
                              ),
                            if (profile != null &&
                                profile.cognitiveNeeds.trim().isNotEmpty)
                              _InfoRow(
                                icon: Icons.psychology_outlined,
                                label: 'Cognición y comunicación',
                                value: profile.cognitiveNeeds.trim(),
                                fontSize: bodySize,
                              ),
                            if (profile != null &&
                                profile.dietNotes.trim().isNotEmpty)
                              _InfoRow(
                                icon: Icons.restaurant_outlined,
                                label: 'Alimentación y dieta',
                                value: profile.dietNotes.trim(),
                                fontSize: bodySize,
                              ),
                            if (profile != null &&
                                profile.patientDetails.trim().isNotEmpty)
                              _InfoRow(
                                icon: Icons.description_outlined,
                                label: 'Pautas y necesidades',
                                value: profile.patientDetails.trim(),
                                fontSize: bodySize,
                              ),
                            if (profile != null &&
                                profile.homeAddress.trim().isNotEmpty)
                              _InfoRow(
                                icon: Icons.location_on_outlined,
                                label: 'Domicilio',
                                value: profile.homeAddress.trim(),
                                fontSize: bodySize,
                              ),
                            if (profile != null &&
                                profile.homeAccessNotes.trim().isNotEmpty)
                              _InfoRow(
                                icon: Icons.meeting_room_outlined,
                                label: 'Indicaciones de acceso',
                                value: profile.homeAccessNotes.trim(),
                                fontSize: bodySize,
                              ),
                            if (profile != null &&
                                profile.emergencyPhone.trim().isNotEmpty)
                              _InfoRow(
                                icon: Icons.emergency_outlined,
                                label: 'Teléfono de emergencia',
                                value: profile.emergencyPhone.trim(),
                                fontSize: bodySize,
                              ),
                            if (checklist.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Tareas del cuidado:',
                                style: TextStyle(
                                  fontSize: bodySize,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.darkSlate,
                                ),
                              ),
                              const SizedBox(height: 4),
                              ...checklist.map(
                                (task) => Padding(
                                  padding: const EdgeInsets.only(bottom: 3),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.check_circle_outline_rounded,
                                        size: 15,
                                        color: Colors.amber.shade900,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          task,
                                          style: TextStyle(
                                            fontSize: bodySize,
                                            color: AppTheme.darkSlate,
                                            height: 1.3,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            if (widget.showDirectionsButton &&
                                widget.onOpenMaps != null) ...[
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: widget.onOpenMaps,
                                  icon: const Icon(
                                    Icons.directions_rounded,
                                    size: 17,
                                  ),
                                  label: const Text(
                                    'Cómo llegar',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppTheme.primary,
                                    backgroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    minimumSize: const Size(0, 34),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      side: BorderSide(
                                        color: AppTheme.primary
                                            .withValues(alpha: 0.3),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
            ),
          ],
        ],
      ),
    );
  }

  String _buildCollapsedHint(ClientProfile profile, int taskCount) {
    final parts = <String>[];
    if (profile.careRecipientName.trim().isNotEmpty) {
      parts.add(profile.careRecipientName.trim());
    }
    if (profile.mobilityLevel.trim().isNotEmpty) {
      parts.add(profile.mobilityLevel.trim());
    }
    if (taskCount > 0) {
      parts.add('$taskCount ${taskCount == 1 ? 'tarea' : 'tareas'}');
    }
    if (parts.isEmpty) {
      return 'Pulsa para ver pautas, acceso y necesidades';
    }
    return parts.join(' · ');
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final double fontSize;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 15, color: Colors.amber.shade900),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: fontSize,
                  color: AppTheme.darkSlate,
                  height: 1.35,
                ),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
