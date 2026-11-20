import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Numéro de la publication en service, donné à la compilation par la CI
/// (`--dart-define=NUMERO_PUBLICATION=<numéro du run>`, le même que l'APK
/// « 0.1.0 (N) »). Vide en développement et dans les tests.
const String numeroPublication = String.fromEnvironment('NUMERO_PUBLICATION');

/// « v146 », discret, en bas des écrans de connexion et du dossier chauffeur :
/// permet de vérifier d'un coup d'œil que le téléphone exécute bien la dernière
/// version (et non un ancien code resté en mémoire). Rien n'est affiché si le
/// numéro n'est pas connu.
class NumeroVersion extends StatelessWidget {
  const NumeroVersion({super.key, this.numero = numeroPublication});

  final String numero;

  @override
  Widget build(BuildContext context) {
    if (numero.trim().isEmpty) return const SizedBox.shrink();
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          'v${numero.trim()}',
          key: const ValueKey('numero-version'),
          style: TextStyle(fontSize: 11, color: AppColors.texteDiscret.withValues(alpha: 0.7), letterSpacing: 0.5),
        ),
      ),
    );
  }
}
