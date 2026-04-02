// Generated Firebase options for this project.
// Values taken from android/app/google-services.json

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Web platform is not configured for Firebase.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError('iOS is not configured for Firebase yet.');
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAbCI7QVLWNrAwqCuJETNDqBeGl9mFaXv4',
    appId: '1:594414222454:android:9d293c828bc46803e5b357',
    messagingSenderId: '594414222454',
    projectId: 'exstranger-a6fc3',
    storageBucket: 'exstranger-a6fc3.firebasestorage.app',
  );
}
