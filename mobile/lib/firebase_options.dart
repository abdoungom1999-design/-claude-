import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Configuration Firebase du projet "Sprint VTC" : app web (GitHub
/// Pages) et APK Android de test.
///
/// Valeurs réelles du projet Firebase créé par le Groupe Santine
/// (Console Firebase > Paramètres du projet > Vos applications > SDK
/// setup and configuration). Ces clés (apiKey compris) sont conçues
/// par Firebase pour être embarquées dans le code client et
/// publiques — la sécurité réelle vient des règles Firestore/Auth,
/// pas du secret de ce fichier. Il est donc normal et sûr de les
/// committer telles quelles.
class DefaultFirebaseOptions {
  DefaultFirebaseOptions._();

  static const String _placeholder = 'A_REMPLACER';

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBI86kFD1rOGdm_4q49ytxm7Og9QtB26PM',
    appId: '1:671806634534:web:9c2d22682a5ebcabb6c4e7',
    messagingSenderId: '671806634534',
    projectId: 'sprint-vtc',
    authDomain: 'sprint-vtc.firebaseapp.com',
    storageBucket: 'sprint-vtc.firebasestorage.app',
    measurementId: 'G-8VH7H8XYM6',
  );

  /// Identifiant de l'app Android dans Firebase ("1:…:android:…"),
  /// public comme le reste de ce fichier. Fourni par la CI au moment de
  /// compiler l'APK (`--dart-define=FIREBASE_ANDROID_APP_ID=…`), après
  /// avoir enregistré l'app Android dans le projet si besoin.
  static const String _appIdAndroid = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');

  /// Même projet, même clé que le web ; seul l'identifiant d'app change.
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBI86kFD1rOGdm_4q49ytxm7Og9QtB26PM',
    appId: _appIdAndroid,
    messagingSenderId: '671806634534',
    projectId: 'sprint-vtc',
    storageBucket: 'sprint-vtc.firebasestorage.app',
  );

  /// Système réel (et non `defaultTargetPlatform`, qui vaut Android dans
  /// les tests) ; `kIsWeb` d'abord : `Platform` n'existe pas sur le web.
  static bool get _android => !kIsWeb && Platform.isAndroid;

  /// Configuration de la plateforme en cours (web ou APK Android).
  static FirebaseOptions get currentPlatform => _android ? android : web;

  /// Devient vrai automatiquement dès que les valeurs ci-dessus auront
  /// été remplacées par la vraie configuration du projet Firebase. Sur
  /// Android, il faut en plus l'identifiant d'app fourni à la compilation
  /// (sinon l'app démarre en mode démo plutôt que de planter).
  static bool get estConfigure => web.apiKey != _placeholder && (!_android || _appIdAndroid.isNotEmpty);
}
