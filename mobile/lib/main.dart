import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'app.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // N'initialise Firebase que si firebase_options.dart contient une
  // vraie configuration (projet "Sprint VTC") — évite un crash au
  // démarrage si ce fichier devait un jour revenir à ses valeurs
  // placeholder. AuthRepository vérifie la même condition.
  if (DefaultFirebaseOptions.estConfigure) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await _conserverLaSessionSurLeWeb();
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
