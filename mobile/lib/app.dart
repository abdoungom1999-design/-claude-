import 'package:flutter/material.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/splash_sprint.dart';

class SprintApp extends StatelessWidget {
  const SprintApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Sprint',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.sombre,
      routerConfig: appRouter,
      // Écran de démarrage sous les pages : visible tant que le routeur n'a
      // rien à afficher (jamais d'écran blanc), entièrement recouvert dès
      // qu'une page est là.
      builder: (context, page) => Stack(
        fit: StackFit.expand,
        children: [
          const SplashSprint(),
          if (page != null) page,
        ],
      ),
    );
  }
}
