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
  bool isLogin = true;
  bool isLoading = false;
  bool _acceptedLegalTerms = false;
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (!isLogin) {
      if (password != _confirmPasswordController.text.trim()) {
        CustomSnackBar.show(context, message: 'Las contraseñas no coinciden.', type: SnackBarType.info);
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
        CustomSnackBar.show(context, message: 'Error de autenticación: $e', type: SnackBarType.info);
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _signInWithGoogle() async {
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
        CustomSnackBar.show(context, message: 'Error al acceder con Google: $e', type: SnackBarType.info);
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _signInWithApple() async {
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
        CustomSnackBar.show(context, message: 'Error al acceder con Apple: $e', type: SnackBarType.info);
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _showResetPasswordDialog() async {
    final resetEmailController = TextEditingController(text: _emailController.text);
    try {
      final submittedEmail = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Recuperar contraseña'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Introduce tu correo para recibir un enlace de recuperación.'),
              const SizedBox(height: 16),
              TextField(
                controller: resetEmailController,
                decoration: const InputDecoration(
                  labelText: 'Correo Electrónico',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () {
                final email = resetEmailController.text.trim();
                if (email.isEmpty || !email.contains('@')) return;
                Navigator.pop(ctx, email);
              },
              child: const Text('Enviar Enlace'),
            ),
          ],
        ),
      );
      if (submittedEmail != null && submittedEmail.isNotEmpty) {
        await DependencyInjection.auth.sendPasswordResetEmail(submittedEmail);
        if (mounted) {
          CustomSnackBar.show(
            context,
            message: 'Correo de recuperación enviado a $submittedEmail',
            type: SnackBarType.info,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        CustomSnackBar.show(
          context,
          message: 'No se pudo enviar el correo de recuperación: $e',
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
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => selectedRole = roleValue),
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
            children: [
              Icon(
                icon,
                size: 28,
                color: isSelected ? AppTheme.primary : AppTheme.slateMuted,
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
                  fontSize: 11,
                  color: AppTheme.slateMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                  const SizedBox(height: 16),
                  Text(
                    'SeniCare',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppTheme.darkSlate,
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
                        // Selector claro Iniciar Sesión vs Crear Cuenta
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
                                child: GestureDetector(
                                  onTap: () => setState(() => isLogin = true),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
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
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => setState(() => isLogin = false),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
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
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          isLogin ? 'Tu perfil en SeniCare:' : '¿Cómo quieres registrarte en SeniCare?',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.slateMuted),
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
                        const SizedBox(height: 18),
                        Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _emailController,
                                decoration: const InputDecoration(
                                  labelText: 'Correo Electrónico',
                                  prefixIcon: Icon(Icons.email_outlined),
                                ),
                                keyboardType: TextInputType.emailAddress,
                                validator: (value) {
                                  if (value == null || value.isEmpty) return 'Requerido';
                                  if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                                    return 'Correo inválido';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _passwordController,
                                decoration: const InputDecoration(
                                  labelText: 'Contraseña',
                                  prefixIcon: Icon(Icons.lock_outline),
                                ),
                                obscureText: true,
                                validator: (value) {
                                  if (value == null || value.isEmpty) return 'Requerido';
                                  if (!isLogin && value.length < 8) return 'Mínimo 8 caracteres';
                                  return null;
                                },
                              ),
                              if (!isLogin) ...[
                                const SizedBox(height: 14),
                                TextFormField(
                                  controller: _confirmPasswordController,
                                  decoration: const InputDecoration(
                                    labelText: 'Confirmar Contraseña',
                                    prefixIcon: Icon(Icons.lock_outline),
                                  ),
                                  obscureText: true,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) return 'Requerido';
                                    if (value != _passwordController.text) return 'Las contraseñas no coinciden';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 10),
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  controlAffinity: ListTileControlAffinity.leading,
                                  value: _acceptedLegalTerms,
                                  onChanged: (val) => setState(() => _acceptedLegalTerms = val ?? false),
                                  title: Wrap(
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      const Text(
                                        'He leído y acepto los ',
                                        style: TextStyle(fontSize: 12.5),
                                      ),
                                      InkWell(
                                        onTap: () => launchUrl(
                                          Uri.parse('https://senicare-3342d.web.app'),
                                          mode: LaunchMode.externalApplication,
                                        ),
                                        child: const Text(
                                          'Términos, Privacidad y Cancelaciones',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            color: AppTheme.primary,
                                            fontWeight: FontWeight.w700,
                                            decoration: TextDecoration.underline,
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
                        if (isLoading)
                          const Center(child: CircularProgressIndicator())
                        else
                          ElevatedButton(
                            onPressed: _submit,
                            child: Text(isLogin ? 'Iniciar Sesión' : 'Crear Cuenta Ahora'),
                          ),
                        if (isLogin)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _showResetPasswordDialog,
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
                          onPressed: _signInWithGoogle,
                          icon: const Icon(Icons.g_mobiledata_rounded, size: 30, color: Colors.redAccent),
                          label: const Text('Continuar con Google'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppTheme.darkSlate,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: const BorderSide(color: AppTheme.borderSubtle, width: 1.5),
                          ),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton.icon(
                          onPressed: _signInWithApple,
                          icon: const Icon(Icons.apple, size: 26),
                          label: const Text('Continuar con Apple'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.darkSlate,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => setState(() => isLogin = !isLogin),
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
