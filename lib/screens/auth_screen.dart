import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/widgets/widgets.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  static final RegExp _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  bool isLogin = true;
  bool isLoading = false;
  bool _acceptedLegalTerms = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String selectedRole = 'client';
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _selectRole(String roleValue) {
    setState(() => selectedRole = roleValue);
    unawaited(ObservabilityService.logEvent(
      'onboarding_role_selected',
      parameters: {'role': roleValue},
    ));
  }

  Future<void> _submit() async {
    if (isLoading) return;
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (!isLogin) {
      if (password != _confirmPasswordController.text.trim()) {
        CustomSnackBar.show(
          context,
          message: 'Las contraseñas no coinciden.',
          type: SnackBarType.error,
        );
        return;
      }
      if (!_acceptedLegalTerms) {
        CustomSnackBar.show(
          context,
          message: 'Debes aceptar los Términos de Servicio y la Política de Privacidad para crear tu cuenta.',
          type: SnackBarType.warning,
        );
        return;
      }
    }

    setState(() => isLoading = true);

    try {
      if (isLogin) {
        await DependencyInjection.auth.signInWithEmail(email, password);
      } else {
        await DependencyInjection.auth.signUpWithEmail(email, password, selectedRole);
      }
      if (mounted) await context.read<AuthNotifier>().reloadRole();
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: UserFacingErrorMapper.toSpanishMessage(e),
          type: SnackBarType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    if (isLoading) return;
    if (!isLogin && !_acceptedLegalTerms) {
      CustomSnackBar.show(
        context,
        message: 'Acepta los Términos de Servicio y la Política de Privacidad antes de registrarte.',
        type: SnackBarType.warning,
      );
      return;
    }
    setState(() => isLoading = true);
    try {
      await DependencyInjection.auth.signInWithGoogle(selectedRole, isLogin: isLogin);
      if (mounted) await context.read<AuthNotifier>().reloadRole();
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: UserFacingErrorMapper.toSpanishMessage(e),
          type: SnackBarType.error,
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _signInWithApple() async {
    if (isLoading) return;
    if (!isLogin && !_acceptedLegalTerms) {
      CustomSnackBar.show(
        context,
        message: 'Acepta los Términos de Servicio y la Política de Privacidad antes de registrarte.',
        type: SnackBarType.warning,
      );
      return;
    }
    setState(() => isLoading = true);
    try {
      await DependencyInjection.auth.signInWithApple(selectedRole, isLogin: isLogin);
      if (mounted) await context.read<AuthNotifier>().reloadRole();
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: UserFacingErrorMapper.toSpanishMessage(e),
          type: SnackBarType.error,
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _showResetPasswordDialog() async {
    if (isLoading) return;
    final resetEmailController = TextEditingController(text: _emailController.text.trim());
    String? dialogError;
    try {
      final submittedEmail = await showDialog<String>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Recuperar contraseña'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Introduce tu correo para recibir un enlace seguro de recuperación.'),
                const SizedBox(height: 16),
                TextField(
                  controller: resetEmailController,
                  decoration: InputDecoration(
                    labelText: 'Correo Electrónico',
                    errorText: dialogError,
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  onChanged: (_) {
                    if (dialogError != null) {
                      setDialogState(() => dialogError = null);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () {
                  final email = resetEmailController.text.trim();
                  if (email.isEmpty || !_emailRegex.hasMatch(email)) {
                    setDialogState(() {
                      dialogError = 'Introduce un correo electrónico válido.';
                    });
                    return;
                  }
                  Navigator.pop(ctx, email);
                },
                child: const Text('Enviar Enlace'),
              ),
            ],
          ),
        ),
      );
      if (submittedEmail != null && submittedEmail.isNotEmpty) {
        await DependencyInjection.auth.sendPasswordResetEmail(submittedEmail);
        if (mounted) {
          CustomSnackBar.show(
            context,
            message: 'Te hemos enviado un enlace de recuperación a $submittedEmail',
            type: SnackBarType.success,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: UserFacingErrorMapper.toSpanishMessage(e),
          type: SnackBarType.error,
        );
      }
    } finally {
      resetEmailController.dispose();
    }
  }

  Widget _buildRoleCard({
    required String roleValue,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final bool isSelected = selectedRole == roleValue;
    return Expanded(
      child: Semantics(
        button: true,
        selected: isSelected,
        label: '$title, $subtitle',
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: isLoading ? null : () => _selectRole(roleValue),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 88),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.primarySurface : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? AppTheme.primary : AppTheme.borderSubtle,
                  width: isSelected ? 2.0 : 1.2,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ExcludeSemantics(
                    child: Icon(
                      icon,
                      size: 28,
                      color: isSelected ? AppTheme.primary : AppTheme.slateMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: isSelected ? AppTheme.primary : AppTheme.darkSlate,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.slateMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool showAppleSignIn = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);

    return Scaffold(
      backgroundColor: AppTheme.backgroundNeutral,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: ExcludeSemantics(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: AppTheme.borderSubtle),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primary.withValues(alpha: 0.10),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.asset(
                            'assets/images/logo.png',
                            height: 88,
                            width: 88,
                            errorBuilder: (_, _, _) => const SizedBox(
                              height: 88,
                              width: 88,
                              child: Icon(
                                Icons.health_and_safety_rounded,
                                size: 52,
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Semantics(
                    header: true,
                    child: Text(
                      'SeniCare',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.darkSlate,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Cuidado de mayores en casa, 100% verificado y seguro',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: AppTheme.modernCardDecoration(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Selector accesible Iniciar Sesión vs Crear Cuenta (≥ 48dp)
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppTheme.backgroundNeutral,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppTheme.borderSubtle),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Semantics(
                                  button: true,
                                  selected: isLogin,
                                  label: 'Iniciar Sesión',
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: isLoading ? null : () => setState(() => isLogin = true),
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(minHeight: 48),
                                      child: Container(
                                        alignment: Alignment.center,
                                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                                        decoration: BoxDecoration(
                                          color: isLogin ? Colors.white : Colors.transparent,
                                          borderRadius: BorderRadius.circular(10),
                                          boxShadow: isLogin
                                              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)]
                                              : null,
                                        ),
                                        child: Text(
                                          'Iniciar Sesión',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: isLogin ? AppTheme.primary : AppTheme.slateMuted,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Semantics(
                                  button: true,
                                  selected: !isLogin,
                                  label: 'Registrarse',
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: isLoading ? null : () => setState(() => isLogin = false),
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(minHeight: 48),
                                      child: Container(
                                        alignment: Alignment.center,
                                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                                        decoration: BoxDecoration(
                                          color: !isLogin ? Colors.white : Colors.transparent,
                                          borderRadius: BorderRadius.circular(10),
                                          boxShadow: !isLogin
                                              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)]
                                              : null,
                                        ),
                                        child: Text(
                                          'Registrarse',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: !isLogin ? AppTheme.primary : AppTheme.slateMuted,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!isLogin) ...[
                          const SizedBox(height: 18),
                          const Text(
                            '¿Cómo quieres registrarte en SeniCare?',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.slateMuted),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _buildRoleCard(
                                roleValue: 'client',
                                title: 'Cliente / Familia',
                                subtitle: 'Busco cuidador',
                                icon: Icons.family_restroom_rounded,
                              ),
                              const SizedBox(width: 12),
                              _buildRoleCard(
                                roleValue: 'caregiver',
                                title: 'Cuidador/a',
                                subtitle: 'Ofrezco cuidados',
                                icon: Icons.health_and_safety_rounded,
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 18),
                        Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _emailController,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.email],
                                decoration: const InputDecoration(
                                  labelText: 'Correo Electrónico',
                                  prefixIcon: Icon(Icons.email_outlined),
                                ),
                                keyboardType: TextInputType.emailAddress,
                                validator: (value) {
                                  final trimmed = value?.trim() ?? '';
                                  if (trimmed.isEmpty) return 'Introduce tu correo electrónico';
                                  if (!_emailRegex.hasMatch(trimmed)) {
                                    return 'Introduce un correo válido (ej. nombre@correo.com)';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _passwordController,
                                textInputAction: isLogin ? TextInputAction.done : TextInputAction.next,
                                autofillHints: [
                                  isLogin ? AutofillHints.password : AutofillHints.newPassword,
                                ],
                                onFieldSubmitted: (_) {
                                  if (isLogin) _submit();
                                },
                                decoration: InputDecoration(
                                  labelText: 'Contraseña',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    tooltip: _obscurePassword ? 'Mostrar contraseña' : 'Ocultar contraseña',
                                    icon: Icon(
                                      _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                      color: AppTheme.slateMuted,
                                    ),
                                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                  ),
                                ),
                                obscureText: _obscurePassword,
                                validator: (value) {
                                  if (value == null || value.isEmpty) return 'Introduce tu contraseña';
                                  if (!isLogin && value.length < 8) {
                                    return 'La contraseña debe tener al menos 8 caracteres';
                                  }
                                  return null;
                                },
                              ),
                              if (!isLogin) ...[
                                const SizedBox(height: 14),
                                TextFormField(
                                  controller: _confirmPasswordController,
                                  textInputAction: TextInputAction.done,
                                  autofillHints: const [AutofillHints.newPassword],
                                  onFieldSubmitted: (_) => _submit(),
                                  decoration: InputDecoration(
                                    labelText: 'Confirmar Contraseña',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    suffixIcon: IconButton(
                                      tooltip: _obscureConfirmPassword ? 'Mostrar contraseña' : 'Ocultar contraseña',
                                      icon: Icon(
                                        _obscureConfirmPassword
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                        color: AppTheme.slateMuted,
                                      ),
                                      onPressed: () =>
                                          setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                                    ),
                                  ),
                                  obscureText: _obscureConfirmPassword,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) return 'Confirma tu contraseña';
                                    if (value != _passwordController.text) return 'Las contraseñas no coinciden';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 10),
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  controlAffinity: ListTileControlAffinity.leading,
                                  value: _acceptedLegalTerms,
                                  onChanged: isLoading
                                      ? null
                                      : (val) => setState(() => _acceptedLegalTerms = val ?? false),
                                  title: Wrap(
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      const Text(
                                        'He leído y acepto los ',
                                        style: TextStyle(fontSize: 13),
                                      ),
                                      Semantics(
                                        button: true,
                                        label: 'Ver Términos, Privacidad y Cancelaciones',
                                        child: InkWell(
                                          onTap: () => launchUrl(
                                            Uri.parse('https://senicare-3342d.web.app'),
                                            mode: LaunchMode.externalApplication,
                                          ),
                                          child: const Padding(
                                            padding: EdgeInsets.symmetric(vertical: 6),
                                            child: Text(
                                              'Términos, Privacidad y Cancelaciones',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: AppTheme.primary,
                                                fontWeight: FontWeight.w700,
                                                decoration: TextDecoration.underline,
                                              ),
                                            ),
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
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: isLoading ? null : _submit,
                          child: isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(isLogin ? 'Iniciar Sesión' : 'Crear Cuenta Ahora'),
                        ),
                        if (isLogin)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: isLoading ? null : _showResetPasswordDialog,
                              child: const Text('¿Has olvidado tu contraseña?'),
                            ),
                          ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text('O entra en 1 toque con', style: theme.textTheme.bodySmall),
                            ),
                            const Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: isLoading ? null : _signInWithGoogle,
                          icon: const Icon(Icons.g_mobiledata_rounded, size: 30, color: AppTheme.danger),
                          label: const Text('Continuar con Google'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppTheme.darkSlate,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: const BorderSide(color: AppTheme.borderSubtle, width: 1.5),
                          ),
                        ),
                        if (showAppleSignIn) ...[
                          const SizedBox(height: 10),
                          ElevatedButton.icon(
                            onPressed: isLoading ? null : _signInWithApple,
                            icon: const Icon(Icons.apple, size: 26),
                            label: const Text('Continuar con Apple'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.darkSlate,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: isLoading ? null : () => setState(() => isLogin = !isLogin),
                    child: Text(
                      isLogin
                          ? '¿No tienes cuenta? Toca aquí para registrarte'
                          : '¿Ya tienes cuenta? Toca aquí para iniciar sesión',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
