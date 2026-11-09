import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/screens/screens.dart';
import 'package:senicare/widgets/widgets.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool isLogin = true;
  bool isLoading = false;
  String selectedRole = 'client';
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (!isLogin) {
      if (password != _confirmPasswordController.text.trim()) {
        CustomSnackBar.show(context, message: 'Las contraseñas no coinciden.', type: SnackBarType.info);
        return;
      }
    }

    setState(() => isLoading = true);
    
    try {
      if (isLogin) {
        await DependencyInjection.auth.signInWithEmail(email, password);
      } else {
        if (mounted) context.read<AuthNotifier>().setRole(selectedRole);
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
    setState(() => isLoading = true);
    try {
      if (mounted && !isLogin) context.read<AuthNotifier>().setRole(selectedRole);
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
    setState(() => isLoading = true);
    try {
      if (mounted && !isLogin) context.read<AuthNotifier>().setRole(selectedRole);
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
    await showDialog(
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
            onPressed: () async {
              final email = resetEmailController.text.trim();
              if (email.isNotEmpty) {
                Navigator.pop(ctx);
                await DependencyInjection.auth.sendPasswordResetEmail(email);
                if (mounted) {
                  CustomSnackBar.show(context, message: 'Correo de recuperación enviado a $email', type: SnackBarType.info);
                }
              }
            },
            child: const Text('Enviar Enlace'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset('assets/images/logo.png', height: 120, width: 120),
              ),
              const SizedBox(height: 48),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Correo Electrónico',
                        border: OutlineInputBorder(),
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
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      decoration: const InputDecoration(
                        labelText: 'Contraseña',
                        border: OutlineInputBorder(),
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
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirmPasswordController,
                        decoration: const InputDecoration(
                          labelText: 'Confirmar Contraseña',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        obscureText: true,
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Requerido';
                          if (value != _passwordController.text) return 'Las contraseñas no coinciden';
                          return null;
                        },
                      ),
                    ],
                  ],
                ),
              ),
              if (!isLogin) ...[
                const SizedBox(height: 16),
                const Text('¿Cómo quieres usar SeniCare?'),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Cliente'),
                        value: 'client',
                        groupValue: selectedRole,
                        onChanged: (v) => setState(() => selectedRole = v!),
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Cuidador'),
                        value: 'caregiver',
                        groupValue: selectedRole,
                        onChanged: (v) => setState(() => selectedRole = v!),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              if (isLoading)
                const Center(child: CircularProgressIndicator())
              else
                ElevatedButton(
                  onPressed: _submit,
                  child: Text(isLogin ? 'Iniciar Sesión' : 'Registrarse'),
                ),
              if (isLogin)
                TextButton(
                  onPressed: _showResetPasswordDialog,
                  child: const Text('¿Has olvidado tu contraseña?'),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('O continuar con', style: theme.textTheme.bodySmall),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _signInWithGoogle,
                icon: const Icon(Icons.account_circle, size: 28),
                label: const Text('Continuar con Google'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: Colors.grey, width: 0.5),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _signInWithApple,
                icon: const Icon(Icons.apple, size: 28),
                label: const Text('Continuar con Apple'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => setState(() => isLogin = !isLogin),
                child: Text(
                  isLogin 
                    ? '¿No tienes cuenta? Regístrate aquí' 
                    : '¿Ya tienes cuenta? Inicia sesión',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
