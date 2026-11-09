import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/screens/screens.dart';
import 'package:senicare/widgets/widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _showInsuranceAndSafetyModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.shield_rounded, color: AppTheme.primary, size: 28),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Protección SeniCare, Seguro RC y RGPD Art. 9',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                '1. Cobertura de Responsabilidad Civil y Garantía por Servicio:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                '• Todos los servicios contratados y abonados dentro de SeniCare cuentan con retención de pago en garantía (Escrow) y canal prioritario de resolución de incidencias.\n'
                '• El pago solo se libera al cuidador tras validar su llegada en el domicilio con el código PIN/QR de la reserva.',
                style: TextStyle(fontSize: 13.5, height: 1.4),
              ),
              const SizedBox(height: 12),
              const Text(
                '2. Verificación Documental (DNI/NIE + Certificado Negativo de Penales):',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                '• Exigimos documento de identidad en vigor y Certificado de Antecedentes Penales / Delitos de Naturaleza Sexual antes de aprobar el sello de Cuidador Verificado.',
                style: TextStyle(fontSize: 13.5, height: 1.4),
              ),
              const SizedBox(height: 12),
              const Text(
                '3. Protección de Datos de Salud (RGPD Art. 9) y Directiva Europea DAC7:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                '• Los datos de asistencia y contacto están protegidos bajo acuerdo de confidencialidad (DPA) y normativa europea RGPD.\n'
                '• Cumplimos con la normativa fiscal europea de plataformas digitales (Directiva DAC7) mediante liquidaciones trazables en Stripe Connect.',
                style: TextStyle(fontSize: 13.5, height: 1.4),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDeleteConfirmation(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Cuenta', style: TextStyle(color: Colors.red)),
        content: const Text(
          '¿Estás seguro de que quieres eliminar tu cuenta?\n\n'
          'Esta acción es IRREVERSIBLE y borrará permanentemente todos tus datos, '
          'historial de reservas y perfil de nuestros servidores (Derecho al Olvido RGPD Art. 17).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar Definitivamente', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      _deleteAccount(context);
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final authNotifier = context.read<AuthNotifier>();
      final userId = authNotifier.currentUserId;

      if (userId != null) {
        try {
          await FirebaseFunctions.instanceFor(region: 'europe-west1')
              .httpsCallable('deleteUserAccountRgpd')
              .call();
        } catch (e) {
          debugPrint('Warning calling deleteUserAccountRgpd: $e');
        }
        await DependencyInjection.auth.deleteAccount();
      }

      if (context.mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AuthScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // close loading
        CustomSnackBar.show(
          context,
          message: 'Error al eliminar cuenta: $e\nPuede que necesites cerrar sesión y volver a entrar para confirmar tu identidad.',
          type: SnackBarType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<ConfigNotifier>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes, Accesibilidad y Privacidad'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Accesibilidad Visual', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary)),
          const SizedBox(height: 10),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.text_fields_rounded, color: AppTheme.primary),
              title: const Text('Modo Letra Grande (Accesible)', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Aumenta el tamaño de los textos y botones para facilitar la lectura.'),
              value: config.seniorMode,
              activeThumbColor: AppTheme.primary,
              onChanged: (val) => config.toggleSeniorMode(val),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Seguridad, Cobertura y Legal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary)),
          const SizedBox(height: 10),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.verified_user_rounded, color: AppTheme.primary),
                  title: const Text('Garantía SeniCare, Seguro RC y RGPD Art. 9', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Ver cobertura del servicio, protección de pagos y confidencialidad médica.'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showInsuranceAndSafetyModal(context),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Términos y Política de Privacidad Oficial'),
                  leading: const Icon(Icons.privacy_tip_outlined, color: AppTheme.primary),
                  trailing: const Icon(Icons.open_in_new, size: 16),
                  onTap: () async {
                    final url = Uri.parse('https://senicare-3342d.web.app');
                    if (await canLaunchUrl(url)) {
                      await launchUrl(url, mode: LaunchMode.externalApplication);
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('Zona de Peligro', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('Eliminar Cuenta Definitivamente', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              subtitle: const Text('Borra todos tus datos personales y de perfil de forma irreversible (RGPD Art. 17).'),
              onTap: () => _showDeleteConfirmation(context),
            ),
          ),
        ],
      ),
    );
  }
}

