import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/widgets/widgets.dart';

class CaregiverCalendarScreen extends StatefulWidget {
  const CaregiverCalendarScreen({super.key});

  @override
  State<CaregiverCalendarScreen> createState() => _CaregiverCalendarScreenState();
}

class _CaregiverCalendarScreenState extends State<CaregiverCalendarScreen> {
  DateTime _selectedDate = DateTime.now();
  List<TimeSlot> _slots = [];
  bool _isLoading = false;
  late AuthNotifier _auth;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthNotifier>();
    _loadSlots();
  }

  String get _dateStr {
    return '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadSlots() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final slots = await DependencyInjection.caregivers
          .fetchTimeSlots(_auth.currentUserId!, _dateStr);
      slots.sort((a, b) => a.dateTime.compareTo(b.dateTime));
      if (mounted) setState(() => _slots = slots);
    } catch (e) {
      debugPrint('Error loading slots: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleSlot(TimeSlot slot, bool newValue) async {
    slot.isAvailable = newValue;
    setState(() {});
    try {
      await DependencyInjection.caregivers
          .updateTimeSlot(_auth.currentUserId!, _dateStr, slot);
    } catch (e) {
      // Revert on failure
      slot.isAvailable = !newValue;
      if (mounted) {
        setState(() {});
        CustomSnackBar.show(context, message: 'Error al guardar: $e', type: SnackBarType.error);
      }
    }
  }

  Future<void> _showRecurringDialog() async {
    int startHour = 9;
    int endHour = 18;
    int weeksAhead = 4;
    List<bool> selectedDays = List.filled(7, true); // Mon-Sun
    final daysOfWeek = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // Validate range for UI feedback
            final rangeValid = endHour > startHour;
            final daysSelected = selectedDays.any((d) => d);
            final canGenerate = rangeValid && daysSelected;

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                top: 20,
                left: 20,
                right: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header ──
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Configurar Horario Recurrente',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Genera tu disponibilidad para las próximas semanas de forma automática.',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 20),

                  // ── Days of week ──
                  const Text('Días que trabajas', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: List.generate(7, (index) {
                      return FilterChip(
                        label: Text(daysOfWeek[index]),
                        selected: selectedDays[index],
                        onSelected: (val) =>
                            setModalState(() => selectedDays[index] = val),
                      );
                    }),
                  ),
                  if (!daysSelected)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'Selecciona al menos un día.',
                        style: TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 20),

                  // ── Hours ──
                  const Text('Franja horaria', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Desde', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            DropdownButton<int>(
                              isExpanded: true,
                              value: startHour,
                              items: List.generate(
                                24,
                                (i) => DropdownMenuItem(
                                  value: i,
                                  child: Text('${i.toString().padLeft(2, '0')}:00'),
                                ),
                              ),
                              onChanged: (val) => setModalState(() => startHour = val!),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Hasta', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            DropdownButton<int>(
                              isExpanded: true,
                              value: endHour,
                              items: List.generate(
                                24,
                                (i) => DropdownMenuItem(
                                  value: i,
                                  child: Text('${i.toString().padLeft(2, '0')}:00'),
                                ),
                              ),
                              onChanged: (val) => setModalState(() => endHour = val!),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (!rangeValid && daysSelected)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'La hora de fin debe ser posterior a la de inicio.',
                        style: TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    )
                  else if (rangeValid)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${endHour - startHour} hora${endHour - startHour != 1 ? 's' : ''} por día',
                        style: TextStyle(color: Colors.green.shade700, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 20),

                  // ── Weeks ahead ──
                  const Text('Cuántas semanas generar', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [1, 2, 4, 8].map((w) {
                      return ChoiceChip(
                        label: Text('$w sem.'),
                        selected: weeksAhead == w,
                        onSelected: (_) => setModalState(() => weeksAhead = w),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  // ── Generate button ──
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.autorenew),
                      label: Text(
                        'Generar ${weeksAhead * 7} días × ${rangeValid ? endHour - startHour : 0} horas/día',
                      ),
                      onPressed: canGenerate
                          ? () {
                              Navigator.pop(ctx);
                              _generateRecurringSchedule(
                                selectedDays: selectedDays,
                                startHour: startHour,
                                endHour: endHour,
                                weeksAhead: weeksAhead,
                              );
                            }
                          : null,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Generates recurring slots using batch writes with progress feedback.
  Future<void> _generateRecurringSchedule({
    required List<bool> selectedDays,
    required int startHour,
    required int endHour,
    required int weeksAhead,
  }) async {
    if (mounted) setState(() => _isLoading = true);

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final caregiverId = _auth.currentUserId!;
    final today = DateTime.now();
    final totalDays = weeksAhead * 7;
    int processedDays = 0;
    int slotsCreated = 0;

    try {
      for (int i = 0; i < totalDays; i++) {
        final targetDate = today.add(Duration(days: i));
        // weekday: 1=Mon … 7=Sun → index 0-6
        if (!selectedDays[targetDate.weekday - 1]) continue;

        final dateStr =
            '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';

        // Build the slot list for this day
        final List<TimeSlot> daySlots = [];
        for (int h = startHour; h < endHour; h++) {
          daySlots.add(TimeSlot(
            id: '$dateStr-$h',
            dateTime: DateTime(targetDate.year, targetDate.month, targetDate.day, h),
            isAvailable: true,
          ));
        }

        // 1. Clear old slots for this day (so removed hours don't linger)
        await DependencyInjection.caregivers.clearDaySlots(caregiverId, dateStr);
        // 2. Write the new slots atomically
        await DependencyInjection.caregivers.setBatchTimeSlots(caregiverId, dateStr, daySlots);

        processedDays++;
        slotsCreated += daySlots.length;
      }

      scaffoldMessenger.showSnackBar(SnackBar(
        content: Text(
          '✅ Horario generado: $processedDays días, $slotsCreated franjas en total.',
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
      ));
    } catch (e) {
      debugPrint('Error generating recurring schedule: $e');
      scaffoldMessenger.showSnackBar(SnackBar(
        content: Text(
          'Error al generar el horario: $e\n'
          'Se han guardado $processedDays días antes del fallo.',
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 6),
      ));
    } finally {
      // Reload current day's slots to reflect any changes
      await _loadSlots();
    }
  }

  Future<void> _createSingleDaySlots(int startHour, int endHour) async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final caregiverId = _auth.currentUserId!;
      final List<TimeSlot> daySlots = [];
      for (int h = startHour; h < endHour; h++) {
        daySlots.add(TimeSlot(
          id: '$_dateStr-$h',
          dateTime: DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, h),
          isAvailable: true,
        ));
      }
      await DependencyInjection.caregivers.clearDaySlots(caregiverId, _dateStr);
      await DependencyInjection.caregivers.setBatchTimeSlots(caregiverId, _dateStr, daySlots);
      await _loadSlots();
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: '✅ Horarios activados para este día. Puedes encender o apagar cada hora.',
          type: SnackBarType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(context, message: 'Error al crear horarios: $e', type: SnackBarType.error);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<ConfigNotifier>();
    final fontMult = config.seniorMode ? 1.2 : 1.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Calendario de Horarios'),
        actions: [
          if (_slots.isNotEmpty)
            TextButton.icon(
              onPressed: _isLoading
                  ? null
                  : () async {
                      setState(() => _isLoading = true);
                      await DependencyInjection.caregivers.clearDaySlots(_auth.currentUserId!, _dateStr);
                      await _loadSlots();
                    },
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
              label: const Text('Vaciar día', style: TextStyle(color: Colors.red)),
            ),
        ],
      ),
      body: Column(
        children: [
          CalendarDatePicker(
            initialDate: _selectedDate,
            firstDate: DateTime.now().subtract(const Duration(days: 1)),
            lastDate: DateTime.now().add(const Duration(days: 90)),
            onDateChanged: (date) {
              setState(() => _selectedDate = date);
              _loadSlots();
            },
          ),
          const Divider(height: 1),
          // Progress indicator while loading or generating
          if (_isLoading) const LinearProgressIndicator(),
          Expanded(
            child: _isLoading && _slots.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _slots.isEmpty
                    ? Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.event_available_rounded,
                                  size: 46, color: AppTheme.primary.withValues(alpha: 0.6)),
                              const SizedBox(height: 10),
                              Text(
                                'Sin horarios activados en este día',
                                style: TextStyle(
                                    color: AppTheme.darkSlate,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16 * fontMult),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Pulsa un botón abajo para abrir horas solo hoy, o usa "Repetir Varias Semanas" si tienes un horario fijo.',
                                style: TextStyle(
                                    color: AppTheme.slateMuted,
                                    fontSize: 13 * fontMult),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                alignment: WrapAlignment.center,
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: _isLoading ? null : () => _createSingleDaySlots(9, 18),
                                    icon: const Icon(Icons.wb_sunny_outlined, size: 18),
                                    label: const Text('Abrir este día (09:00 - 18:00)'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _isLoading ? null : () => _createSingleDaySlots(8, 22),
                                    icon: const Icon(Icons.schedule, size: 18),
                                    label: const Text('Jornada completa (08:00 - 22:00)'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _slots.length,
                        itemBuilder: (context, index) {
                          final slot = _slots[index];
                          final endHour = (slot.dateTime.hour + 1) % 24;
                          final timeStr =
                              '${slot.dateTime.hour.toString().padLeft(2, '0')}:00 — ${endHour.toString().padLeft(2, '0')}:00';
                          return SwitchListTile(
                            title: Text(timeStr,
                                style: TextStyle(fontSize: 16 * fontMult)),
                            subtitle: Text(
                              slot.isAvailable
                                  ? 'Disponible'
                                  : 'Bloqueado / Ocupado',
                              style: TextStyle(
                                color: slot.isAvailable
                                    ? Colors.green.shade700
                                    : Colors.red.shade400,
                              ),
                            ),
                            value: slot.isAvailable,
                            onChanged: _isLoading
                                ? null
                                : (val) => _toggleSlot(slot, val),
                            activeThumbColor: AppTheme.primary,
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading ? null : _showRecurringDialog,
        icon: const Icon(Icons.autorenew),
        label: const Text('Horario Recurrente'),
        backgroundColor: _isLoading ? Colors.grey : AppTheme.primary,
      ),
    );
  }
}
