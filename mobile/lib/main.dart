import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'app.dart';
import 'core/widgets/racine_de_session.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Site et iPhone : le geste « retour » ferme la page en cours (voir RouteSansHistorique).
  configurerHistoriqueNavigateur();

  // N'initialise Firebase que si firebase_options.dart contient une
  // vraie configuration (projet "Sprint VTC") — évite un crash au
  // démarrage si ce fichier devait un jour revenir à ses valeurs
  // placeholder. AuthRepository vérifie la même condition.
  if (DefaultFirebaseOptions.estConfigure) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }

  runApp(const SprintApp());
}
