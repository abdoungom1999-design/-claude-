import 'package:firebase_core/firebase_core.dart';

/// Configuration Firebase du projet "Sprint VTC" (déploiement web
/// uniquement — Sprint ne cible que Flutter Web pour l'instant).
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

  /// Devient vrai automatiquement dès que les valeurs ci-dessus auront
  /// été remplacées par la vraie configuration du projet Firebase.
  static bool get estConfigure => web.apiKey != _placeholder;
}
