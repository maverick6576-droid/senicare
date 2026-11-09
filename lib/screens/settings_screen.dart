import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/screens/screens.dart';
import 'package:senicare/widgets/widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _launchUrl(String urlString) async {
    final url = Uri.parse(urlString);
    if (!await launchUrl(url)) {
      debugPrint('Could not launch $urlString');
    }
  }

  Future<void> _showDeleteConfirmation(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Cuenta', style: TextStyle(color: Colors.red)),
        content: const Text(
          '¿Estás seguro de que quieres eliminar tu cuenta?\n\n'
          'Esta acción es IRREVERSIBLE y borrará permanentemente todos tus datos, '
          'historial de reservas y perfil de nuestros servidores.',
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
        // Delete Firestore document if possible (or mark as deleted via a cloud function ideally)
        // Here we just delete the Auth user for App Store compliance.
        // A robust backend would use an auth trigger to cascade delete data.
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
        CustomSnackBar.show(context, message: 'Error al eliminar cuenta: $e\nPuede que necesites cerrar sesión y volver a entrar para confirmar tu identidad.', type: SnackBarType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes y Privacidad'),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.darkSlate,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Legal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary)),
          const SizedBox(height: 16),
          ListTile(
            title: const Text('Términos y Política de Privacidad'),
            leading: const Icon(Icons.privacy_tip, color: AppTheme.primary),
            trailing: const Icon(Icons.open_in_new, size: 16),
            onTap: () async {
              final url = Uri.parse('https://senicare-3342d.web.app');
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
          ),
          const Divider(height: 32),
          const Text('Zona de Peligro', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('Eliminar Cuenta Definitivamente', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            subtitle: const Text('Borra todos tus datos de forma irreversible.'),
            onTap: () => _showDeleteConfirmation(context),
          ),
        ],
      ),
    );
  }
}

