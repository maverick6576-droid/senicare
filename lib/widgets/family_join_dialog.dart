import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/widgets/custom_snackbar.dart';

/// Abre un diálogo simple y accesible para unirse a una cuenta familiar existente
/// mediante código de invitación (`SN4K8P2M`) o enlace completo.
Future<FamilyJoinResult?> showJoinFamilyDialog(BuildContext context) {
  return showDialog<FamilyJoinResult>(
    context: context,
    builder: (_) => const _JoinFamilyDialog(),
  );
}

class _JoinFamilyDialog extends StatefulWidget {
  const _JoinFamilyDialog();

  @override
  State<_JoinFamilyDialog> createState() => _JoinFamilyDialogState();
}

class _JoinFamilyDialogState extends State<_JoinFamilyDialog> {
  final _codeCtrl = TextEditingController();
  bool _isSubmitting = false;
  String? _errorText;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final raw = _codeCtrl.text.trim();
    final extracted = FamilyInvite.extractInviteCode(raw);
    if (extracted == null) {
      setState(() {
        _errorText =
            'Introduce un código válido (ej. SN4K8P2M) o pega el enlace de invitación.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    try {
      final result =
          await context.read<AuthNotifier>().joinFamilyWithCode(raw);
      if (!mounted) return;
      Navigator.pop(context, result);
      CustomSnackBar.show(
        context,
        message:
            'Conectado a "${result.familyName}" como ${result.role.displayLabel}.',
        type: SnackBarType.success,
      );
    } catch (e) {
      if (!mounted) return;
      final clean = e.toString().replaceFirst('Bad state: ', '').trim();
      setState(() {
        _isSubmitting = false;
        _errorText = clean;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.family_restroom_rounded, color: AppTheme.primary),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Unirme a cuenta familiar',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Introduce el código de 8 caracteres o pega el enlace que te envió el administrador de tu familia:',
            style: TextStyle(fontSize: 13.5, color: AppTheme.slateMuted),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _codeCtrl,
            textCapitalization: TextCapitalization.characters,
            enabled: !_isSubmitting,
            decoration: InputDecoration(
              labelText: 'Código o enlace de invitación',
              hintText: 'Ej. SN4K8P2M o https://senicare.app/join?code=...',
              prefixIcon: const Icon(Icons.vpn_key_outlined),
              errorText: _errorText,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onSubmitted: (_) => _isSubmitting ? null : _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton.icon(
          onPressed: _isSubmitting ? null : _submit,
          icon: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.login_rounded, size: 18),
          label: Text(_isSubmitting ? 'Conectando...' : 'Unirme'),
        ),
      ],
    );
  }
}

/// Tarjeta compacta para unirse a una familia ya existente mediante código/enlace
/// o reintentar la detección automática por email.
class JoinFamilyBannerCard extends StatelessWidget {
  final VoidCallback? onJoined;
  final VoidCallback? onRecheckEmail;
  final bool isRecheckingEmail;

  const JoinFamilyBannerCard({
    super.key,
    this.onJoined,
    this.onRecheckEmail,
    this.isRecheckingEmail = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primarySurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.group_add_rounded, color: AppTheme.primary),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '¿Otro familiar ya creó la cuenta?',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Únete a la misma cuenta familiar para ver reservas, el Diario del Cuidado y chatear en equipo, cada uno con su propio Google, Apple o email.',
            style: TextStyle(fontSize: 12.5, color: AppTheme.darkSlate),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: () async {
                  final res = await showJoinFamilyDialog(context);
                  if (res != null) {
                    onJoined?.call();
                  }
                },
                icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                label: const Text('Unirme con código o enlace'),
              ),
              if (onRecheckEmail != null)
                OutlinedButton.icon(
                  onPressed: isRecheckingEmail ? null : onRecheckEmail,
                  icon: isRecheckingEmail
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.mark_email_read_outlined, size: 18),
                  label: const Text('Buscar invitación por mi email'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
