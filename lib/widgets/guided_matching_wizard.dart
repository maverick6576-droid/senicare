import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../models/models.dart';

class GuidedMatchingWizard extends StatefulWidget {
  final List<CaregiverProfile> caregivers;
  final ValueChanged<CaregiverProfile> onSelectCaregiver;
  final void Function(Set<String> specialties, double maxRate)? onApplyFilters;

  const GuidedMatchingWizard({
    super.key,
    required this.caregivers,
    required this.onSelectCaregiver,
    this.onApplyFilters,
  });

  static Future<void> show(
    BuildContext context, {
    required List<CaregiverProfile> caregivers,
    required ValueChanged<CaregiverProfile> onSelectCaregiver,
    void Function(Set<String> specialties, double maxRate)? onApplyFilters,
  }) {
    HapticFeedback.mediumImpact();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GuidedMatchingWizard(
        caregivers: caregivers,
        onSelectCaregiver: onSelectCaregiver,
        onApplyFilters: onApplyFilters,
      ),
    );
  }

  @override
  State<GuidedMatchingWizard> createState() => _GuidedMatchingWizardState();
}

class _GuidedMatchingWizardState extends State<GuidedMatchingWizard> {
  int _step = 0; // 0: Familiar, 1: Necesidades, 2: Presupuesto, 3: Resultados
  String _elderRelation = 'Mi madre / abuela';
  String _mobilityLevel = 'Autónoma con supervisión';
  final Set<String> _selectedNeeds = {'Acompañamiento'};
  double _maxHourlyRate = 22.0;
  bool _prioritizeSuperCaregivers = true;

  static const List<Map<String, dynamic>> _relations = [
    {'label': 'Mi madre / abuela', 'icon': Icons.elderly_woman_rounded},
    {'label': 'Mi padre / abuelo', 'icon': Icons.elderly_rounded},
    {'label': 'Matrimonio mayor', 'icon': Icons.people_alt_rounded},
    {'label': 'Otro familiar', 'icon': Icons.favorite_rounded},
  ];

  static const List<String> _mobilityLevels = [
    'Autónoma con supervisión',
    'Movilidad reducida (bastón / andador)',
    'Silla de ruedas / Dependencia alta',
  ];

  static const List<Map<String, String>> _needsCatalog = [
    {'label': 'Acompañamiento', 'emoji': '💛', 'spec': 'Acompañamiento'},
    {'label': 'Control de medicación', 'emoji': '💊', 'spec': 'Control de medicación'},
    {'label': 'Alzheimer / Demencia', 'emoji': '🧠', 'spec': 'Alzheimer'},
    {'label': 'Movilidad reducida', 'emoji': '🦯', 'spec': 'Movilidad reducida'},
    {'label': 'Paseos y recados', 'emoji': '🚶', 'spec': 'Acompañamiento'},
    {'label': 'Cuidado nocturno', 'emoji': '🌙', 'spec': 'Cuidado nocturno'},
  ];

  List<MapEntry<CaregiverProfile, int>> _computeTopMatches() {
    final scored = <MapEntry<CaregiverProfile, int>>[];
    for (final c in widget.caregivers) {
      int score = 78;
      if (c.pricePerHour <= _maxHourlyRate) {
        score += 8;
      } else {
        score -= 10;
      }
      if (c.isSuperCaregiver) {
        score += _prioritizeSuperCaregivers ? 7 : 4;
      }
      if (c.verified) score += 3;

      for (final need in _selectedNeeds) {
        final mappedSpec = _needsCatalog
            .firstWhere((e) => e['label'] == need, orElse: () => {'spec': need})['spec']!;
        if (c.specialties.any((s) => s.toLowerCase().contains(mappedSpec.toLowerCase())) ||
            c.title.toLowerCase().contains(mappedSpec.toLowerCase()) ||
            c.bio.toLowerCase().contains(mappedSpec.toLowerCase())) {
          score += 5;
        }
      }

      if (_mobilityLevel.contains('Silla') &&
          c.specialties.any((s) => s.toLowerCase().contains('movilidad'))) {
        score += 4;
      }

      score = score.clamp(82, 99);
      scored.add(MapEntry(c, score));
    }

    scored.sort((a, b) {
      final cmp = b.value.compareTo(a.value);
      if (cmp != 0) return cmp;
      return b.key.rating.compareTo(a.key.rating);
    });

    return scored.take(3).toList();
  }

  void _nextStep() {
    HapticFeedback.selectionClick();
    if (_step < 3) {
      setState(() => _step++);
    }
  }

