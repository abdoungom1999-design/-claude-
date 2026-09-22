import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Carte Portefeuille noire premium (écran Compte) : solde, bouton
/// Recharger et interrupteur pour régler les courses avec le solde.
/// Ponctuellement en noir profond — le reste de l'app reste sur le fond
/// blanc de la charte Sprint (voir [AppColors.noirProfond]).
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.noirProfond, AppColors.noirProfondClair],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.noirProfond.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Portefeuille Santine',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Icon(
                Icons.account_balance_wallet_outlined,
                color: AppColors.orange,
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '$soldeFcfa FCFA',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: onRecharger,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Recharger',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Régler mes courses avec mon solde',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12.5,
                  ),
                ),
              ),
              Switch(
                value: payerAvecSolde,
                onChanged: onTogglePaiement,
                activeThumbColor: AppColors.orange,
                activeTrackColor: AppColors.orange.withValues(alpha: 0.35),
                inactiveThumbColor: Colors.white70,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
