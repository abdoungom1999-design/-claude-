import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'logo_sprint.dart';

/// Écran de démarrage : fond Onyx, logo « S » au centre, rien d'autre.
/// Identique à l'écran de démarrage de `web/index.html` (affiché avant que
/// l'app soit chargée) : le passage de l'un à l'autre est invisible.
///
/// Sert aussi de fond à toute l'app ([SprintApp]) : tant que le routeur n'a
/// encore aucune page à montrer, c'est lui qui est visible, jamais un écran
/// blanc.
class SplashSprint extends StatelessWidget {
  const SplashSprint({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.onyx,
      child: Center(child: LogoSprint()),
    );
  }
}
