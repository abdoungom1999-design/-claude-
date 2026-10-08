import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'onyx_vert.dart';

/// Carte Portefeuille (écran Compte), charte Onyx & Vert : verre sombre
/// cerné d'un liseré vert et d'une lueur, solde en grand en clair, bouton
/// Recharger vert (texte Onyx) et interrupteur pour régler les courses avec
/// le solde.
class WalletCard extends StatelessWidget {
  const WalletCard({
    super.key,
    required this.soldeFcfa,
    required this.payerAvecSolde,
    required this.onTogglePaiement,
    required this.onRecharger,
  });

  final int soldeFcfa;
  final bool payerAvecSolde;
  final ValueChanged<bool> onTogglePaiement;
  final VoidCallback onRecharger;

  @override
  Widget build(BuildContext context) {
    return CarteVerre(
      rayon: 28,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
      contour: AppColors.vert.withValues(alpha: 0.55),
      lueur: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: AppColors.vertTeinte, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.account_balance_wallet_outlined, color: AppColors.vert, size: 18),
              ),
              const SizedBox(width: 10),
              const Text(
                'Portefeuille Santine',
                style: TextStyle(color: AppColors.texteDiscret, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '$soldeFcfa FCFA',
            key: const ValueKey('solde-portefeuille'),
            style: const TextStyle(color: AppColors.texte, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.8),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: onRecharger,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.vert,
                foregroundColor: AppColors.onyx,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                elevation: 0,
              ),
              child: const Text('Recharger', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.bordVerre),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Régler mes courses avec mon solde',
                  style: TextStyle(color: AppColors.texte, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
              Switch(
                value: payerAvecSolde,
                onChanged: onTogglePaiement,
                activeThumbColor: AppColors.onyx,
                activeTrackColor: AppColors.vert,
                inactiveThumbColor: AppColors.texteDiscret,
                inactiveTrackColor: AppColors.carteHaute,
                trackOutlineColor: WidgetStateProperty.resolveWith(
                  (etats) => etats.contains(WidgetState.selected) ? AppColors.vert : AppColors.bord,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
