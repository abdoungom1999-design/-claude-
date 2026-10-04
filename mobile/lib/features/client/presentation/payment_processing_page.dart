import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_fcfa.dart';
import '../../../core/widgets/payment_method_selector.dart';
import '../../courses/data/course_service.dart';
import 'suivi_course_page.dart';
import '../../../core/widgets/onyx_light.dart';

/// Sas de paiement obligatoire (100% mobile money), piloté par le
/// serveur :
///
/// 1. le serveur recalcule le prix et renvoie un lien de paiement
///    ([CourseService.creerPaiement]) ;
/// 2. le client paie sur la page de l'opérateur, ouverte dans un nouvel
///    onglet (aujourd'hui le faux Wave : aucune somme débitée) ;
/// 3. l'opérateur confirme le paiement au serveur (webhook signé), qui
///    crée alors la course, ce qui réveille le radar des chauffeurs ;
///    l'app, qui suit la commande en temps réel
///    ([CourseService.streamCommande]), passe à [SuiviCoursePage].
///
/// L'app ne décide jamais qu'un paiement a réussi. En cas de refus,
/// d'expiration ou d'abandon, aucune course n'est créée : la page se
/// referme en renvoyant le message à l'écran de commande, qui l'affiche.
class PaymentProcessingPage extends StatefulWidget {
  PaymentProcessingPage({
    super.key,
    required this.methode,
    required this.type,
    required this.adresseDepart,
    required this.adresseArrivee,
    required this.prixFcfa,
    required this.points,
    CourseService? courseService,
    Future<bool> Function(Uri lien)? ouvrirLien,
  })  : courseService = courseService ?? CourseService(),
        ouvrirLien = ouvrirLien ?? _ouvrirDansUnNouvelOnglet;

  final PaymentMethod methode;
  final String type;
  final String adresseDepart;
  final String adresseArrivee;
  final int prixFcfa;

  /// Coordonnées du trajet : le serveur en déduit la distance et le prix,
  /// et les enregistre avec la course (suivi d'approche côté client).
  final PointsCourse points;
  final CourseService courseService;

  /// Ouvre la page de paiement de l'opérateur (injectable pour les tests).
  final Future<bool> Function(Uri lien) ouvrirLien;

  static Future<bool> _ouvrirDansUnNouvelOnglet(Uri lien) =>
      launchUrl(lien, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');

  @override
  State<PaymentProcessingPage> createState() => _PaymentProcessingPageState();
}

enum _EtapePaiement { preparation, aPayer, confirme }

class _PaymentProcessingPageState extends State<PaymentProcessingPage> {
  _EtapePaiement _etape = _EtapePaiement.preparation;
  DemandePaiement? _demande;
  bool _pageOuverte = false;
  StreamSubscription<CommandePaiement?>? _suivi;

  String get _operateur => widget.methode.label;

  @override
  void initState() {
    super.initState();
    _demanderPaiement();
  }

  @override
  void dispose() {
    _suivi?.cancel();
    super.dispose();
  }

  Future<void> _demanderPaiement() async {
    final DemandePaiement demande;
    try {
      demande = await widget.courseService.creerPaiement(
        type: widget.type,
        adresseDepart: widget.adresseDepart,
        adresseArrivee: widget.adresseArrivee,
        prixFcfa: widget.prixFcfa,
        methodePaiement: widget.methode.apiValue,
        points: widget.points,
      );
    } on PrixModifie catch (e) {
      _abandonner(
        'Le prix de ce trajet vient de changer : ${formaterFcfa(e.nouveauPrixFcfa)}. '
        "Aucune course n'a été créée : vérifiez le nouveau prix avant de commander.",
      );
      return;
    } on ApiException catch (e) {
      _abandonner("${e.message} Aucune course n'a été créée.");
      return;
    } catch (_) {
      _abandonner("Le paiement $_operateur n'a pas pu être préparé. Aucune course n'a été créée.");
      return;
    }
    if (!mounted) return;
    setState(() {
      _demande = demande;
      // Payée avec le solde : rien à ouvrir, la course est déjà créée ; on
      // reste sur l'écran d'attente jusqu'à ce que le suivi de la commande
      // la confirme (quasi immédiat).
      if (!demande.payeParSolde) _etape = _EtapePaiement.aPayer;
    });
    _suivi = widget.courseService.streamCommande(demande.commandeId).listen(
          _suivre,
          onError: (_) => _abandonner(
            'Le suivi du paiement a été interrompu. Si vous avez payé, votre course apparaîtra '
            'dans Activité.',
          ),
        );
  }

