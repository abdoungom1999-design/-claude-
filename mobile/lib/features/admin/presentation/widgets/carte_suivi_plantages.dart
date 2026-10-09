import 'package:flutter/material.dart';
import '../../../../core/suivi/suivi_plantages.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_card.dart';

/// Suivi des plantages (Firebase Crashlytics) : explique ce qui est envoyé et
/// permet de vérifier que les rapports arrivent, en plantant l'app exprès.
/// N'apparaît que sur l'APK Android en version finale : le web (donc l'app
/// installée sur l'iPhone) n'est pas couvert par Crashlytics.
class CarteSuiviPlantages extends StatelessWidget {
  const CarteSuiviPlantages({super.key, this.suivi});

  /// Injectable pour les tests.
  final SuiviDesPlantages? suivi;

  SuiviDesPlantages get _suivi => suivi ?? SuiviDesPlantages.instance;

  Future<void> _tester(BuildContext context) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Planter l\'application ?'),
        content: const Text(
          'L\'application va se fermer volontairement, comme lors d\'un vrai plantage.\n\n'
          'Rouvrez-la ensuite : le rapport part à ce moment-là et apparaît dans la console Firebase '
          '(Crashlytics) au bout de quelques minutes.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Planter pour tester')),
        ],
      ),
    );
    if (confirme == true) _suivi.plantagePourTest();
  }

  @override
  Widget build(BuildContext context) {
    if (!_suivi.testable) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: AppCard(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Suivi des plantages', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text(
                'Les plantages de l\'application Android sont envoyés à Firebase Crashlytics (console Firebase > '
                'Crashlytics), avec la version de l\'app et le modèle du téléphone ; aucun nom, numéro ni identifiant '
                'de compte n\'y est ajouté. Le site web et l\'app installée sur l\'iPhone ne sont pas couverts.',
                style: TextStyle(fontSize: 12.5, color: AppColors.texteDiscret, height: 1.4),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => _tester(context),
                icon: const Icon(Icons.bug_report_outlined, size: 18),
                label: const Text('Tester le suivi'),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.texte),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
