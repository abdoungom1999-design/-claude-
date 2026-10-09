import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'app.dart';
import 'core/suivi/suivi_plantages.dart';
import 'firebase_options.dart';

/// Réservé à l'essai de la CI sur émulateur (.github/workflows/essai-android.yml) :
/// l'app se plante exprès dix secondes après son démarrage, pour vérifier que
/// Crashlytics reçoit le rapport. Jamais défini dans l'APK publié : sans effet.
const _essaiPlantage = bool.fromEnvironment('ESSAI_PLANTAGE');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // N'initialise Firebase que si firebase_options.dart contient une
  // vraie configuration (projet "Sprint VTC") — évite un crash au
  // démarrage si ce fichier devait un jour revenir à ses valeurs
  // placeholder. AuthRepository vérifie la même condition.
  if (DefaultFirebaseOptions.estConfigure) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await _conserverLaSessionSurLeWeb();
    // Android : les plantages partent vers Crashlytics (sans effet ailleurs, jamais bloquant).
    await SuiviDesPlantages.instance.brancher();
    if (_essaiPlantage) {
      unawaited(Future<void>.delayed(const Duration(seconds: 10), SuiviDesPlantages.instance.plantagePourTest));
    }
  }

  runApp(const SprintApp());
}

/// Web : la session reste enregistrée dans le navigateur (stockage local)
/// jusqu'à un appui sur « Se déconnecter », même après fermeture de
/// l'onglet ou de l'app installée. C'est déjà le réglage par défaut de
/// Firebase ; on le pose explicitement pour qu'un changement de défaut ne
/// déconnecte personne. Sur téléphone, la session est conservée d'office.
Future<void> _conserverLaSessionSurLeWeb() async {
  if (!kIsWeb) return;
  try {
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
  } on Object catch (e) {
    // Stockage du navigateur refusé (navigation privée…) : le défaut s'applique.
    debugPrint('Session non conservée explicitement : $e');
  }
}
