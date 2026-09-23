import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'payment_method_selector.dart';

/// Bottom sheet "Choisissez votre mode de paiement", affichée juste
/// avant la création réelle de la course (voir `PassagerPage` /
/// `ColisPage`) : le clic sur "Commander" ouvre cette sheet plutôt que
/// d'écrire directement dans Firestore. Chaque option valide
/// immédiatement le choix et referme la sheet — pas de bouton de
/// confirmation séparé. L'encaissement réel (Wave, Orange Money) n'est
/// pas encore intégré : le choix est pour l'instant simplement
/// enregistré avec la course, en préparation du vrai paiement.
///
/// Retourne `null` si l'utilisateur ferme la sheet sans choisir
/// (glissement vers le bas, tap en dehors) : dans ce cas, aucune course
/// n'est créée.
Future<PaymentMethod?> afficherSelectionPaiementSheet(BuildContext context) {
  return showModalBottomSheet<PaymentMethod>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _SelectionPaiementSheet(),
  );
}

class _SelectionPaiementSheet extends StatelessWidget {
  const _SelectionPaiementSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.greyBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Choisissez votre mode de paiement',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),
          const _OptionPaiement(
            emoji: '🌊',
            icon: Icons.water_drop_rounded,
            couleur: Color(0xFF1DA1F2),
            methode: PaymentMethod.wave,
          ),
          const SizedBox(height: 12),
          const _OptionPaiement(
            emoji: '🧡',
            icon: Icons.account_balance_wallet_rounded,
            couleur: AppColors.orange,
            methode: PaymentMethod.orangeMoney,
          ),
          const SizedBox(height: 12),
          _OptionPaiement(
            emoji: '💵',
            icon: Icons.payments_rounded,
            couleur: Colors.green.shade600,
            methode: PaymentMethod.cash,
          ),
        ],
      ),
    );
  }
}

class _OptionPaiement extends StatelessWidget {
  const _OptionPaiement({
    required this.emoji,
    required this.icon,
    required this.couleur,
    required this.methode,
  });

  final String emoji;
  final IconData icon;
  final Color couleur;
  final PaymentMethod methode;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).pop(methode),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.greyLight,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: couleur.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: couleur, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                '$emoji  ${methode.label}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.grey),
          ],
        ),
      ),
    );
  }
}
