import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/widgets/widgets.dart';
import 'package:senicare/widgets/address_form_widget.dart';

class ClientProfileEditScreen extends StatefulWidget {
  const ClientProfileEditScreen({super.key});

  @override
  State<ClientProfileEditScreen> createState() => _ClientProfileEditScreenState();
}

class _ClientProfileEditScreenState extends State<ClientProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _patientDetailsCtrl;
  final TextEditingController _newChecklistCtrl = TextEditingController();
  final TextEditingController _newFamilyEmailCtrl = TextEditingController();
  
  List<String> _defaultChecklist = [];
  List<String> _authorizedFamilyEmails = [];
  bool _isLoading = false;
  bool _isEditing = false;
  double? _homeLat;
  double? _homeLon;

  @override
  void initState() {
    super.initState();
    final client = context.read<AuthNotifier>().currentClient;
    _nameCtrl = TextEditingController(text: client?.name ?? '');
    _phoneCtrl = TextEditingController(text: client?.phone ?? '');
    _addressCtrl = TextEditingController(text: client?.homeAddress ?? '');
    _patientDetailsCtrl = TextEditingController(text: client?.patientDetails ?? '');
    _defaultChecklist = List<String>.from(client?.defaultCareChecklist ?? []);
    _authorizedFamilyEmails = List<String>.from(client?.authorizedFamilyEmails ?? []);
    _homeLat = client?.latitude;
    _homeLon = client?.longitude;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _patientDetailsCtrl.dispose();
    _newChecklistCtrl.dispose();
    _newFamilyEmailCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveFamilyListsQuickly() async {
    final auth = context.read<AuthNotifier>();
    final userId = auth.currentUserId;
    if (userId == null) return;
    await DependencyInjection.clients.updateClient(userId, {
      'defaultCareChecklist': _defaultChecklist,
      'authorizedFamilyEmails': _authorizedFamilyEmails,
    });
    auth.currentClient = await DependencyInjection.clients.getClient(userId);
    auth.forceRefresh();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final auth = context.read<AuthNotifier>();
      final userId = auth.currentUserId;
      if (userId == null) throw Exception('Usuario no logueado');

      // Si la dirección cambió, forzamos buscar las coordenadas
      double? lat = _homeLat;
      double? lon = _homeLon;
      
      final currentClient = auth.currentClient;
      if (currentClient?.homeAddress != _addressCtrl.text.trim() || lat == null || lon == null) {
        final coords = await NominatimService.geocodeAddress(_addressCtrl.text.trim());
        if (coords != null) {
          lat = coords.latitude;
          lon = coords.longitude;
          _homeLat = lat;
          _homeLon = lon;
        } else {
          throw Exception('No se pudo encontrar la ubicación de la dirección introducida. Por favor, sé más específico.');
        }
      }

      final data = {
        'name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'homeAddress': _addressCtrl.text.trim(),
        'patientDetails': _patientDetailsCtrl.text.trim(),
        'latitude': lat,
        'longitude': lon,
        'defaultCareChecklist': _defaultChecklist,
        'authorizedFamilyEmails': _authorizedFamilyEmails,
      };

      await DependencyInjection.clients.updateClient(userId, data);
      
      // Actualizamos el estado local
      auth.currentClient = await DependencyInjection.clients.getClient(userId);
      auth.forceRefresh(); // Refrescar dependientes

      if (mounted) {
        setState(() => _isEditing = false);
        CustomSnackBar.show(context, message: 'Perfil y ubicación actualizados correctamente', type: SnackBarType.success);
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(context, message: 'Error: $e', type: SnackBarType.error);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    return Scaffold(
      appBar: canPop
          ? AppBar(
              title: const Text('Mi Perfil (Cliente)'),
              backgroundColor: Colors.white,
              foregroundColor: AppTheme.darkSlate,
              elevation: 0,
            )
          : null,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        tooltip: _isEditing ? 'Guardar Cambios' : 'Editar Perfil',
        onPressed: () {
          if (_isEditing) {
            _submit();
          } else {
            setState(() => _isEditing = true);
          }
        },
        icon: Icon(_isEditing ? Icons.save : Icons.edit, color: Colors.white),
        label: Text(_isEditing ? 'Guardar' : 'Editar Perfil'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: _isEditing
                  ? Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Datos Personales', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _nameCtrl,
                            decoration: const InputDecoration(labelText: 'Nombre Completo', border: OutlineInputBorder()),
                            validator: (v) => v!.isEmpty ? 'Requerido' : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _phoneCtrl,
                            decoration: const InputDecoration(labelText: 'Teléfono', border: OutlineInputBorder()),
                            keyboardType: TextInputType.phone,
                            validator: (v) => v!.isEmpty ? 'Requerido' : null,
                          ),
                          const SizedBox(height: 32),
                          
                          const Text('Ubicación de Residencia', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                          const SizedBox(height: 8),
                          const Text('Los cuidadores cercanos y el mapa se centrarán en esta dirección.', style: TextStyle(color: Colors.grey)),
                          const SizedBox(height: 16),
                          AddressFormWidget(
                            initialAddress: _addressCtrl.text,
                            onAddressChanged: (addr) {
                              _addressCtrl.text = addr;
                              _homeLat = null;
                              _homeLon = null;
                            },
                          ),
                          const SizedBox(height: 32),
                          
                          const Text('Detalles del Paciente', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _patientDetailsCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Información relevante (edad, movilidad, etc.)',
                              border: OutlineInputBorder(),
                              alignLabelWithHint: true,
                            ),
                            maxLines: 4,
                            validator: (v) => v!.isEmpty ? 'Requerido' : null,
                          ),
                          const SizedBox(height: 32),
                          
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    side: const BorderSide(color: Colors.grey),
                                  ),
                                  onPressed: () => setState(() => _isEditing = false),
                                  child: const Text('Cancelar', style: TextStyle(fontSize: 16, color: Colors.grey)),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 2,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                  ),
                                  onPressed: _submit,
                                  child: const Text('Guardar Cambios', style: TextStyle(fontSize: 16)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Column(
                            children: [
                              const CircleAvatar(
                                radius: 46,
                                backgroundColor: AppTheme.primary,
                                child: Icon(Icons.person, size: 50, color: Colors.white),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _nameCtrl.text.isEmpty ? 'Cliente' : _nameCtrl.text,
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                              ),
                              if (_phoneCtrl.text.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.phone, size: 16, color: Colors.grey),
                                    const SizedBox(width: 6),
                                    Text(
                                      _phoneCtrl.text,
                                      style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 16),
                        const Text('Ubicación de Residencia', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.location_on, color: AppTheme.primary, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _addressCtrl.text.isEmpty ? 'No especificada' : _addressCtrl.text,
                                style: TextStyle(fontSize: 16, color: Colors.grey.shade800),
                                softWrap: true,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        const Text('Detalles del Paciente', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Text(
                            _patientDetailsCtrl.text.isEmpty ? 'Sin especificar' : _patientDetailsCtrl.text,
                            style: TextStyle(fontSize: 16, color: Colors.grey.shade800, height: 1.4),
                          ),
                        ),
                        const SizedBox(height: 28),
                        _buildFamilyDefaultChecklistCard(),
                        const SizedBox(height: 24),
                        _buildSharedFamilyAccountCard(),
                        const SizedBox(height: 80),
                      ],
                    ),
            ),
    );
  }

  Widget _buildFamilyDefaultChecklistCard() {
    const quickPresets = [
      '💊 Tomar medicación pautada',
      '🍲 Preparar comida e hidratación',
      '🚶 Paseo diario de 30-40 min',
      '🧠 Ejercicios de memoria y charla',
      '🚿 Apoyo en higiene personal',
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.primarySurface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.playlist_add_check_circle_rounded, color: AppTheme.primary, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Checklist Habitual de Cuidado',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.darkSlate),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Define aquí las tareas que tu familiar necesita habitualmente. Se cargarán automáticamente en cada nueva reserva para que el cuidador las marque durante el servicio.',
            style: TextStyle(fontSize: 12.5, color: AppTheme.slateMuted, height: 1.35),
          ),
          const SizedBox(height: 12),
          if (_defaultChecklist.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Aún no has definido tareas habituales. Toca una sugerencia o escribe una abajo:',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _defaultChecklist.map((task) {
                return Chip(
                  backgroundColor: Colors.white,
                  label: Text(task, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  deleteIcon: const Icon(Icons.close_rounded, size: 16),
                  onDeleted: () {
                    HapticFeedback.selectionClick();
                    setState(() => _defaultChecklist.remove(task));
                    _saveFamilyListsQuickly();
                  },
                );
              }).toList(),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newChecklistCtrl,
                  decoration: InputDecoration(
                    hintText: 'Añadir tarea (ej. Pastilla tensión 12:30)...',
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  final val = _newChecklistCtrl.text.trim();
                  if (val.isNotEmpty && !_defaultChecklist.contains(val)) {
                    HapticFeedback.mediumImpact();
                    setState(() {
                      _defaultChecklist.add(val);
                      _newChecklistCtrl.clear();
                    });
                    _saveFamilyListsQuickly();
                  }
                },
                child: const Text('Añadir'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: quickPresets
                .where((p) => !_defaultChecklist.contains(p))
                .map((preset) => ActionChip(
                      backgroundColor: Colors.white,
                      label: Text('+ $preset', style: const TextStyle(fontSize: 11.5)),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        setState(() => _defaultChecklist.add(preset));
                        _saveFamilyListsQuickly();
                      },
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSharedFamilyAccountCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.family_restroom_rounded, color: AppTheme.primary, size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Cuenta Familiar Compartida',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.darkSlate),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Autoriza a tus hermanos u otros familiares para que reciban notificaciones del Diario del Cuidado y consulten el calendario de visitas.',
            style: TextStyle(fontSize: 12.5, color: AppTheme.slateMuted, height: 1.35),
          ),
          const SizedBox(height: 12),
          if (_authorizedFamilyEmails.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _authorizedFamilyEmails.map((email) {
                return Chip(
                  avatar: const Icon(Icons.person_outline_rounded, size: 16, color: AppTheme.primary),
                  backgroundColor: AppTheme.backgroundNeutral,
                  label: Text(email, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  deleteIcon: const Icon(Icons.close_rounded, size: 16),
                  onDeleted: () {
                    HapticFeedback.selectionClick();
                    setState(() => _authorizedFamilyEmails.remove(email));
                    _saveFamilyListsQuickly();
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newFamilyEmailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: 'Email del familiar (ej. hermano@email.com)',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  final email = _newFamilyEmailCtrl.text.trim();
                  if (email.contains('@') && !_authorizedFamilyEmails.contains(email)) {
                    HapticFeedback.mediumImpact();
                    setState(() {
                      _authorizedFamilyEmails.add(email);
                      _newFamilyEmailCtrl.clear();
                    });
                    _saveFamilyListsQuickly();
                    CustomSnackBar.show(
                      context,
                      message: 'Familiar autorizado correctamente.',
                      type: SnackBarType.success,
                    );
                  }
                },
                child: const Text('Invitar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
