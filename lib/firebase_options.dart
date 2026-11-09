// File generated manually to bypass CLI requirements for non-admin users

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for ios - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.macOS:
        return web;
      case TargetPlatform.windows:
        return web;
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
