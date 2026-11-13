import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'firebase_options.dart';

import 'package:senicare/core/core.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = ObservabilityService.recordFlutterError;
  PlatformDispatcher.instance.onError = ObservabilityService.recordPlatformError;

  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("⚠️ Failed to load .env file: $e");
  }

  bool firebaseReady = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    firebaseReady = Firebase.apps.isNotEmpty;

    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    try {
      final serverClientId = dotenv.isInitialized
          ? dotenv.env['GOOGLE_SERVER_CLIENT_ID']
          : null;
      await GoogleSignIn.instance.initialize(
        serverClientId: (serverClientId != null && serverClientId.isNotEmpty)
            ? serverClientId
            : '834223742998-2s46vm8a43tip1tbldssoeom5te5o6al.apps.googleusercontent.com',
      );
    } catch (e) {
      debugPrint("Google SignIn init failed: $e");
    }

    // Inicializar el servicio de notificaciones Push (FCM)
    await FCMService.initialize();
  } catch (e) {
    debugPrint("==================================================");
    debugPrint("⚠️ FIREBASE INITIALIZATION FAILED ⚠️");
    debugPrint("Details: $e");
    debugPrint("==================================================");
  }

  await ObservabilityService.initialize(firebaseReady: firebaseReady);

  if (kReleaseMode && !firebaseReady) {
    runApp(const _ProductionBootErrorApp());
    return;
  }

  final configNotifier = ConfigNotifier();
  await configNotifier.loadPreferences();
  ObservabilityService.setUserContext(seniorMode: configNotifier.seniorMode);

  // Initialize Data Layer before the UI
  DependencyInjection.initialize();

  // Initialize Stripe with the provided key
  try {
    String? stripeKey;
    if (dotenv.isInitialized) {
      stripeKey = dotenv.env['STRIPE_PUBLISHABLE_KEY'];
    }
    await StripeService.init(stripeKey);
  } catch (e) {
    debugPrint("⚠️ STRIPE INITIALIZATION FAILED: $e");
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthNotifier()),
        ChangeNotifierProvider(create: (_) => LocationNotifier()),
        ChangeNotifierProvider<ConfigNotifier>.value(value: configNotifier),
        ChangeNotifierProxyProvider2<AuthNotifier, LocationNotifier, CaregiverNotifier>(
          create: (_) => CaregiverNotifier(),
          update: (_, auth, location, caregiverNotifier) {
            final lat = auth.currentClient?.latitude ?? location.latitude;
            final lng = auth.currentClient?.longitude ?? location.longitude;
            caregiverNotifier!.updateLocation(lat, lng);
            return caregiverNotifier;
          },
        ),
        ChangeNotifierProxyProvider2<AuthNotifier, LocationNotifier, JobOfferNotifier>(
          create: (_) => JobOfferNotifier(),
          update: (_, auth, location, jobOfferNotifier) {
            if (!auth.isAuthenticated || auth.currentUserId == null) {
              jobOfferNotifier!.clear(notify: false);
            } else if (auth.currentRole == 'client') {
              jobOfferNotifier!.initForClient(
                auth.effectiveClientId ?? auth.currentUserId!,
              );
            } else if (auth.currentRole == 'caregiver') {
              final lat = auth.currentCaregiver?.latitude ?? location.latitude;
              final lng = auth.currentCaregiver?.longitude ?? location.longitude;
              final maxDistance = auth.currentCaregiver?.maxDistanceRadius ?? 50.0;
              if (lat != null && lng != null) {
                jobOfferNotifier!.initForCaregiver(
                  lat,
                  lng,
                  maxDistance,
                  caregiverId: auth.currentUserId,
                );
              }
            }
            return jobOfferNotifier!;
          },
        ),
        ChangeNotifierProxyProvider<AuthNotifier, BookingNotifier>(
          create: (_) => BookingNotifier(),
          update: (_, auth, bookingNotifier) {
            final scopeId = auth.currentRole == 'client'
                ? (auth.effectiveClientId ?? auth.currentUserId)
                : auth.currentUserId;
            bookingNotifier!.updateAuth(scopeId, auth.currentRole);
            return bookingNotifier;
          },
        ),
        ChangeNotifierProxyProvider<AuthNotifier, ChatNotifier>(
          create: (_) => ChatNotifier(),
          update: (_, auth, chatNotifier) {
            final scopeId = auth.currentRole == 'client'
                ? (auth.effectiveClientId ?? auth.currentUserId)
                : auth.currentUserId;
            chatNotifier!.updateAuth(scopeId, auth.currentRole);
            return chatNotifier;
          },
        ),
      ],
      child: const SeniCareApp(),
    ),
  );
}

class _ProductionBootErrorApp extends StatelessWidget {
  const _ProductionBootErrorApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SeniCare',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.cloud_off_rounded, size: 56, color: Color(0xFFDC2626)),
                SizedBox(height: 16),
                Text(
                  'No se pudo conectar con SeniCare',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 8),
                Text(
                  'Falta la configuración segura de Firebase para este dispositivo o no hay conexión disponible.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Color(0xFF475569)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
