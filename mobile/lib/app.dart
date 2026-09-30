import 'package:flutter/material.dart';
import 'core/router/app_router.dart';
import 'core/router/routage_sans_historique.dart';
import 'core/theme/app_theme.dart';

class SprintApp extends StatelessWidget {
  const SprintApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Sprint',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      // Sans écriture dans l'historique du navigateur : le geste « retour » ferme
      // la page en cours et ne ramène jamais à la connexion (voir RouteSansHistorique).
      routerConfig: appRouter.configSansHistorique,
    );
  }
}
