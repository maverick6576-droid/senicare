import 'dart:math' show cos, sqrt, asin;
import 'package:flutter/material.dart';

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
final ValueNotifier<Map<String, dynamic>?> pendingPushRoute = ValueNotifier<Map<String, dynamic>?>(null);
final ValueNotifier<String?> pendingTrackingBookingId = ValueNotifier<String?>(null);

void showNetworkError(String contextInfo, [Object? error]) {
  rootScaffoldMessengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Text('⚠️ Fallo ($contextInfo): ${error?.toString().split(']').last.trim() ?? "Sin conexión"}'),
      backgroundColor: Colors.amber[900],
      duration: const Duration(seconds: 5),
    ),
  );
}

const bool useFirebaseBackend = true;

double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
  var p = 0.017453292519943295;
  var a = 0.5 - cos((lat2 - lat1) * p) / 2 + cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
  return 12742 * asin(sqrt(a));
}
