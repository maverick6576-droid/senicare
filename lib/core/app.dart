import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
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
          content: Semantics(
            liveRegion: true,
            container: true,
            child: const Text(
              'Sin conexión a Internet. Algunas funciones pueden no estar disponibles.',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
          leading: const Icon(Icons.wifi_off, color: Colors.white),
          backgroundColor: AppTheme.danger,
          actions: [
            TextButton(
              onPressed: () => messenger.clearMaterialBanners(),
              child: const Text('Entendido', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildHomeScreen(AuthNotifier auth) {
    if (!auth.isAuthenticated) return const AuthScreen();
    if (auth.currentRole == 'admin') {
      return auth.isAdminVerified2FA
          ? const AdminDashboard()
          : const Admin2FAScreen();
    }
    return auth.onboardingComplete
        ? const MainLayout()
        : const OnboardingRouterScreen();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthNotifier>();
    final config = context.watch<ConfigNotifier>();
    final analyticsObserver = ObservabilityService.analyticsObserver;
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      navigatorObservers: [
        ?analyticsObserver,
      ],
      locale: config.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      title: 'SeniCare',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.getTheme(config.seniorMode),
      home: _buildHomeScreen(auth),
      onGenerateRoute: (settings) {
        final rawName = settings.name ?? '/';
        final uri = Uri.tryParse(rawName);
        final path = uri?.path ?? rawName;
        if (path == '/join') {
          final code = uri?.queryParameters['code'];
          if (code != null && code.trim().isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              auth.setPendingFamilyInviteCode(code.trim());
              auth.consumePendingFamilyInviteIfReady();
            });
          }
        } else if (path.startsWith('/tracking/')) {
          final bookingId = path.substring('/tracking/'.length).trim();
          if (bookingId.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              pendingTrackingBookingId.value = bookingId;
              pendingPushRoute.value = {'type': 'tracking', 'bookingId': bookingId};
            });
          }
        }
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => _buildHomeScreen(auth),
        );
      },
      onUnknownRoute: (settings) => MaterialPageRoute(
        settings: settings,
        builder: (_) => _buildHomeScreen(auth),
      ),
    );
  }
}
