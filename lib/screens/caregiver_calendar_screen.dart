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
  DateTime get _todayDateOnly {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime _selectedDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
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

  List<TimeSlot> get _visibleSlots {
    final now = DateTime.now();
    return _slots.where((s) => s.effectiveEndTime.isAfter(now)).toList();
  }

  String _formatHm(DateTime dt) => TimeInterval.formatHm(dt);

  String _formatTimeOfDay(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

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
        CustomSnackBar.show(
          context,
          message: UserFacingErrorMapper.toSpanishMessage(
            e,
            fallback: 'No se pudo guardar la disponibilidad.',
          ),
          type: SnackBarType.error,
        );
      }
    }
  }

  Future<void> _showAddFlexibleSlotDialog() async {
    final now = DateTime.now();
    final isToday = _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;

    // Hora inicial sugerida: si es hoy, próxima media hora desde la hora actual; si no, 09:00
    final defaultStartDt = isToday
        ? now.add(const Duration(minutes: 30))
        : DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 9, 0);
    TimeOfDay startTime = TimeOfDay(
      hour: defaultStartDt.hour.clamp(0, 22),
      minute: (defaultStartDt.minute ~/ 15) * 15,
    );
    TimeOfDay endTime = TimeOfDay(
      hour: (startTime.hour + 2).clamp(1, 23),
      minute: startTime.minute,
    );
    String? errorMsg;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final startDt = DateTime(
            _selectedDate.year,
            _selectedDate.month,
            _selectedDate.day,
            startTime.hour,
            startTime.minute,
          );
          final endDt = DateTime(
            _selectedDate.year,
            _selectedDate.month,
            _selectedDate.day,
            endTime.hour,
            endTime.minute,
          );
          final diffMin = endDt.difference(startDt).inMinutes;
          final currentNow = DateTime.now();
          final isPastStart = startDt.isBefore(currentNow);
          final isValid = diffMin >= 30 && !isPastStart;

          String validationText() {
            if (isPastStart) {
              return 'La hora de inicio debe ser posterior a la hora actual (${_formatHm(currentNow)}).';
            }
            if (diffMin < 30) {
              return 'La franja debe durar al menos 30 minutos.';
            }
            return '';
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Añadir Franja Horaria Flexible',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Elige exactamente desde qué hora hasta qué hora estás disponible ese día.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('flex_start_time_btn'),
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: ctx,
                            initialTime: startTime,
                          );
                          if (picked != null) {
                            setModalState(() {
                              startTime = picked;
                              errorMsg = null;
                            });
                          }
                        },
                        icon: const Icon(Icons.login_rounded, size: 18),
                        label: Text('Inicio: ${_formatTimeOfDay(startTime)}'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('flex_end_time_btn'),
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: ctx,
                            initialTime: endTime,
                          );
                          if (picked != null) {
                            setModalState(() {
                              endTime = picked;
                              errorMsg = null;
                            });
                          }
                        },
                        icon: const Icon(Icons.logout_rounded, size: 18),
                        label: Text('Fin: ${_formatTimeOfDay(endTime)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (!isValid || errorMsg != null)
                  Text(
                    errorMsg ?? validationText(),
                    style: const TextStyle(color: Colors.red, fontSize: 12.5),
                  )
                else
                  Text(
                    'Duración: ${TimeInterval(start: startDt, end: endDt).formattedDuration}',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('confirm_flex_slot_btn'),
                    onPressed: isValid
                        ? () async {
                            Navigator.pop(ctx);
                            final tagStart =
                                '${startDt.hour.toString().padLeft(2, '0')}${startDt.minute.toString().padLeft(2, '0')}';
                            final tagEnd =
                                '${endDt.hour.toString().padLeft(2, '0')}${endDt.minute.toString().padLeft(2, '0')}';
                            final newSlot = TimeSlot(
                              id: 'flex_${_dateStr}_${tagStart}_$tagEnd',
                              dateTime: startDt,
                              endTime: endDt,
                              isAvailable: true,
                            );
                            await DependencyInjection.caregivers.updateTimeSlot(
                              _auth.currentUserId!,
                              _dateStr,
                              newSlot,
                            );
                            await _loadSlots();
                            if (mounted) {
                              CustomSnackBar.show(
                                context,
                                message:
                                    '✅ Franja ${_formatHm(startDt)} - ${_formatHm(endDt)} añadida.',
                                type: SnackBarType.success,
                              );
                            }
                          }
                        : null,
                    icon: const Icon(Icons.add_alarm_rounded),
                    label: const Text('Guardar franja disponible'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showRecurringDialog() async {
    TimeOfDay startTime = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 18, minute: 0);
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
            final startMins = startTime.hour * 60 + startTime.minute;
            final endMins = endTime.hour * 60 + endTime.minute;
            final diffMins = endMins - startMins;
            final rangeValid = diffMins >= 30;
            final daysSelected = selectedDays.any((d) => d);
            final canGenerate = rangeValid && daysSelected;

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                top: 20,
                left: 20,
                right: 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
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
                      'Genera tu disponibilidad con franjas flexibles para las próximas semanas.',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 20),
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
                    const Text('Franja horaria flexible', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await showTimePicker(
                                context: ctx,
                                initialTime: startTime,
                              );
                              if (picked != null) {
                                setModalState(() => startTime = picked);
                              }
                            },
                            icon: const Icon(Icons.login_rounded, size: 18),
                            label: Text('Desde ${_formatTimeOfDay(startTime)}'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await showTimePicker(
                                context: ctx,
                                initialTime: endTime,
                              );
                              if (picked != null) {
                                setModalState(() => endTime = picked);
                              }
                            },
                            icon: const Icon(Icons.logout_rounded, size: 18),
                            label: Text('Hasta ${_formatTimeOfDay(endTime)}'),
                          ),
                        ),
                      ],
                    ),
                    if (!rangeValid && daysSelected)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'La hora de fin debe ser al menos 30 min posterior a la de inicio.',
                          style: TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      )
                    else if (rangeValid)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${diffMins ~/ 60} h ${diffMins % 60 > 0 ? '${diffMins % 60} min ' : ''}por día',
                          style: TextStyle(color: Colors.green.shade700, fontSize: 12),
                        ),
                      ),
                    const SizedBox(height: 20),
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
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.autorenew),
                        label: Text(
                          'Generar ${weeksAhead * 7} días (${_formatTimeOfDay(startTime)} - ${_formatTimeOfDay(endTime)})',
                        ),
                        onPressed: canGenerate
                            ? () {
                                Navigator.pop(ctx);
                                _generateRecurringSchedule(
                                  selectedDays: selectedDays,
                                  startTime: startTime,
                                  endTime: endTime,
                                  weeksAhead: weeksAhead,
                                );
                              }
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Generates recurring flexible slots using batch writes with progress feedback.
  Future<void> _generateRecurringSchedule({
    required List<bool> selectedDays,
    required TimeOfDay startTime,
    required TimeOfDay endTime,
    required int weeksAhead,
  }) async {
    if (mounted) setState(() => _isLoading = true);

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final caregiverId = _auth.currentUserId!;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final totalDays = weeksAhead * 7;
    int processedDays = 0;
    int slotsCreated = 0;

    try {
      for (int i = 0; i < totalDays; i++) {
        final targetDate = today.add(Duration(days: i));
        if (!selectedDays[targetDate.weekday - 1]) continue;

        final dateStr =
            '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';

        DateTime startDt = DateTime(
          targetDate.year,
          targetDate.month,
          targetDate.day,
          startTime.hour,
          startTime.minute,
        );
        final endDt = DateTime(
          targetDate.year,
          targetDate.month,
          targetDate.day,
          endTime.hour,
          endTime.minute,
        );

        // Si es hoy, solo desde la hora actual en adelante
        if (i == 0 && startDt.isBefore(now)) {
          startDt = now;
        }
        if (endDt.difference(startDt).inMinutes < 30) {
          continue;
        }

        final tagStart =
            '${startDt.hour.toString().padLeft(2, '0')}${startDt.minute.toString().padLeft(2, '0')}';
        final tagEnd =
            '${endDt.hour.toString().padLeft(2, '0')}${endDt.minute.toString().padLeft(2, '0')}';

        final daySlots = <TimeSlot>[
          TimeSlot(
            id: 'flex_${dateStr}_${tagStart}_$tagEnd',
            dateTime: startDt,
            endTime: endDt,
            isAvailable: true,
          ),
        ];

        await DependencyInjection.caregivers.clearDaySlots(caregiverId, dateStr);
        await DependencyInjection.caregivers.setBatchTimeSlots(caregiverId, dateStr, daySlots);

        processedDays++;
        slotsCreated += daySlots.length;
      }

      scaffoldMessenger.showSnackBar(SnackBar(
        content: Text(
          '✅ Horario generado: $processedDays días, $slotsCreated franja(s) flexibles.',
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
      ));
    } catch (e) {
      debugPrint('Error generating recurring schedule: $e');
      scaffoldMessenger.showSnackBar(SnackBar(
        content: Text(
          '${UserFacingErrorMapper.toSpanishMessage(e, fallback: 'No se pudo completar la generación del horario.')}\n'
          'Se han guardado $processedDays días antes del fallo.',
        ),
        backgroundColor: AppTheme.danger,
        duration: const Duration(seconds: 6),
      ));
    } finally {
      await _loadSlots();
    }
  }

  Future<void> _createSingleDaySlots(int startHour, int endHour) async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final caregiverId = _auth.currentUserId!;
      final now = DateTime.now();
      DateTime startDt = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        startHour,
      );
      final endDt = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        endHour,
      );
      if (startDt.isBefore(now)) {
        startDt = now;
      }
      if (endDt.difference(startDt).inMinutes < 30) {
        if (mounted) {
          CustomSnackBar.show(
            context,
            message: 'Ya pasó el horario de esa franja para hoy. Usa "Añadir franja flexible".',
            type: SnackBarType.warning,
          );
        }
        return;
      }

      final tagStart =
          '${startDt.hour.toString().padLeft(2, '0')}${startDt.minute.toString().padLeft(2, '0')}';
      final tagEnd =
          '${endDt.hour.toString().padLeft(2, '0')}${endDt.minute.toString().padLeft(2, '0')}';

      final daySlots = <TimeSlot>[
        TimeSlot(
          id: 'flex_${_dateStr}_${tagStart}_$tagEnd',
          dateTime: startDt,
          endTime: endDt,
          isAvailable: true,
        ),
      ];
      await DependencyInjection.caregivers.clearDaySlots(caregiverId, _dateStr);
      await DependencyInjection.caregivers.setBatchTimeSlots(caregiverId, _dateStr, daySlots);
      await _loadSlots();
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: '✅ Franja ${_formatHm(startDt)} - ${_formatHm(endDt)} activada.',
          type: SnackBarType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: UserFacingErrorMapper.toSpanishMessage(
            e,
            fallback: 'No se pudieron crear los horarios.',
          ),
          type: SnackBarType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<ConfigNotifier>();
    final fontMult = config.seniorMode ? 1.2 : 1.0;
    final visibleSlots = _visibleSlots;
    final todayOnly = _todayDateOnly;
    final safeInitialDate =
        _selectedDate.isBefore(todayOnly) ? todayOnly : _selectedDate;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Calendario de Horarios'),
        actions: [
          if (visibleSlots.isNotEmpty)
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
            initialDate: safeInitialDate,
            firstDate: todayOnly,
            lastDate: todayOnly.add(const Duration(days: 90)),
            onDateChanged: (date) {
              setState(() => _selectedDate = date);
              _loadSlots();
            },
          ),
          const Divider(height: 1),
          if (_isLoading) const LinearProgressIndicator(),
          Expanded(
            child: _isLoading && visibleSlots.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : visibleSlots.isEmpty
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
                                'Crea tu propia franja horaria flexible desde la hora actual en adelante o genera tu horario recurrente.',
                                style: TextStyle(
                                    color: AppTheme.slateMuted,
                                    fontSize: 13 * fontMult),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  key: const Key('add_flexible_slot_btn'),
                                  onPressed: _isLoading ? null : _showAddFlexibleSlotDialog,
                                  icon: const Icon(Icons.add_alarm_rounded, size: 19),
                                  label: const Text('Añadir franja flexible'),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                alignment: WrapAlignment.center,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: _isLoading ? null : () => _createSingleDaySlots(9, 18),
                                    icon: const Icon(Icons.wb_sunny_outlined, size: 18),
                                    label: const Text('Mañana y tarde (09:00 - 18:00)'),
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
                        padding: const EdgeInsets.only(bottom: 84),
                        itemCount: visibleSlots.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                              child: OutlinedButton.icon(
                                key: const Key('add_flexible_slot_btn'),
                                onPressed: _isLoading ? null : _showAddFlexibleSlotDialog,
                                icon: const Icon(Icons.add_alarm_rounded, size: 18),
                                label: const Text('Añadir otra franja flexible'),
                              ),
                            );
                          }
                          final slot = visibleSlots[index - 1];
                          final interval = TimeInterval(
                            start: slot.dateTime,
                            end: slot.effectiveEndTime,
                          );
                          return SwitchListTile(
                            title: Text(
                              interval.formattedRange,
                              style: TextStyle(
                                fontSize: 16 * fontMult,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              slot.isAvailable
                                  ? 'Disponible (${interval.formattedDuration})'
                                  : 'Bloqueado / Reservado',
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
