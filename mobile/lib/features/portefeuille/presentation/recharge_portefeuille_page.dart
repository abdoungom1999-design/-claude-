import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_fcfa.dart';
import '../../../core/widgets/payment_method_selector.dart';
import '../data/portefeuille_service.dart';
import '../../../core/widgets/onyx_light.dart';

/// Sas de recharge du portefeuille, piloté par le serveur (même principe
/// que `PaymentProcessingPage`) :
///
/// 1. le serveur vérifie la demande et renvoie un lien de paiement ;
/// 2. le client paie sur la page de l'opérateur (aujourd'hui le faux Wave :
///    aucune somme débitée), ouverte dans un nouvel onglet ;
/// 3. l'opérateur confirme au serveur (webhook signé), qui crédite alors le
///    solde ; l'app, qui suit la recharge en temps réel, l'affiche.
///
/// L'app ne décide jamais qu'une recharge a réussi. La page se referme en
/// renvoyant `true` (rechargé) ou le message d'échec à afficher.
class RechargePortefeuillePage extends StatefulWidget {
  RechargePortefeuillePage({
    super.key,
    required this.montantFcfa,
    required this.methode,
    PortefeuilleService? service,
    Future<bool> Function(Uri lien)? ouvrirLien,
  })  : service = service ?? PortefeuilleService(),
        ouvrirLien = ouvrirLien ?? _ouvrirDansUnNouvelOnglet;

  final int montantFcfa;
  final PaymentMethod methode;
  final PortefeuilleService service;

  /// Ouvre la page de paiement de l'opérateur (injectable pour les tests).
  final Future<bool> Function(Uri lien) ouvrirLien;

  static Future<bool> _ouvrirDansUnNouvelOnglet(Uri lien) =>
      launchUrl(lien, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');

  @override
  State<RechargePortefeuillePage> createState() => _RechargePortefeuillePageState();
}

enum _Etape { preparation, aPayer, creditee }

class _RechargePortefeuillePageState extends State<RechargePortefeuillePage> {
  _Etape _etape = _Etape.preparation;
  RechargeDemandee? _recharge;
  bool _pageOuverte = false;
  StreamSubscription<AvancementRecharge?>? _suivi;

  String get _operateur => widget.methode.label;

  @override
  void initState() {
    super.initState();
    _demander();
  }

  @override
  void dispose() {
    _suivi?.cancel();
    super.dispose();
  }

  Future<void> _demander() async {
    final RechargeDemandee recharge;
    try {
      recharge = await widget.service.creerRecharge(
        montantFcfa: widget.montantFcfa,
        methodePaiement: widget.methode.apiValue,
      );
    } on ApiException catch (e) {
      _quitter(e.message);
      return;
    } catch (_) {
      _quitter("La recharge $_operateur n'a pas pu être préparée. Votre solde n'a pas changé.");
      return;
    }
    if (!mounted) return;
    setState(() {
      _recharge = recharge;
      _etape = _Etape.aPayer;
    });
    _suivi = widget.service.streamRecharge(recharge.rechargeId).listen(
          _suivre,
          onError: (_) => _quitter(
            'Le suivi de la recharge a été interrompu. Si vous avez payé, votre solde sera crédité '
            'dans quelques instants.',
          ),
        );
  }

  Future<void> _suivre(AvancementRecharge? avancement) async {
    if (avancement == null || !mounted || _etape == _Etape.creditee) return;
    switch (avancement.statut) {
      case StatutRecharge.enAttente:
        return;
      case StatutRecharge.reussie:
        unawaited(_suivi?.cancel());
        setState(() => _etape = _Etape.creditee);
        await Future.delayed(const Duration(milliseconds: 1200));
        if (mounted) Navigator.of(context).pop(true);
      case StatutRecharge.echouee:
        _quitter("Recharge $_operateur refusée ou annulée. Votre solde n'a pas changé.");
      case StatutRecharge.expiree:
        _quitter("Le délai de paiement est dépassé. Votre solde n'a pas changé.");
      default:
        _quitter(
          "Votre recharge n'a pas pu être validée. Si vous avez été débité, contactez le support Sprint : "
          'vous serez remboursé.',
        );
    }
  }

