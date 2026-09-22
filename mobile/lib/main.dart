import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'app.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Tant que firebase_options.dart contient encore ses valeurs
  // placeholder (aucun projet Firebase créé côté Groupe Santine), on
  // n'appelle pas Firebase.initializeApp() : ça éviterait sinon un
  // crash au démarrage avec une config invalide. AuthRepository
  // détecte la même condition et continue d'utiliser le mode démo en
  // attendant.
  if (DefaultFirebaseOptions.estConfigure) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
  }

  runApp(const SprintApp());
}
