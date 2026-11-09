import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/widgets/address_form_widget.dart';
import 'package:geolocator/geolocator.dart';
import 'package:senicare/widgets/widgets.dart';

class ClientOnboardingScreen extends StatefulWidget {
  const ClientOnboardingScreen({super.key});

  @override
  State<ClientOnboardingScreen> createState() => _ClientOnboardingScreenState();
}

class _ClientOnboardingScreenState extends State<ClientOnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _patientDetailsCtrl = TextEditingController();
  bool _isLoading = false;
  double? _homeLat;
  double? _homeLon;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final auth = context.read<AuthNotifier>();
      final userId = auth.currentUserId;
      if (userId == null) throw Exception('No user logged in');

      double? lat = _homeLat;
      double? lon = _homeLon;
      if (lat == null || lon == null) {
        final coords = await NominatimService.geocodeAddress(_addressCtrl.text.trim());
        if (coords != null) {
          lat = coords.latitude;
          lon = coords.longitude;
        }
      }

      final data = {
        'name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'homeAddress': _addressCtrl.text.trim(),
        'patientDetails': _patientDetailsCtrl.text.trim(),
        'onboardingComplete': true,
        'latitude': lat,
        'longitude': lon,
      };

      await DependencyInjection.clients.updateClient(userId, data);
      
      // Update local state directly so UI can rebuild and switch to MainLayout
      auth.currentClient = await DependencyInjection.clients.getClient(userId);
      auth.onboardingComplete = true;
      // Note: In strict architecture, we'd use a setter. 
      // Using notifyListeners since it's available.
      auth.notifyListeners();
    } catch (e) {
      if (context.mounted) {
        CustomSnackBar.show(context, message: 'Error: $e', type: SnackBarType.info);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Completar Perfil')),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('¡Bienvenido a SeniCare!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Antes de empezar a buscar cuidadores, necesitamos algunos datos básicos.'),
                  const SizedBox(height: 24),
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
                  const SizedBox(height: 16),
                  AddressFormWidget(
                        initialAddress: _addressCtrl.text,
                        onAddressChanged: (addr) {
                          _addressCtrl.text = addr;
                          _homeLat = null;
                          _homeLon = null;
                        },
                      ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.blue),
                            SizedBox(width: 8),
                            Expanded(child: Text('Detalles de la Persona a Cuidar', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text('Aclara que la información introducida a continuación (y la dirección) pertenece a la persona que va a recibir los cuidados, no necesariamente a la que se registra.', style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _patientDetailsCtrl,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            hintText: 'Ej: Mi padre de 80 años, movilidad reducida, necesita ayuda para el aseo...',
                            border: OutlineInputBorder(),
                            fillColor: Colors.white,
                            filled: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _submit,
                      child: const Text('Finalizar Registro', style: TextStyle(fontSize: 16)),
                    ),
                  )
                ],
              ),
            ),
          ),
    );
  }
}

