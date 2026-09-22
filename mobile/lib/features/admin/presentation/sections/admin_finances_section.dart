import 'package:flutter/material.dart';
import '../../../../core/demo/admin_demo_data.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/premium_dialog.dart';
import '../../../../core/widgets/primary_button.dart';

/// Page "Finances" : paramètres vitaux de tarification. Simulée : modifie
/// uniquement [AdminDemoData], sans effet sur le calcul de prix réel de
/// l'app (voir la note dans [AdminDemoData]).
class AdminFinancesSection extends StatefulWidget {
  const AdminFinancesSection({super.key});

  @override
  State<AdminFinancesSection> createState() => _AdminFinancesSectionState();
}

class _AdminFinancesSectionState extends State<AdminFinancesSection> {
  late final _commissionController = TextEditingController(
    text: AdminDemoData.commissionPourcent.toStringAsFixed(1),
  );
  late final _prixBaseController = TextEditingController(
    text: '${AdminDemoData.prixBaseFcfa}',
  );
  late final _prixKmController = TextEditingController(
    text: '${AdminDemoData.prixParKmFcfa}',
  );

  @override
  void dispose() {
    _commissionController.dispose();
    _prixBaseController.dispose();
    _prixKmController.dispose();
    super.dispose();
  }

  void _sauvegarder() {
    final commission = double.tryParse(_commissionController.text.replaceAll(',', '.'));
    final prixBase = int.tryParse(_prixBaseController.text);
    final prixKm = int.tryParse(_prixKmController.text);

    if (commission == null || prixBase == null || prixKm == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Merci de saisir des valeurs numériques valides.')),
      );
      return;
    }

    AdminDemoData.mettreAJourConfigFinance(
      commissionPourcent: commission,
      prixBaseFcfa: prixBase,
      prixParKmFcfa: prixKm,
    );

    PremiumDialog.afficher(
      context,
      icon: Icons.savings_outlined,
      titre: 'Configuration enregistrée',
      message: 'Les nouveaux paramètres financiers ont bien été sauvegardés.',
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
              'Paramètres financiers',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Ces valeurs pilotent la commission Santine et la tarification des courses.',
              style: TextStyle(fontSize: 12.5, color: AppColors.grey),
            ),
            const SizedBox(height: 28),
            _ChampFinance(
              label: 'Commission prélevée (%)',
              controller: _commissionController,
              suffixe: '%',
            ),
            const SizedBox(height: 18),
            _ChampFinance(
              label: 'Prix de base de la course (FCFA)',
              controller: _prixBaseController,
              suffixe: 'FCFA',
            ),
            const SizedBox(height: 18),
            _ChampFinance(
              label: 'Prix par kilomètre (FCFA)',
              controller: _prixKmController,
              suffixe: 'FCFA/km',
            ),
            const SizedBox(height: 28),
            PrimaryButton(
              label: 'Sauvegarder la configuration',
              icon: Icons.save_outlined,
              onPressed: _sauvegarder,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChampFinance extends StatelessWidget {
  const _ChampFinance({
    required this.label,
    required this.controller,
    required this.suffixe,
  });

  final String label;
  final TextEditingController controller;
  final String suffixe;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            suffixText: suffixe,
            filled: true,
            fillColor: AppColors.greyLight,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}
