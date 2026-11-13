// File configured manually with build-time defines for iOS store overrides.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static const String _iosApiKey = String.fromEnvironment('FIREBASE_IOS_API_KEY');
  static const String _iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const String _iosBundleId = String.fromEnvironment(
    'FIREBASE_IOS_BUNDLE_ID',
    defaultValue: 'com.example.senicare',
  );
  static const String _iosClientId = String.fromEnvironment('FIREBASE_IOS_CLIENT_ID');

  static FirebaseOptions? get _configuredIosOptions {
    if (_iosApiKey.isEmpty || _iosAppId.isEmpty) return null;
    return FirebaseOptions(
      apiKey: _iosApiKey,
      appId: _iosAppId,
      messagingSenderId: '834223742998',
      projectId: 'senicare-3342d',
      storageBucket: 'senicare-3342d.firebasestorage.app',
      iosClientId: _iosClientId.isNotEmpty ? _iosClientId : null,
      iosBundleId: _iosBundleId,
    );
  }

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        final iosOptions = _configuredIosOptions;
        if (iosOptions != null) return iosOptions;
        throw UnsupportedError(
          'Faltan credenciales Firebase para iOS: añade ios/Runner/GoogleService-Info.plist '
          'o compila con --dart-define=FIREBASE_IOS_API_KEY y FIREBASE_IOS_APP_ID.',
        );
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return web;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyC_eC5MRYuwz4qVMnbozWt9UYDQvzOkG_8',
    appId: '1:834223742998:web:4a5e695dce4de695711537',
    messagingSenderId: '834223742998',
    projectId: 'senicare-3342d',
    authDomain: 'senicare-3342d.firebaseapp.com',
    storageBucket: 'senicare-3342d.firebasestorage.app',
    measurementId: 'G-EYYEKLCDTJ',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyC_eC5MRYuwz4qVMnbozWt9UYDQvzOkG_8',
    appId: '1:834223742998:android:b53f8169c429d5d7711537',
    messagingSenderId: '834223742998',
    projectId: 'senicare-3342d',
    storageBucket: 'senicare-3342d.firebasestorage.app',
  );
}
