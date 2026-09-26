import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'payment_method_selector.dart';

const _bleuWave = Color(0xFF1DC8F2);
const _orangeOrangeMoney = Color(0xFFFF7900);

/// Bottom sheet "Choisissez votre mode de paiement", affichée après la
/// confirmation du prix et avant toute création de course (voir
/// `PassagerPage` / `ColisPage`). Uniquement Wave et Orange Money —
/// Groupe Santine est passé au 100% mobile money. Le choix referme la
/// sheet puis ouvre le sas de paiement (`PaymentProcessingPage`), seul
/// habilité à créer la course une fois le paiement confirmé.
///
/// Retourne `null` si l'utilisateur ferme la sheet sans choisir : aucune
/// course n'est alors créée.
Future<PaymentMethod?> afficherSelectionPaiementSheet(
  BuildContext context, {
  int? montantFcfa,
}) {
  return showModalBottomSheet<PaymentMethod>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _SelectionPaiementSheet(montantFcfa: montantFcfa),
  );
}

class _SelectionPaiementSheet extends StatelessWidget {
  const _SelectionPaiementSheet({required this.montantFcfa});

  final int? montantFcfa;

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
          if (montantFcfa != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.greyLight,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Text('Montant à payer', style: TextStyle(color: AppColors.grey)),
                  const Spacer(),
                  Text(
                    '$montantFcfa FCFA',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          const _BoutonPaiement(
            methode: PaymentMethod.wave,
            fond: _bleuWave,
            couleurTexte: Colors.white,
            icone: Icons.waves_rounded,
          ),
          const SizedBox(height: 12),
          const _BoutonPaiement(
            methode: PaymentMethod.orangeMoney,
            fond: Colors.black,
            couleurTexte: _orangeOrangeMoney,
            icone: Icons.account_balance_wallet_rounded,
          ),
          const SizedBox(height: 14),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline_rounded, size: 14, color: AppColors.grey),
              SizedBox(width: 6),
              Text(
                'Paiement sécurisé — mode test, aucun débit réel',
                style: TextStyle(fontSize: 12, color: AppColors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BoutonPaiement extends StatelessWidget {
  const _BoutonPaiement({
    required this.methode,
    required this.fond,
    required this.couleurTexte,
    required this.icone,
  });

  final PaymentMethod methode;
  final Color fond;
  final Color couleurTexte;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: fond,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => Navigator.of(context).pop(methode),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: couleurTexte.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(icone, color: couleurTexte, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Payer avec ${methode.label}',
                  style: TextStyle(
                    color: couleurTexte,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(Icons.arrow_forward_rounded, color: couleurTexte),
            ],
          ),
        ),
      ),
    );
  }
}
