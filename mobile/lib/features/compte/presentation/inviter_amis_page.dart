import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/demo/demo_data.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/premium_dialog.dart';
import '../../../core/widgets/primary_button.dart';

/// Parrainage : code personnel copiable (Clipboard réel) et statistiques
/// de parrainage.
class InviterAmisPage extends StatelessWidget {
  const InviterAmisPage({super.key});

  Future<void> _copier(BuildContext context) async {
    await Clipboard.setData(
      const ClipboardData(text: DemoData.codeParrainage),
    );
    if (!context.mounted) return;
    PremiumDialog.afficher(
      context,
      icon: Icons.copy_all_rounded,
      titre: 'Code copié !',
      message: 'Votre code de parrainage a été copié dans le presse-papiers.',
      succes: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inviter des amis')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 84,
                height: 84,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.orange, AppColors.orangeDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.card_giftcard_rounded,
                  color: Colors.white,
                  size: 38,
                ),
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Parrainez et gagnez',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Partagez votre code : vos amis reçoivent une réduction sur '
              'leur première course, et vous une course offerte dès leur '
              'première commande.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.grey, height: 1.5),
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: AppColors.greyLight,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.orange.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  const Text(
                    'Votre code de parrainage',
                    style: TextStyle(fontSize: 12, color: AppColors.grey),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        DemoData.codeParrainage,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 3,
                          color: AppColors.orange,
                        ),
                      ),
                      const SizedBox(width: 10),
                      InkWell(
                        onTap: () => _copier(context),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.greyBorder),
                          ),
                          child: const Icon(
                            Icons.copy_all_rounded,
                            size: 16,
                            color: AppColors.orange,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Row(
              children: [
                Expanded(
                  child: _BlocStat(
                    valeur: '${DemoData.parrainageInvites}',
                    label: 'Invités',
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: _BlocStat(
                    valeur: '${DemoData.parrainageQualifies}',
                    label: 'Qualifiés',
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: _BlocStat(
                    valeur: '${DemoData.parrainageGainsFcfa} FCFA',
                    label: 'Gagnés',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            PrimaryButton(
              label: 'Partager mon invitation',
              icon: Icons.share_outlined,
              onPressed: () => PremiumDialog.afficher(
                context,
                icon: Icons.share_outlined,
                titre: 'Partagé !',
                message: 'Votre code de parrainage a été partagé avec succès.',
                succes: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlocStat extends StatelessWidget {
  const _BlocStat({required this.valeur, required this.label});

  final String valeur;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.greyBorder),
      ),
      child: Column(
        children: [
          Text(
            valeur,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.grey)),
        ],
      ),
    );
  }
}