  Future<void> _suivre(CommandePaiement? commande) async {
    if (commande == null || !mounted || _etape == _EtapePaiement.confirme) return;
    switch (commande.statut) {
      case StatutCommande.enAttente:
        return;
      case StatutCommande.payee:
        final courseId = commande.courseId;
        if (courseId == null) return;
        unawaited(_suivi?.cancel());
        setState(() => _etape = _EtapePaiement.confirme);
        await Future.delayed(const Duration(milliseconds: 900));
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => SuiviCoursePage(courseId: courseId)),
        );
      case StatutCommande.echouee:
        _abandonner("Paiement $_operateur refusé ou annulé. Aucune course n'a été créée.");
      case StatutCommande.expiree:
        _abandonner("Le délai de paiement est dépassé. Aucune course n'a été créée.");
      default:
        _abandonner(
          "Votre paiement n'a pas pu être validé. Aucune course n'a été créée ; "
          'si vous avez été débité, vous serez remboursé (support Sprint).',
        );
    }
  }

  Future<void> _payer() async {
    final lien = _demande?.lienPaiement;
    if (lien == null) return;
    final ouverte = await widget.ouvrirLien(lien);
    if (!mounted) return;
    if (!ouverte) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Impossible d'ouvrir la page de paiement $_operateur. Réessayez.")),
      );
      return;
    }
    setState(() => _pageOuverte = true);
  }

  /// Referme le sas (malgré le [PopScope] qui bloque le retour manuel)
  /// en renvoyant [message] à l'écran de commande.
  void _abandonner(String message) {
    _suivi?.cancel();
    if (mounted) Navigator.of(context).pop(message);
  }

  @override
  Widget build(BuildContext context) {
    final demande = _demande;
    return PopScope(
      // Pas de retour arrière accidentel pendant le paiement : seul le
      // bouton "Annuler" referme le sas.
      canPop: false,
      child: SousPageOnyx(child: Scaffold(
        body: SafeArea(
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: switch (_etape) {
                _EtapePaiement.preparation => _VueAttente(
                    key: const ValueKey('preparation'),
                    titre: widget.methode == PaymentMethod.portefeuille
                        ? 'Paiement avec votre solde Sprint…'
                        : 'Préparation de votre paiement $_operateur…',
                  ),
                _EtapePaiement.aPayer => _VueAPayer(
                    key: ValueKey('aPayer-$_pageOuverte'),
                    operateur: _operateur,
                    prixFcfa: demande?.prixFcfa ?? widget.prixFcfa,
                    pageOuverte: _pageOuverte,
                    onPayer: _payer,
                    onAnnuler: () => _abandonner("Paiement annulé. Aucune course n'a été créée."),
                  ),
                _EtapePaiement.confirme => const _VueConfirmee(),
              },
            ),
          ),
        ),
      )),
    );
  }
}

class _VueAttente extends StatelessWidget {
  const _VueAttente({super.key, required this.titre, this.sousTitre});

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
          Text(
            titre,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
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

class _VueAPayer extends StatelessWidget {
  const _VueAPayer({
    super.key,
    required this.operateur,
    required this.prixFcfa,
    required this.pageOuverte,
    required this.onPayer,
    required this.onAnnuler,
  });

  final String operateur;
  final int prixFcfa;
  final bool pageOuverte;
  final VoidCallback onPayer;
  final VoidCallback onAnnuler;

  @override
  Widget build(BuildContext context) {
    final boutonPayer = FilledButton.icon(
      onPressed: onPayer,
      icon: const Icon(Icons.open_in_new_rounded),
      label: Text(
        pageOuverte ? 'Rouvrir la page de paiement' : 'Payer avec $operateur · ${formaterFcfa(prixFcfa)}',
      ),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.orange,
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
      ),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pageOuverte)
              _VueAttente(
                titre: 'En attente de la confirmation de\nvotre paiement $operateur…',
                sousTitre: 'Payez sur la page $operateur qui vient de s\'ouvrir, puis revenez ici : '
                    'votre course partira aux chauffeurs dès la confirmation.',
              )
            else ...[
              const Icon(Icons.account_balance_wallet_outlined, size: 52, color: AppColors.bleu),
              const SizedBox(height: 18),
              Text(
                formaterFcfa(prixFcfa),
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Payez votre course avec $operateur. Elle sera envoyée aux chauffeurs '
                'dès que $operateur aura confirmé le paiement.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13.5, color: AppColors.texteDiscret, height: 1.4),
              ),
              const SizedBox(height: 28),
            ],
            boutonPayer,
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

class _VueConfirmee extends StatelessWidget {
  const _VueConfirmee();

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('confirmee'),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(
              color: AppColors.bleu,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 44),
          ),
          const SizedBox(height: 24),
          const Text(
            'Paiement confirmé !',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