  Future<void> _payer() async {
    final recharge = _recharge;
    if (recharge == null) return;
    final ouverte = await widget.ouvrirLien(recharge.lienPaiement);
    if (!mounted) return;
    if (!ouverte) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Impossible d'ouvrir la page de paiement $_operateur. Réessayez.")),
      );
      return;
    }
    setState(() => _pageOuverte = true);
  }

  /// Referme la page en renvoyant [message] à l'écran Compte.
  void _quitter(String message) {
    _suivi?.cancel();
    if (mounted) Navigator.of(context).pop(message);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Pas de retour arrière accidentel : la flèche du haut annule.
      canPop: false,
      child: SousPageOnyx(child: Scaffold(
        appBar: AppBar(
          title: const Text('Recharger mon portefeuille'),
          automaticallyImplyLeading: false,
          leading: _etape == _Etape.creditee
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: 'Retour',
                  onPressed: () => _quitter("Recharge annulée. Votre solde n'a pas changé."),
                ),
        ),
        body: SafeArea(
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: switch (_etape) {
                _Etape.preparation => _Attente(
                    key: const ValueKey('preparation'),
                    titre: 'Préparation de votre recharge $_operateur…',
                  ),
                _Etape.aPayer => _APayer(
                    key: ValueKey('aPayer-$_pageOuverte'),
                    operateur: _operateur,
                    montantFcfa: _recharge?.montantFcfa ?? widget.montantFcfa,
                    pageOuverte: _pageOuverte,
                    onPayer: _payer,
                    onAnnuler: () => _quitter("Recharge annulée. Votre solde n'a pas changé."),
                  ),
                _Etape.creditee => _Creditee(key: const ValueKey('creditee'), montantFcfa: widget.montantFcfa),
              },
            ),
          ),
        ),
      )),
    );
  }
}

class _Attente extends StatelessWidget {
  const _Attente({super.key, required this.titre, this.sousTitre});

  final String titre;
  final String? sousTitre;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 64,
            height: 64,
            child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.bleu),
          ),
          const SizedBox(height: 28),
          Text(titre, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          if (sousTitre case final texte?) ...[
            const SizedBox(height: 10),
            Text(
              texte,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13.5, color: AppColors.texteDiscret, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

class _APayer extends StatelessWidget {
  const _APayer({
    super.key,
    required this.operateur,
    required this.montantFcfa,
    required this.pageOuverte,
    required this.onPayer,
    required this.onAnnuler,
  });

  final String operateur;
  final int montantFcfa;
  final bool pageOuverte;
  final VoidCallback onPayer;
  final VoidCallback onAnnuler;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pageOuverte)
              _Attente(
                titre: 'En attente de la confirmation de\nvotre paiement $operateur…',
                sousTitre: 'Payez sur la page $operateur qui vient de s\'ouvrir, puis revenez ici : '
                    'votre solde sera crédité dès la confirmation.',
              )
            else ...[
              const Icon(Icons.account_balance_wallet_outlined, size: 52, color: AppColors.bleu),
              const SizedBox(height: 18),
              Text(formaterFcfa(montantFcfa), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                'Rechargez votre portefeuille Sprint avec $operateur. Le solde sera crédité dès que '
                '$operateur aura confirmé le paiement.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13.5, color: AppColors.texteDiscret, height: 1.4),
              ),
              const SizedBox(height: 28),
            ],
            FilledButton.icon(
              onPressed: onPayer,
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(
                pageOuverte ? 'Rouvrir la page de paiement' : 'Payer avec $operateur · ${formaterFcfa(montantFcfa)}',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.orange,
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: onAnnuler,
              child: const Text('Annuler', style: TextStyle(color: AppColors.texteDiscret, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Creditee extends StatelessWidget {
  const _Creditee({super.key, required this.montantFcfa});

  final int montantFcfa;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(color: AppColors.bleu, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 44),
          ),
          const SizedBox(height: 24),
          const Text('Portefeuille rechargé !', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            '${formaterFcfa(montantFcfa)} ajoutés à votre solde.',
            style: const TextStyle(fontSize: 14, color: AppColors.texteDiscret),
          ),
        ],
      ),
    );
  }
}
