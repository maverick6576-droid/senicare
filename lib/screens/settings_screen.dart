import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
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
    final isSharedMember = context.read<AuthNotifier>().isSharedFamilyMember;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Cuenta', style: TextStyle(color: Colors.red)),
        content: Text(
          isSharedMember
              ? '¿Estás seguro de que quieres eliminar tu cuenta personal?\n\n'
                  'Saldrás de la cuenta familiar compartida sin borrar el historial médico ni las reservas de los demás familiares.'
              : '¿Estás seguro de que quieres eliminar tu cuenta?\n\n'
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
        if (useFirebaseBackend && Firebase.apps.isNotEmpty) {
          // La Cloud Function borra atómicamente membresía familiar, datos RGPD en Firestore y Firebase Auth.
          await FirebaseFunctions.instanceFor(region: 'europe-west1')
              .httpsCallable('deleteUserAccountRgpd')
              .call();
          try {
            await DependencyInjection.auth.signOut();
          } catch (_) {}
        } else {
          if (authNotifier.isSharedFamilyMember) {
            await authNotifier.leaveSharedFamily();
          }
          await DependencyInjection.auth.deleteAccount();
        }
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
    final isCaregiver = context.watch<AuthNotifier>().currentRole == 'caregiver';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes, Accesibilidad y Privacidad'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            isCaregiver
                ? '🎓 Ayuda y Tutorial para Cuidadores'
                : '🎓 Ayuda y Tutorial para Familias',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.35)),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primarySurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.play_circle_outline_rounded, color: AppTheme.primary, size: 26),
              ),
              title: const Text(
                'Tutorial guiado paso a paso',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              subtitle: Text(
                isCaregiver
                    ? 'Aprende cómo gestionar horarios, ofertas, reservas, mensajes y cobros con guía iluminada.'
                    : 'Aprende paso a paso cómo buscar cuidadores, publicar ofertas, reservar con pago seguro, chatear y configurar tu perfil.',
                style: const TextStyle(fontSize: 13),
              ),
              trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.primary),
              onTap: () {
                HapticFeedback.selectionClick();
                final cfg = context.read<ConfigNotifier>();
                if (isCaregiver) {
                  cfg.triggerCaregiverTutorial();
                } else {
                  cfg.triggerClientTutorial();
                }
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
            ),
          ),
          const SizedBox(height: 20),
          const Text('👓 Modo Senior & Accesibilidad Visual', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary)),
          const SizedBox(height: 6),
          const Text(
            'Diseñado para familiares mayores o usuarios con vista cansada. Aumenta la tipografía, refuerza el contraste y ensancha los botones.',
            style: TextStyle(fontSize: 13, color: AppTheme.slateMuted),
          ),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: config.seniorMode ? AppTheme.primary : AppTheme.borderSubtle,
                width: config.seniorMode ? 1.8 : 1.0,
              ),
            ),
            elevation: config.seniorMode ? 2 : 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: config.seniorMode ? AppTheme.primarySurface : AppTheme.backgroundNeutral,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.text_increase_rounded,
                        color: config.seniorMode ? AppTheme.primary : AppTheme.darkSlate,
                        size: 26,
                      ),
                    ),
                    title: const Text('Activar Modo Senior (Letra Grande)', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    subtitle: const Text(
                      'Aumenta el tamaño tipográfico (+30%) y el área de toque en toda la aplicación.',
                      style: TextStyle(fontSize: 12.5),
                    ),
                    value: config.seniorMode,
                    activeThumbColor: AppTheme.primary,
                    onChanged: (val) {
                      HapticFeedback.mediumImpact();
                      config.toggleSeniorMode(val);
                    },
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: config.seniorMode ? AppTheme.primarySurface.withValues(alpha: 0.5) : AppTheme.backgroundNeutral,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: config.seniorMode ? AppTheme.primary.withValues(alpha: 0.4) : AppTheme.borderSubtle),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                config.seniorMode ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                                size: 16,
                                color: config.seniorMode ? AppTheme.primary : AppTheme.slateMuted,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                config.seniorMode ? 'Modo Senior Activado (Tamaño XL)' : 'Modo Estándar (Tamaño Normal)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: config.seniorMode ? 14 : 12.5,
                                  color: config.seniorMode ? AppTheme.primary : AppTheme.darkSlate,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Así es como leerás los nombres de los cuidadores, los horarios de medicación y las pautas familiares de SeniCare.',
                            style: TextStyle(
                              fontSize: config.seniorMode ? 16 : 13,
                              height: 1.4,
                              color: AppTheme.darkSlate,
                              fontWeight: config.seniorMode ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                CustomSnackBar.show(
                                  context,
                                  message: config.seniorMode
                                      ? '✅ Botón táctil Senior XL: fácil de pulsar y altamente visible.'
                                      : 'Botón táctil estándar.',
                                  type: SnackBarType.info,
                                );
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: config.seniorMode ? AppTheme.primary : AppTheme.darkSlate,
                                minimumSize: Size(double.infinity, config.seniorMode ? 52 : 42),
                              ),
                              child: Text(
                                'Botón de Prueba Táctil',
                                style: TextStyle(
                                  fontSize: config.seniorMode ? 16 : 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!isCaregiver) ...[
            const SizedBox(height: 20),
            Builder(
              builder: (ctx) {
                final auth = ctx.watch<AuthNotifier>();
                final role = auth.currentFamilyRole;
                final familyName = auth.currentClient?.name.isNotEmpty == true
                    ? auth.currentClient!.name
                    : 'Cuenta Familiar';
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '👨‍👩‍👧‍👦 Cuenta Familiar Compartida',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(
                              Icons.family_restroom_rounded,
                              color: AppTheme.primary,
                            ),
                            title: Text(
                              familyName,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              role != null
                                  ? 'Tu rol: ${role.displayLabel} · ${role.permissionsSummary}'
                                  : 'Conecta a otros familiares desde Mi Perfil',
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                          const Divider(height: 1),
                          ListTile(
                            leading: const Icon(
                              Icons.qr_code_2_rounded,
                              color: AppTheme.primary,
                            ),
                            title: const Text(
                              'Unirme a otra cuenta familiar con código',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: const Text(
                              'Introduce un código o enlace recibido de tu familia.',
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => showJoinFamilyDialog(context),
                          ),
                          if (auth.isSharedFamilyMember) ...[
                            const Divider(height: 1),
                            ListTile(
                              leading: const Icon(
                                Icons.logout_rounded,
                                color: Colors.orange,
                              ),
                              title: const Text(
                                'Salir de esta familia compartida',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.deepOrange,
                                ),
                              ),
                              subtitle: const Text(
                                'Desconecta tu usuario de esta cuenta familiar sin afectar al resto.',
                              ),
                              onTap: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (dCtx) => AlertDialog(
                                    title: const Text('¿Salir de esta familia?'),
                                    content: const Text(
                                      'Dejarás de ver sus reservas, el Diario del Cuidado y sus chats hasta que vuelvas a recibir una invitación.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(dCtx, false),
                                        child: const Text('Cancelar'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () => Navigator.pop(dCtx, true),
                                        child: const Text('Salir'),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok == true && context.mounted) {
                                  await context.read<AuthNotifier>().leaveSharedFamily();
                                  if (context.mounted) {
                                    Navigator.of(context).popUntil((r) => r.isFirst);
                                  }
                                }
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
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

