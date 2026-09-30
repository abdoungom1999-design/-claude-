import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../utils/format_fcfa.dart';
import '../../features/portefeuille/data/portefeuille_service.dart';
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
///
/// [portefeuille] (client connecté, Firebase réel) : quand l'interrupteur
/// « Régler mes courses avec mon solde » est actif et que le solde couvre
/// la course, « Payer avec mon solde » passe en premier (un seul appui) ;
/// s'il ne la couvre pas, le client est prévenu et paie par Wave ou Orange
/// Money pour le total.
Future<PaymentMethod?> afficherSelectionPaiementSheet(
  BuildContext context, {
  int? montantFcfa,
  Portefeuille? portefeuille,
}) {
  return showModalBottomSheet<PaymentMethod>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _SelectionPaiementSheet(montantFcfa: montantFcfa, portefeuille: portefeuille),
  );
}

class _SelectionPaiementSheet extends StatelessWidget {
  const _SelectionPaiementSheet({required this.montantFcfa, this.portefeuille});

  final int? montantFcfa;
  final Portefeuille? portefeuille;

  /// Solde à proposer : interrupteur actif et solde suffisant.
  int? get _soldeUtilisable {
    final p = portefeuille;
    final montant = montantFcfa;
    if (p == null || montant == null || !p.payerAvecSolde || !p.couvre(montant)) return null;
    return p.soldeFcfa;
  }

  /// Interrupteur actif mais solde trop juste : on prévient le client.
  int? get _soldeInsuffisant {
    final p = portefeuille;
    final montant = montantFcfa;
    if (p == null || montant == null || !p.payerAvecSolde || p.couvre(montant)) return null;
    return p.soldeFcfa;
  }

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
                    formaterFcfa(montantFcfa!),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          if (_soldeUtilisable case final solde?) ...[
            _BoutonSolde(soldeFcfa: solde, montantFcfa: montantFcfa!),
            const SizedBox(height: 14),
            const Center(
              child: Text('ou par mobile money', style: TextStyle(fontSize: 12.5, color: AppColors.grey)),
            ),
            const SizedBox(height: 14),
          ] else if (_soldeInsuffisant case final solde?) ...[
            _AvertissementSolde(soldeFcfa: solde),
            const SizedBox(height: 14),
          ],
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


/// « Payer avec mon solde » : un appui débite le portefeuille (le serveur
/// vérifie le solde et crée la course dans la même opération).
class _BoutonSolde extends StatelessWidget {
  const _BoutonSolde({required this.soldeFcfa, required this.montantFcfa});

  final int soldeFcfa;
  final int montantFcfa;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.noirProfond,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: const ValueKey('payer-avec-solde'),
        onTap: () => Navigator.of(context).pop(PaymentMethod.portefeuille),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: AppColors.or.withValues(alpha: 0.18), shape: BoxShape.circle),
                alignment: Alignment.center,
                child: const Icon(Icons.account_balance_wallet_outlined, color: AppColors.or, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Payer avec mon solde',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Solde ${formaterFcfa(soldeFcfa)} · il restera ${formaterFcfa(soldeFcfa - montantFcfa)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, color: AppColors.or),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvertissementSolde extends StatelessWidget {
  const _AvertissementSolde({required this.soldeFcfa});

  final int soldeFcfa;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('solde-insuffisant'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: AppColors.orangeLight, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.orangeDark),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Votre solde (${formaterFcfa(soldeFcfa)}) ne couvre pas cette course : '
              'payez le total avec Wave ou Orange Money.',
              style: const TextStyle(fontSize: 12.5, color: AppColors.orangeDark, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