  void _prevStep() {
    HapticFeedback.selectionClick();
    if (_step > 0) {
      setState(() => _step--);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: AppTheme.primaryColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _step == 3
                              ? 'Tus 3 cuidadores ideales'
                              : 'Asistente de Cuidado Ideal',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          _step == 3
                              ? 'Seleccionados para $_elderRelation'
                              : 'Paso ${_step + 1} de 3 · Respuesta en 30 segundos',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: (_step + 1) / 4,
                  minHeight: 6,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: _buildCurrentStep(),
              ),
            ),
            if (_step < 3)
              Container(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  children: [
                    if (_step > 0) ...[
                      OutlinedButton(
                        onPressed: _prevStep,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('Atrás'),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _nextStep,
                        icon: Icon(
                          _step == 2 ? Icons.insights_rounded : Icons.arrow_forward_rounded,
                          size: 18,
                        ),
                        label: Text(
                          _step == 2 ? 'Ver cuidadores compatibles' : 'Continuar',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
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

  Widget _buildCurrentStep() {
    switch (_step) {
      case 0:
        return _buildStep1();
      case 1:
        return _buildStep2();
      case 2:
        return _buildStep3();
      default:
        return _buildResultsStep();
    }
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '1. ¿Para quién buscas acompañamiento o cuidado?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.3,
          children: _relations.map((item) {
            final label = item['label'] as String;
            final icon = item['icon'] as IconData;
            final selected = _elderRelation == label;
            return InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _elderRelation = label);
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: selected
                      ? AppTheme.primaryColor.withValues(alpha: 0.1)
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? AppTheme.primaryColor : Colors.grey.shade300,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      color: selected ? AppTheme.primaryColor : AppTheme.textSecondary,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                          color: selected ? AppTheme.primaryColor : AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 22),
        const Text(
          'Nivel de movilidad actual',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        ..._mobilityLevels.map((level) {
          final selected = _mobilityLevel == level;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _mobilityLevel = level);
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: selected
                      ? AppTheme.primaryColor.withValues(alpha: 0.08)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? AppTheme.primaryColor : Colors.grey.shade300,
                    width: selected ? 1.8 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: selected ? AppTheme.primaryColor : Colors.grey,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        level,
                        style: TextStyle(
                          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '2. ¿Qué apoyo necesita principalmente?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'Puedes seleccionar varias opciones para afinar la compatibilidad.',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _needsCatalog.map((need) {
            final label = need['label']!;
            final emoji = need['emoji']!;
            final selected = _selectedNeeds.contains(label);
            return FilterChip(
              selected: selected,
              showCheckmark: false,
              avatar: Text(emoji, style: const TextStyle(fontSize: 16)),
              label: Text(
                label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  color: selected ? AppTheme.primaryColor : AppTheme.textPrimary,
                ),
              ),
              selectedColor: AppTheme.primaryColor.withValues(alpha: 0.14),
              backgroundColor: Colors.grey.shade100,
              side: BorderSide(
                color: selected ? AppTheme.primaryColor : Colors.grey.shade300,
                width: selected ? 1.5 : 1,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              onSelected: (val) {
                HapticFeedback.selectionClick();
                setState(() {
                  if (val) {
                    _selectedNeeds.add(label);
                  } else if (_selectedNeeds.length > 1) {
                    _selectedNeeds.remove(label);
                  }
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '3. Presupuesto máximo por hora',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Hasta ${_maxHourlyRate.toInt()} €/h',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primaryColor,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Slider(
          value: _maxHourlyRate,
          min: 12,
          max: 30,
          divisions: 18,
          activeColor: AppTheme.primaryColor,
          label: '${_maxHourlyRate.toInt()} €/h',
          onChanged: (val) {
            setState(() => _maxHourlyRate = val);
          },
        ),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('12 €/h (Estándar)', style: TextStyle(fontSize: 12, color: Colors.grey)),
            Text('30 €/h (Especializado)', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 20),
        SwitchListTile.adaptive(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.amber.shade300),
          ),
          tileColor: Colors.amber.shade50.withValues(alpha: 0.5),
          title: const Text(
            'Priorizar 🏆 Supercuidadores',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          subtitle: const Text(
            'Profesionales con valoración ≥ 4.8 y excelente tasa de familias que repiten.',
            style: TextStyle(fontSize: 12),
          ),
          value: _prioritizeSuperCaregivers,
          activeTrackColor: AppTheme.primaryColor,
          onChanged: (val) {
            HapticFeedback.selectionClick();
            setState(() => _prioritizeSuperCaregivers = val);
          },
        ),
      ],
    );
  }

  Widget _buildResultsStep() {
    final matches = _computeTopMatches();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (matches.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('No hemos encontrado cuidadores disponibles en este momento.'),
            ),
          )
        else
          ...matches.asMap().entries.map((entry) {
            final rank = entry.key + 1;
            final caregiver = entry.value.key;
            final matchPercent = entry.value.value;

            return Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: rank == 1
                    ? AppTheme.primaryColor.withValues(alpha: 0.05)
                    : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: rank == 1 ? AppTheme.primaryColor : Colors.grey.shade200,
                  width: rank == 1 ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(
                          caregiver.imageUrl,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 64,
                            height: 64,
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.person, size: 32),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppTheme.secondaryColor.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$matchPercent% compatible',
                                    style: const TextStyle(
                                      color: AppTheme.secondaryColor,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                if (caregiver.isSuperCaregiver)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      '🏆 Supercuidador',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              caregiver.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              '⭐ ${caregiver.rating.toStringAsFixed(1)} (${caregiver.reviewsCount}) · 🔄 ${caregiver.retentionRate}% familias repiten',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${caregiver.pricePerHour.toStringAsFixed(0)}€',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                          const Text('/hora', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onSelectCaregiver(caregiver);
                      },
                      icon: const Icon(Icons.visibility_rounded, size: 17),
                      label: const Text('Ver perfil y agendar entrevista'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: rank == 1 ? AppTheme.primaryColor : Colors.grey.shade800,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        const SizedBox(height: 6),
        Row(
          children: [
            TextButton.icon(
              onPressed: _prevStep,
              icon: const Icon(Icons.tune_rounded, size: 16),
              label: const Text('Ajustar respuestas'),
            ),
            const Spacer(),
            if (widget.onApplyFilters != null)
              TextButton(
                onPressed: () {
                  final mappedSpecs = <String>{};
                  for (final need in _selectedNeeds) {
                    final spec = _needsCatalog.firstWhere(
                      (e) => e['label'] == need,
                      orElse: () => {'spec': need},
                    )['spec']!;
                    mappedSpecs.add(spec);
                  }
                  Navigator.pop(context);
                  widget.onApplyFilters!(mappedSpecs, _maxHourlyRate);
                },
                child: const Text('Aplicar filtros al explorador'),
              ),
          ],
        ),
      ],
    );
  }
}
