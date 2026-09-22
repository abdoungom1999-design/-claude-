import 'package:firebase_core/firebase_core.dart';
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
    await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
  }

  runApp(const SprintApp());
}
