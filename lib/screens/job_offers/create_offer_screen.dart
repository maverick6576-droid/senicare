import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/widgets/widgets.dart';

class CreateOfferScreen extends StatefulWidget {
  const CreateOfferScreen({super.key});

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
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  
  final bool _isRecurring = false;
  final int _recurringWeeks = 1;
  final List<bool> _recurringDays = List.filled(7, false); // Mon-Sun
  
  bool get _isUrgent {
    final startDateTime = DateTime(_startDate.year, _startDate.month, _startDate.day, _startTime.hour, _startTime.minute);
    return startDateTime.difference(DateTime.now()).inHours < 24 && startDateTime.isAfter(DateTime.now());
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    final startDateTime = DateTime(_startDate.year, _startDate.month, _startDate.day, _startTime.hour, _startTime.minute);
    
    if (startDateTime.isBefore(DateTime.now())) {
      CustomSnackBar.show(context, message: 'La fecha y hora de la oferta no pueden ser en el pasado', type: SnackBarType.error);
      return;
    }
    
    if (_isRecurring && !_recurringDays.any((d) => d)) {
      CustomSnackBar.show(context, message: 'Selecciona al menos un día para la oferta recurrente', type: SnackBarType.info);
      return;
    }

    final auth = context.read<AuthNotifier>();
    final loc = context.read<LocationNotifier>();
    
    // Calcular horas totales si es recurrente
    int totalHours = int.parse(_hoursCtrl.text);
    int hoursPerDay = totalHours;
    if (_isRecurring) {
      int daysPerWeek = _recurringDays.where((d) => d).length;
      totalHours = hoursPerDay * daysPerWeek * _recurringWeeks;
    }

    final offer = JobOffer(
      id: '', // Will be generated
      clientId: auth.currentUserId!,
      clientName: auth.currentClient?.name ?? 'Cliente',
      clientLatitude: auth.currentClient?.latitude ?? loc.latitude ?? 41.3851,
      clientLongitude: auth.currentClient?.longitude ?? loc.longitude ?? 2.1734,
      title: _titleCtrl.text,
      description: _descCtrl.text,
      pricePerHour: double.parse(_priceCtrl.text),
      totalHours: totalHours,
      isRecurring: _isRecurring,
      recurringDaysOfWeek: _isRecurring ? List.generate(7, (i) => _recurringDays[i] ? i + 1 : -1).where((d) => d != -1).toList() : [],
      recurringHoursPerDay: _isRecurring ? hoursPerDay : 0,
      recurringWeeks: _isRecurring ? _recurringWeeks : 0,
      recurringStartTime: _isRecurring ? '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}' : '',
      startDate: startDateTime,
      isUrgent: _isUrgent,
      urgencyBonusRate: _isUrgent ? 0.10 : 0.0,
      createdAt: DateTime.now(),
    );

    await context.read<JobOfferNotifier>().createOffer(offer);
    
    if (mounted) {
      Navigator.pop(context);
      CustomSnackBar.show(context, message: 'Oferta publicada correctamente. Avisaremos a los cuidadores cercanos.', type: SnackBarType.info);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear Oferta de Trabajo')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_isUrgent)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
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
                        '⚡ Oferta urgente (<24h): SeniCare rebaja un 10% su comisión al cuidador para que recibas candidatos mucho más rápido (sin coste extra para ti).',
                        style: TextStyle(color: Colors.orange.shade900, fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Título de la oferta', hintText: 'Ej. Cuidado diario abuela'),
              validator: (v) => v!.isEmpty ? 'Requerido' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'Descripción / Necesidades', alignLabelWithHint: true),
              maxLines: 4,
              validator: (v) => v!.isEmpty ? 'Requerido' : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _priceCtrl,
                    decoration: const InputDecoration(labelText: 'Precio que ofreces (€/h)'),
                    keyboardType: TextInputType.number,
                    validator: (v) => v!.isEmpty ? 'Requerido' : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _hoursCtrl,
                    decoration: InputDecoration(labelText: _isRecurring ? 'Horas por día' : 'Total de horas'),
                    keyboardType: TextInputType.number,
                    validator: (v) => v!.isEmpty ? 'Requerido' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Fecha de inicio'),
              subtitle: Text('${_startDate.day.toString().padLeft(2, '0')}/${_startDate.month.toString().padLeft(2, '0')}/${_startDate.year}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: _startDate, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                if (d != null) setState(() => _startDate = d);
              },
            ),
            ListTile(
              title: const Text('Hora de inicio'),
              subtitle: Text('${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}'),
              trailing: const Icon(Icons.access_time),
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: _startTime);
                if (t != null) setState(() => _startTime = t);
              },
            ),
            /*
            // Ocultado temporalmente para el MVP por seguridad financiera
            SwitchListTile(
              title: const Text('¿Es un cuidado recurrente?'),
              value: _isRecurring,
              onChanged: (v) => setState(() => _isRecurring = v),
              activeThumbColor: AppTheme.primary,
            ),
            if (_isRecurring) ...[
              const Text('Días de la semana', style: TextStyle(fontWeight: FontWeight.bold)),
              Wrap(
                spacing: 8,
                children: List.generate(7, (i) {
                  final days = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
                  return FilterChip(
                    label: Text(days[i]),
                    selected: _recurringDays[i],
                    onSelected: (v) => setState(() => _recurringDays[i] = v),
                  );
                }),
              ),
              const SizedBox(height: 16),
              const Text('Semanas de duración', style: TextStyle(fontWeight: FontWeight.bold)),
              Slider(
                value: _recurringWeeks.toDouble(),
                min: 1, max: 12, divisions: 11,
                label: '$_recurringWeeks semanas',
                onChanged: (v) => setState(() => _recurringWeeks = v.toInt()),
                activeColor: AppTheme.primary,
              ),
            ],
            */
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primarySurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.verified_user_rounded, color: AppTheme.primary, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Publicar tu oferta es 100% gratuito y sin compromiso. Solo abonarás el servicio (con cobertura de Seguro RC y pago protegido en Escrow) cuando elijas y contrates al candidato que más te guste.',
                      style: TextStyle(fontSize: 12.5, color: AppTheme.darkSlate, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: context.watch<JobOfferNotifier>().isCreating ? null : _submit,
              icon: context.watch<JobOfferNotifier>().isCreating
                  ? const SizedBox.shrink()
                  : const Icon(Icons.campaign_rounded, size: 20),
              label: context.watch<JobOfferNotifier>().isCreating
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Publicar Oferta Gratis'),
            )
          ],
        ),
      ),
    );
  }
}



