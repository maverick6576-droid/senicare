import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:otp/otp.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/screens/screens.dart';
import 'package:senicare/widgets/widgets.dart';

class Admin2FAScreen extends StatefulWidget {
  const Admin2FAScreen({super.key});

  @override
  State<Admin2FAScreen> createState() => _Admin2FAScreenState();
}

class _Admin2FAScreenState extends State<Admin2FAScreen> {
  final _codeController = TextEditingController();
  bool _isLoading = true;
  bool _isSetupMode = false;
  String _secret = '';
  String? _adminEmail;

  @override
  void initState() {
    super.initState();
    _check2FAStatus();
  }

  Future<void> _check2FAStatus() async {
    try {
      Firebase.app(); // Throws if not initialized
    } catch (e) {
      _adminEmail = 'test@admin.com';
      setState(() {
        _isSetupMode = false;
        _isLoading = false;
      });
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      DependencyInjection.auth.signOut();
      return;
    }
    
    _adminEmail = user.email;

    try {
      final doc = await FirebaseFirestore.instance.collection('admins').doc(_adminEmail).get();
      if (doc.exists && doc.data()?['2faEnabled'] == true) {
        _secret = doc.data()?['secret'] ?? '';
        setState(() {
          _isSetupMode = false;
          _isLoading = false;
        });
      } else {
        // Necesita configurar 2FA
        _secret = _generateBase32Secret();
        setState(() {
          _isSetupMode = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error comprobando 2FA: $e');
      setState(() => _isLoading = false);
    }
  }

  String _generateBase32Secret() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final rnd = Random.secure();
    return List.generate(16, (i) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<void> _verifyAndSetup() async {
    final code = _codeController.text.trim();
    if (code.length != 6) return;

    final isValid = _verifyCode(code);
    if (isValid) {
      setState(() => _isLoading = true);
      // Guardar el secret en Firestore
      await FirebaseFirestore.instance.collection('admins').doc(_adminEmail).set({
        'secret': _secret,
        '2faEnabled': true,
        'email': _adminEmail,
      }, SetOptions(merge: true));

      _markVerified();
    } else {
      CustomSnackBar.show(context, message: 'Código incorrecto.', type: SnackBarType.info);
    }
  }

  Future<void> _verifyLogin() async {
    final code = _codeController.text.trim();
    if (code.length != 6) return;

    if (_verifyCode(code)) {
      _markVerified();
    } else {
      CustomSnackBar.show(context, message: 'Código incorrecto.', type: SnackBarType.info);
    }
  }

  bool _verifyCode(String code) {
    // Tolerancia de ventana para TOTP
    final now = DateTime.now().millisecondsSinceEpoch;
    final generatedCode = OTP.generateTOTPCodeString(_secret, now, algorithm: Algorithm.SHA1, isGoogle: true);
    final previousCode = OTP.generateTOTPCodeString(_secret, now - 30000, algorithm: Algorithm.SHA1, isGoogle: true);
    final nextCode = OTP.generateTOTPCodeString(_secret, now + 30000, algorithm: Algorithm.SHA1, isGoogle: true);

    return code == generatedCode || code == previousCode || code == nextCode;
  }

  void _markVerified() {
    final state = context.read<AuthNotifier>();
    state.isAdminVerified2FA = true;
    state.notifyListeners();
    // La UI cambiará automáticamente en app.dart / main_layout.dart
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Seguridad Administrador'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => DependencyInjection.auth.signOut(),
          )
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.security, size: 64, color: AppTheme.primary),
              const SizedBox(height: 24),
              
              if (_isSetupMode) ...[
                Text(
                  'Configura tu Authenticator',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Escanea este código QR con Google Authenticator o Authy:',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    color: Colors.white,
                    child: QrImageView(
                      data: 'otpauth://totp/SeniCare:$_adminEmail?secret=$_secret&issuer=SeniCare',
                      version: QrVersions.auto,
                      size: 200.0,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('O introduce este código manualmente:\n$_secret', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 32),
              ] else ...[
                Text(
                  'Autenticación 2FA',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Introduce el código de 6 dígitos de tu aplicación Authenticator.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
              ],

              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 32, letterSpacing: 8.0),
                decoration: const InputDecoration(
                  hintText: '000000',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isSetupMode ? _verifyAndSetup : _verifyLogin,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: const Text('Verificar Código'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
