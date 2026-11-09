import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/screens/screens.dart';

class SeniCareApp extends StatefulWidget {
  const SeniCareApp({super.key});

  @override
  State<SeniCareApp> createState() => _SeniCareAppState();
}

class _SeniCareAppState extends State<SeniCareApp> {
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final isOffline = results.isEmpty || results.every((r) => r == ConnectivityResult.none);
      if (isOffline != _isOffline) {
        setState(() => _isOffline = isOffline);
        _showConnectivityBanner(isOffline);
      }
    });
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    super.dispose();
  }

  void _showConnectivityBanner(bool isOffline) {
    final messenger = rootScaffoldMessengerKey.currentState;
    if (messenger == null) return;
    
    messenger.clearMaterialBanners();
    if (isOffline) {
      messenger.showMaterialBanner(
        MaterialBanner(
          content: const Text('Sin conexión a Internet', style: TextStyle(color: Colors.white)),
          leading: const Icon(Icons.wifi_off, color: Colors.white),
          backgroundColor: Colors.red.shade600,
          actions: [
            TextButton(
              onPressed: () => messenger.clearMaterialBanners(),
              child: const Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthNotifier>();
    final config = context.watch<ConfigNotifier>();
    // final state = context.watch<AppState>();
    return MaterialApp(
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      title: 'SeniCare',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.getTheme(config.seniorMode),
      home: auth.isAuthenticated 
          ? (auth.currentRole == 'admin' 
              ? (auth.isAdminVerified2FA ? const AdminDashboard() : const Admin2FAScreen())
              : (auth.currentRole == 'caregiver'
                  ? const MainLayout()
                  : (auth.onboardingComplete ? const MainLayout() : OnboardingRouterScreen())))
          : const AuthScreen(),
    );
  }
}
