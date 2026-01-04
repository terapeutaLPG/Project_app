import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Web platform not configured');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return ios;
      default:
        throw UnsupportedError('Platform not supported');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAIgC-QM-vwS3vP7reO-YH6mgMa_5OeDSE',
    appId: '1:897664912036:android:0a80dde4eeae3c4277f431',
    messagingSenderId: '897664912036',
    projectId: 'hybrydowamapa',
    storageBucket: 'hybrydowamapa.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyClCmgjAENrCMnzIdVcA4b8lYDP31c64H0',
    appId: '1:897664912036:ios:07d61aa8e909d13a77f431',
    messagingSenderId: '897664912036',
    projectId: 'hybrydowamapa',
    storageBucket: 'hybrydowamapa.firebasestorage.app',
    iosBundleId: 'com.example.flutterApplication1',
  );
}
