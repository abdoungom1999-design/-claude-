import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_colors.dart';

/// Arrivée sur un accueil (carte plein écran) : le fond Onyx couvre l'écran
/// dès la première image, puis l'accueil apparaît en fondu. L'écran précédent
/// (connexion) n'est donc jamais visible par-dessus la carte pendant la
/// transition (l'animation par défaut d'Android fait glisser et fondre les
/// deux écrans l'un sur l'autre). Rien ne bouge dans les écrans eux-mêmes.
CustomTransitionPage<void> transitionOnyx(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 250),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, secondaryAnimation, child) => ColoredBox(
      color: AppColors.fond,
      child: FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    ),
  );
}
