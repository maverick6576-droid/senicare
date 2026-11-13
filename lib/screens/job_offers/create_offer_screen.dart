import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/widgets/widgets.dart';

class CreateOfferScreen extends StatefulWidget {
  final JobOffer? initialOffer;
  const CreateOfferScreen({super.key, this.initialOffer});

  @override
  State<CreateOfferScreen> createState() => _CreateOfferScreenState();
}

class _CreateOfferScreenState extends State<CreateOfferScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _hoursCtrl = TextEditingController();

  DateTime _startDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _startTime = const TimeOfDay(hour: 10, minute: 0);
  bool _isRecurring = false;
  final List<int> _recurringDays = [1, 3, 5];
  int _recurringWeeks = 4;
  bool _urgencyBonusEnabled = true;

  static const _weekDayLabels = <int, String>{
    1: 'Lun',
    2: 'Mar',
    3: 'Mié',
    4: 'Jue',
    5: 'Vie',
    6: 'Sáb',
    7: 'Dom',
  };

  static const _quickTemplates = <({String title, String desc, double price, int hours})>[
    (
      title: 'Acompañamiento y paseo',
      desc: 'Compañía agradable, conversación y paseo tranquilo cerca de casa.',
      price: 14,
      hours: 3,
    ),
    (
      title: 'Ayuda en casa y comidas',
      desc: 'Apoyo con las tareas diarias del hogar, preparación de comida y compañía.',
      price: 15,
      hours: 4,
    ),
    (
      title: 'Cuidado de noche',
      desc: 'Acompañamiento nocturno en domicilio y asistencia si se despierta.',
      price: 16,
      hours: 8,
    ),
  ];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialOffer;
    if (initial != null) {
      _titleCtrl.text = initial.title;
      _descCtrl.text = initial.description;
      _priceCtrl.text = _formatNumber(initial.pricePerHour);
      _hoursCtrl.text = initial.totalHours.toString();
      _startTime = TimeOfDay(hour: initial.startDate.hour, minute: initial.startDate.minute);
      _isRecurring = initial.isRecurring;
      if (initial.recurringDaysOfWeek.isNotEmpty) {
        _recurringDays
          ..clear()
          ..addAll(initial.recurringDaysOfWeek);
      }
      if (initial.recurringWeeks > 0) {
        _recurringWeeks = initial.recurringWeeks;
      }
    }
    _priceCtrl.addListener(_onCostInputChanged);
    _hoursCtrl.addListener(_onCostInputChanged);
    _loadLeanFlags();
  }

  Future<void> _loadLeanFlags() async {
    if (!useFirebaseBackend || Firebase.apps.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('experiments')
          .doc('lean_config')
          .get();
      if (!mounted || !doc.exists) return;
      final data = doc.data();
      if (data != null && data['urgency_bonus_enabled'] is bool) {
        setState(() {
          _urgencyBonusEnabled = data['urgency_bonus_enabled'] as bool;
        });
      }
    } catch (_) {
      // Fallback safely to default enabled state.
    }
  }

  void _onCostInputChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _priceCtrl.removeListener(_onCostInputChanged);
    _hoursCtrl.removeListener(_onCostInputChanged);
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _hoursCtrl.dispose();
    super.dispose();
  }

  String _formatNumber(double val) {
    return val == val.roundToDouble() ? val.toInt().toString() : val.toStringAsFixed(2);
  }

  double? _parsePrice() {
    final normalized = _priceCtrl.text.trim().replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  int? _parseHours() {
    return int.tryParse(_hoursCtrl.text.trim());
  }

  DateTime get _selectedStartDateTime => DateTime(
        _startDate.year,
        _startDate.month,
        _startDate.day,
        _startTime.hour,
        _startTime.minute,
      );

  bool get _isInPast => _selectedStartDateTime.isBefore(DateTime.now());

  bool get _isUrgent {
    final start = _selectedStartDateTime;
    final now = DateTime.now();
    return start.isAfter(now) && start.difference(now).inHours < 24;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final startDateTime = _selectedStartDateTime;
    if (startDateTime.isBefore(DateTime.now())) {
      CustomSnackBar.show(
        context,
        message: 'Elige una fecha y hora que todavía no hayan pasado.',
        type: SnackBarType.error,
      );
      return;
    }

    final price = _parsePrice();
    final totalHours = _parseHours();
    if (price == null || price <= 0 || totalHours == null || totalHours < 1) {
      CustomSnackBar.show(
        context,
        message: 'Revisa el precio por hora y el total de horas.',
        type: SnackBarType.error,
      );
      return;
    }

    final auth = context.read<AuthNotifier>();
    final uid = auth.effectiveClientId ?? auth.currentUserId;
    if (!auth.canManageFamilyPayments) {
      CustomSnackBar.show(
        context,
        message:
            'Solo un Administrador de la familia puede publicar ofertas de empleo.',
        type: SnackBarType.warning,
      );
      return;
    }
    if (uid == null || uid.isEmpty) {
      CustomSnackBar.show(
        context,
        message: 'Debes iniciar sesión para publicar una oferta.',
        type: SnackBarType.error,
      );
      return;
    }

    if (_isRecurring && _recurringDays.isEmpty) {
      CustomSnackBar.show(
        context,
        message: 'Selecciona al menos un día de la semana para la oferta recurrente.',
        type: SnackBarType.warning,
      );
      return;
    }

    final loc = context.read<LocationNotifier>();
    final recurringStart =
        '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}';
    final offer = JobOffer(
      id: '',
      clientId: uid,
      clientName: auth.currentClient?.name ?? 'Cliente',
      clientLatitude: auth.currentClient?.latitude ?? loc.latitude ?? 41.3851,
      clientLongitude: auth.currentClient?.longitude ?? loc.longitude ?? 2.1734,
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      pricePerHour: price,
      totalHours: totalHours,
      isRecurring: _isRecurring,
      recurringDaysOfWeek: _isRecurring ? (List<int>.from(_recurringDays)..sort()) : const [],
      recurringHoursPerDay: _isRecurring ? totalHours : 0,
      recurringWeeks: _isRecurring ? _recurringWeeks : 0,
      recurringStartTime: _isRecurring ? recurringStart : '',
      startDate: startDateTime,
      isUrgent: _isUrgent,
      urgencyBonusRate: (_isUrgent && _urgencyBonusEnabled) ? 0.10 : 0.0,
      createdAt: DateTime.now(),
    );

    try {
      await context.read<JobOfferNotifier>().createOffer(offer);
      if (!mounted) return;
      Navigator.pop(context);
      CustomSnackBar.show(
        context,
        message: 'Oferta publicada gratis. Te avisaremos en cuanto respondan cuidadores.',
        type: SnackBarType.info,
      );
    } catch (_) {
      if (!mounted) return;
      CustomSnackBar.show(
        context,
        message: 'No pudimos publicar tu oferta ahora. Inténtalo de nuevo.',
        type: SnackBarType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final seniorMode = context.watch<ConfigNotifier>().seniorMode;
    final isCreating = context.watch<JobOfferNotifier>().isCreating;
    final parsedPrice = _parsePrice();
    final parsedHours = _parseHours();
    final estimatedTotal =
        (parsedPrice != null && parsedPrice > 0 && parsedHours != null && parsedHours > 0)
            ? parsedPrice * parsedHours
            : null;

    return Scaffold(
      backgroundColor: AppTheme.backgroundNeutral,
      appBar: AppBar(
        title: Text(widget.initialOffer != null ? 'Volver a Publicar Oferta' : 'Nueva Oferta de Cuidado'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            _buildIntroBanner(seniorMode),
            const SizedBox(height: 16),
            Text(
              'Plantillas rápidas (opcional)',
              style: TextStyle(
                fontSize: seniorMode ? 16 : 14,
                fontWeight: FontWeight.w800,
                color: AppTheme.darkSlate,
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _quickTemplates.map((tpl) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      avatar: const Icon(Icons.auto_awesome_rounded, size: 16, color: AppTheme.primary),
                      label: Text(
                        tpl.title,
                        style: TextStyle(
                          fontSize: seniorMode ? 14 : 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      backgroundColor: Colors.white,
                      side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.25)),
                      onPressed: () {
                        setState(() {
                          _titleCtrl.text = tpl.title;
                          _descCtrl.text = tpl.desc;
                          if (_priceCtrl.text.trim().isEmpty) {
                            _priceCtrl.text = _formatNumber(tpl.price);
                          }
                          if (_hoursCtrl.text.trim().isEmpty) {
                            _hoursCtrl.text = tpl.hours.toString();
                          }
                        });
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            _buildSectionCard(
              title: '1. ¿Qué ayuda necesitas?',
              seniorMode: seniorMode,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _titleCtrl,
                    style: TextStyle(fontSize: seniorMode ? 17 : 15),
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Título sencillo',
                      hintText: 'Ej. Acompañamiento por la tarde',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _descCtrl,
                    style: TextStyle(fontSize: seniorMode ? 16.5 : 14.5),
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: '¿En qué consiste el cuidado?',
                      hintText: 'Ej. Paseo suave, ayuda con la merienda y compañía.',
                      alignLabelWithHint: true,
                    ),
                    maxLines: 3,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: '2. ¿Cuánto pagas y cuántas horas?',
              seniorMode: seniorMode,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [12, 15, 18].map((rate) {
                      final selected = _parsePrice() == rate.toDouble();
                      return ChoiceChip(
                        label: Text('$rate €/h'),
                        selected: selected,
                        onSelected: (_) => setState(() => _priceCtrl.text = '$rate'),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _priceCtrl,
                          style: TextStyle(fontSize: seniorMode ? 17 : 15),
                          decoration: const InputDecoration(
                            labelText: 'Precio (€/h)',
                            hintText: '15',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Requerido';
                            final parsed = double.tryParse(v.trim().replaceAll(',', '.'));
                            if (parsed == null || parsed <= 0 || parsed > 200) {
                              return 'Precio no válido';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _hoursCtrl,
                          style: TextStyle(fontSize: seniorMode ? 17 : 15),
                          decoration: const InputDecoration(
                            labelText: 'Horas totales',
                            hintText: '4',
                          ),
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Requerido';
                            final parsed = int.tryParse(v.trim());
                            if (parsed == null || parsed < 1 || parsed > 168) {
                              return 'Mínimo 1 hora';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [2, 4, 8].map((hrs) {
                      final selected = _parseHours() == hrs;
                      return ChoiceChip(
                        label: Text('$hrs horas'),
                        selected: selected,
                        onSelected: (_) => setState(() => _hoursCtrl.text = '$hrs'),
                      );
                    }).toList(),
                  ),
                  if (estimatedTotal != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primarySurface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calculate_outlined, color: AppTheme.primary, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Total aproximado de la oferta: ${_formatNumber(estimatedTotal)} € (${parsedHours}h × ${_formatNumber(parsedPrice!)} €/h)',
                              style: TextStyle(
                                color: AppTheme.darkSlate,
                                fontWeight: FontWeight.w700,
                                fontSize: seniorMode ? 14.5 : 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: '3. ¿Cuándo empieza el cuidado?',
              seniorMode: seniorMode,
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.primarySurface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.calendar_today_rounded, color: AppTheme.primary, size: 20),
                    ),
                    title: Text(
                      'Día de inicio',
                      style: TextStyle(fontSize: seniorMode ? 16 : 14.5, fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${_startDate.day.toString().padLeft(2, '0')}/${_startDate.month.toString().padLeft(2, '0')}/${_startDate.year}',
                      style: TextStyle(fontSize: seniorMode ? 16 : 14, color: AppTheme.darkSlate),
                    ),
                    trailing: const Text('Cambiar', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700)),
                    onTap: () async {
                      final now = DateTime.now();
                      final today = DateTime(now.year, now.month, now.day);
                      final initial = _startDate.isBefore(today) ? today : _startDate;
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: initial,
                        firstDate: today,
                        lastDate: today.add(const Duration(days: 365)),
                      );
                      if (picked != null) setState(() => _startDate = picked);
                    },
                  ),
                  const Divider(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.primarySurface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.access_time_rounded, color: AppTheme.primary, size: 20),
                    ),
                    title: Text(
                      'Hora de inicio',
                      style: TextStyle(fontSize: seniorMode ? 16 : 14.5, fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(fontSize: seniorMode ? 16 : 14, color: AppTheme.darkSlate),
                    ),
                    trailing: const Text('Cambiar', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700)),
                    onTap: () async {
                      final picked = await showTimePicker(context: context, initialTime: _startTime);
                      if (picked != null) setState(() => _startTime = picked);
                    },
                  ),
                  if (_isInPast) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'La hora elegida ya ha pasado. Adelanta el día o la hora para poder publicar.',
                              style: TextStyle(
                                color: Colors.red.shade900,
                                fontSize: seniorMode ? 14 : 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (_isUrgent && _urgencyBonusEnabled) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.flash_on_rounded, color: Colors.orange.shade800),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Oferta urgente (<24h): la destacamos con +10% de prioridad para encontrar cuidador más rápido.',
                              style: TextStyle(
                                color: Colors.orange.shade900,
                                fontSize: seniorMode ? 14 : 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _isRecurring,
                    activeTrackColor: AppTheme.primary,
                    title: Text(
                      'Repetir todas las semanas',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: seniorMode ? 16 : 14.5,
                        color: AppTheme.darkSlate,
                      ),
                    ),
                    subtitle: Text(
                      _isRecurring
                          ? 'Elige los días fijos y la duración del plan semanal'
                          : 'Actívalo si necesitas cuidado periódico en los mismos días',
                      style: TextStyle(
                        fontSize: seniorMode ? 13.5 : 12,
                        color: AppTheme.slateMuted,
                      ),
                    ),
                    onChanged: (val) => setState(() => _isRecurring = val),
                  ),
                  if (_isRecurring) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _weekDayLabels.entries.map((entry) {
                        final selected = _recurringDays.contains(entry.key);
                        return FilterChip(
                          label: Text(entry.value),
                          selected: selected,
                          selectedColor: AppTheme.primarySurface,
                          checkmarkColor: AppTheme.primary,
                          onSelected: (isOn) {
                            setState(() {
                              if (isOn && !_recurringDays.contains(entry.key)) {
                                _recurringDays.add(entry.key);
                              } else if (!isOn) {
                                _recurringDays.remove(entry.key);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Duración: $_recurringWeeks semanas',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: seniorMode ? 14.5 : 13,
                              color: AppTheme.darkSlate,
                            ),
                          ),
                        ),
                        DropdownButton<int>(
                          value: _recurringWeeks,
                          items: const [2, 4, 8, 12]
                              .map((w) => DropdownMenuItem(value: w, child: Text('$w sem.')))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _recurringWeeks = val);
                          },
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: seniorMode ? 56 : 50,
              child: FilledButton.icon(
                onPressed: isCreating ? null : _submit,
                icon: isCreating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                      )
                    : const Icon(Icons.campaign_rounded, size: 20),
                label: Text(
                  isCreating ? 'Publicando oferta...' : 'Publicar Oferta Gratis',
                  style: TextStyle(fontSize: seniorMode ? 17 : 15.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntroBanner(bool seniorMode) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primarySurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_user_rounded, color: AppTheme.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Publicar es 100% gratis y sin compromiso. Solo pagas cuando elijas al cuidador que más confianza te dé.',
              style: TextStyle(
                fontSize: seniorMode ? 14.5 : 13,
                color: AppTheme.darkSlate,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required bool seniorMode,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.modernCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: seniorMode ? 17.5 : 15.5,
              fontWeight: FontWeight.w800,
              color: AppTheme.darkSlate,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}



