// Firebase Options Configuration for Homecoming App
// This file contains Firebase configuration for the existing homecoming-74f73 project

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAZbMeDAKarfsRZGwg5QQBfH2iIEr_P444',
    appId: '1:632366966739:web:web_app_placeholder',
    messagingSenderId: '632366966739',
    projectId: 'homecoming-74f73',
    authDomain: 'homecoming-74f73.firebaseapp.com',
    databaseURL: 'https://homecoming-74f73-default-rtdb.europe-west1.firebasedatabase.app',
    storageBucket: 'homecoming-74f73.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAZbMeDAKarfsRZGwg5QQBfH2iIEr_P444',
    appId: '1:632366966739:android:351bee9e47901e29ac3126',
    messagingSenderId: '632366966739',
    projectId: 'homecoming-74f73',
    databaseURL: 'https://homecoming-74f73-default-rtdb.europe-west1.firebasedatabase.app',
    storageBucket: 'homecoming-74f73.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyC0V5F_placeholder_ios_key',
    appId: '1:placeholder:ios:placeholder',
    messagingSenderId: 'placeholder',
    projectId: 'homecoming-74f73',
    databaseURL: 'https://homecoming-74f73-default-rtdb.firebaseio.com',
    storageBucket: 'homecoming-74f73.appspot.com',
    iosBundleId: 'com.homecoming.app',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyC0V5F_placeholder_macos_key',
    appId: '1:placeholder:macos:placeholder',
    messagingSenderId: 'placeholder',
    projectId: 'homecoming-74f73',
    databaseURL: 'https://homecoming-74f73-default-rtdb.firebaseio.com',
    storageBucket: 'homecoming-74f73.appspot.com',
    iosBundleId: 'com.homecoming.app',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyC0V5F_placeholder_windows_key',
    appId: '1:placeholder:windows:placeholder',
    messagingSenderId: 'placeholder',
    projectId: 'homecoming-74f73',
    databaseURL: 'https://homecoming-74f73-default-rtdb.firebaseio.com',
    storageBucket: 'homecoming-74f73.appspot.com',
  );
}