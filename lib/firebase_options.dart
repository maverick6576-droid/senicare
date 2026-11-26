// File configured manually with build-time defines for iOS store overrides.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static const String _iosApiKey = String.fromEnvironment('FIREBASE_IOS_API_KEY');
  static const String _iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const String _iosBundleId = String.fromEnvironment(
    'FIREBASE_IOS_BUNDLE_ID',
    defaultValue: 'com.senicare.app',
  );
  static const String _iosClientId = String.fromEnvironment('FIREBASE_IOS_CLIENT_ID');

  static FirebaseOptions get _configuredIosOptions {
    return FirebaseOptions(
      apiKey: _iosApiKey.isNotEmpty
          ? _iosApiKey
          : 'AIzaSyAncD22pkv2mW9pLm2p_XVMJXWAz3Bp3DE',
      appId: _iosAppId.isNotEmpty
          ? _iosAppId
          : '1:834223742998:ios:0ca4dbb2425730f6711537',
      messagingSenderId: '834223742998',
      projectId: 'senicare-3342d',
      storageBucket: 'senicare-3342d.firebasestorage.app',
      iosClientId: _iosClientId.isNotEmpty
          ? _iosClientId
          : '834223742998-pkf94sjith52sj98bu433luvjg0mute4.apps.googleusercontent.com',
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
        return _configuredIosOptions;
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
    appId: '1:834223742998:android:ed76a7a6786f7f51711537',
    messagingSenderId: '834223742998',
    projectId: 'senicare-3342d',
    storageBucket: 'senicare-3342d.firebasestorage.app',
  );
}
