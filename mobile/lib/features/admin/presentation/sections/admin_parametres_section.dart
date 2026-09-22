import 'package:flutter/material.dart';
import '../../../../core/demo/admin_demo_data.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/premium_dialog.dart';
import '../../../../core/widgets/primary_button.dart';

/// Page "Paramètres" : réglages généraux de la plateforme (villes
/// actives, mode maintenance). Simulée, comme le reste de la Tour de
/// Contrôle.
class AdminParametresSection extends StatefulWidget {
  const AdminParametresSection({super.key});

  @override
  State<AdminParametresSection> createState() => _AdminParametresSectionState();
}

class _AdminParametresSectionState extends State<AdminParametresSection> {
  late final Set<String> _villesActives = {...AdminDemoData.villesActives};
  late bool _modeMaintenance = AdminDemoData.modeMaintenance;

  void _sauvegarder() {
    AdminDemoData.mettreAJourParametresPlateforme(
      villesActives: _villesActives,
      modeMaintenance: _modeMaintenance,
    );
    PremiumDialog.afficher(
      context,
      icon: Icons.tune_rounded,
      titre: 'Paramètres enregistrés',
      message: 'La configuration de la plateforme a bien été mise à jour.',
      succes: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: AppCard(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paramètres de la plateforme',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Application Sprint · v1.4.0',
              style: TextStyle(fontSize: 12.5, color: AppColors.grey),
            ),
            const SizedBox(height: 26),
            const Text(
              'Villes actives',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final ville in AdminDemoData.villesDisponibles)
                  FilterChip(
                    label: Text(ville),
                    selected: _villesActives.contains(ville),
                    selectedColor: AppColors.orangeLight,
                    checkmarkColor: AppColors.orange,
                    labelStyle: TextStyle(
                      color: _villesActives.contains(ville)
                          ? AppColors.orangeDark
                          : AppColors.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                    backgroundColor: AppColors.greyLight,
                    side: BorderSide.none,
                    onSelected: (selectionne) => setState(() {
                      if (selectionne) {
                        _villesActives.add(ville);
                      } else {
                        _villesActives.remove(ville);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.greyLight,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Mode maintenance',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _modeMaintenance
                              ? "L'application est actuellement fermée aux nouvelles commandes."
                              : "L'application fonctionne normalement.",
                          style: const TextStyle(fontSize: 11.5, color: AppColors.grey),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _modeMaintenance,
                    activeThumbColor: AppColors.orange,
                    onChanged: (valeur) => setState(() => _modeMaintenance = valeur),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            PrimaryButton(
              label: 'Enregistrer',
              icon: Icons.save_outlined,
              onPressed: _sauvegarder,
            ),
          ],
        ),
      ),
    );
  }
}
