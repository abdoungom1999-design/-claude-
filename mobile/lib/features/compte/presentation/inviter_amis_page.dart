import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/premium_dialog.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/secondary_button.dart';

/// Parrainage : code personnel copiable (Clipboard réel).
class InviterAmisPage extends StatelessWidget {
  const InviterAmisPage({super.key});

  static const _code = 'SANTINE-V29K7';

  Future<void> _copier(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: _code));
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
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
              const SizedBox(height: 22),
              const Text(
                'Parrainez et gagnez',
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
              const SizedBox(height: 28),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: AppColors.greyLight,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppColors.orange.withValues(alpha: 0.3),
                    style: BorderStyle.solid,
                  ),
                ),
                child: const Column(
                  children: [
                    Text(
                      'Votre code de parrainage',
                      style: TextStyle(fontSize: 12, color: AppColors.grey),
                    ),
                    SizedBox(height: 6),
                    Text(
                      _code,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        color: AppColors.orange,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Copier le code',
                icon: Icons.copy_all_rounded,
                onPressed: () => _copier(context),
              ),
              const SizedBox(height: 12),
              SecondaryButton(
                label: 'Partager',
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
      ),
    );
  }
}
