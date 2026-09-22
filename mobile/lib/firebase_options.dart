import 'package:firebase_core/firebase_core.dart';

/// Configuration Firebase du projet "Santine" (déploiement web
/// uniquement — Sprint ne cible que Flutter Web pour l'instant).
///
/// Toutes les valeurs ci-dessous sont des PLACEHOLDERS : ce fichier a
/// été préparé pour la migration vers Firebase, mais aucun projet
/// Firebase n'existe encore côté Groupe Santine au moment où il est
/// écrit. Tant qu'elles ne sont pas remplacées par les vraies valeurs
/// (Console Firebase > Paramètres du projet > Vos applications > SDK
/// setup and configuration), [DefaultFirebaseOptions.estConfigure]
/// reste faux et [AuthRepository] continue d'utiliser le mode démo
/// existant — l'app déployée ne casse donc pas tant que ce fichier
/// n'est pas complété. Voir le guide de configuration fourni pour la
/// marche à suivre exacte.
///
/// Remarque : ces clés (apiKey compris) sont conçues par Firebase pour
/// être embarquées dans le code client et publiques — la sécurité
/// réelle vient des règles Firestore/Auth, pas du secret de ce
/// fichier. Il est donc normal et sûr de les committer telles quelles.
class DefaultFirebaseOptions {
  DefaultFirebaseOptions._();

  static const String _placeholder = 'A_REMPLACER';

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: _placeholder,
    appId: _placeholder,
    messagingSenderId: _placeholder,
    projectId: _placeholder,
    authDomain: _placeholder,
    storageBucket: _placeholder,
  );

  /// Devient vrai automatiquement dès que les valeurs ci-dessus auront
  /// été remplacées par la vraie configuration du projet Firebase.
  static bool get estConfigure => web.apiKey != _placeholder;
}
