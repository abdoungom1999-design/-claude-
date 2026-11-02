import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/onyx_vert.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/data/auth_repository.dart';
import '../../courses/data/course_service.dart';
import '../../portefeuille/data/portefeuille_service.dart';
import 'suivi_course_page.dart';

/// Ce que suit la page de retour : une commande de course (24 caractères
/// hexadécimaux) ou une recharge du portefeuille (« rch_… ») ; `null` pour
/// une référence d'une autre forme.
enum SortePaiement { course, recharge }

SortePaiement? sortePaiement(String? reference) {
  if (reference == null) return null;
  if (RegExp(r'^[0-9a-f]{24}$').hasMatch(reference)) return SortePaiement.course;
  if (RegExp(r'^rch_[0-9a-f]{24}$').hasMatch(reference)) return SortePaiement.recharge;
  return null;
}

/// Page où Max It ramène le client après un paiement Orange Money
/// (`/paiement/retour?ref=<référence>&etat=ok|annule`, adresse donnée à
/// Orange par le serveur) : l'APK s'y ouvre directement, le site l'affiche
/// sinon.
///
/// Elle ne décide jamais qu'un paiement a réussi : elle suit, en temps réel,
/// la commande ou la recharge que seul le serveur confirme (après relecture
/// chez Orange), puis ouvre le suivi de la course. Sans session sur cet
/// appareil (iPhone : Safari ne partage pas la session de l'app installée),
/// elle invite à revenir dans Sprint, où le paiement s'affiche de toute façon.
class RetourPaiementPage extends StatefulWidget {
  const RetourPaiementPage({
    super.key,
    required this.reference,
    required this.etat,
    this.sessionConnectee,
    this.suivreCommande,
    this.suivreRecharge,
    this.ouvrirSuivi,
    this.delaiMax = const Duration(minutes: 3),
  });

  final String? reference;

  /// `ok` (paiement validé dans Max It) ou `annule`.
  final String? etat;

  /// Compte connecté sur cet appareil (après relecture de la session), `null`
  /// sinon. Injectable pour les tests.
  final Future<String?> Function()? sessionConnectee;
  final Stream<CommandePaiement?> Function(String commandeId)? suivreCommande;
  final Stream<AvancementRecharge?> Function(String rechargeId)? suivreRecharge;

  /// Ouvre le suivi de la course créée (par défaut [SuiviCoursePage]).
  final void Function(BuildContext context, String courseId)? ouvrirSuivi;

  /// Au-delà, on cesse d'attendre la confirmation à l'écran.
  final Duration delaiMax;

  @override
  State<RetourPaiementPage> createState() => _RetourPaiementPageState();
}

enum _Etat { verification, confirme, rechargee, refuse, annule, horsSession, tropLong }

class _RetourPaiementPageState extends State<RetourPaiementPage> {
  _Etat _etat = _Etat.verification;
  StreamSubscription<Object?>? _suivi;
  Timer? _delai;
  String? _courseId;

  @override
  void initState() {
    super.initState();
    if (widget.etat == 'annule') {
      _etat = _Etat.annule;
    } else {
      unawaited(_demarrer());
    }
  }

  @override
  void dispose() {
    _suivi?.cancel();
    _delai?.cancel();
    super.dispose();
  }

  Future<void> _demarrer() async {
    final reference = widget.reference;
    final sorte = sortePaiement(reference);
    String? uid;
    try {
      uid = await (widget.sessionConnectee ?? _sessionParDefaut)();
    } on Object {
      uid = null;
    }
    if (!mounted) return;
    if (uid == null || reference == null || sorte == null) {
      setState(() => _etat = _Etat.horsSession);
      return;
    }
    _delai = Timer(widget.delaiMax, () {
      if (mounted && _etat == _Etat.verification) setState(() => _etat = _Etat.tropLong);
    });
    void horsSession(Object _) {
      if (mounted && _etat == _Etat.verification) setState(() => _etat = _Etat.horsSession);
    }

    if (sorte == SortePaiement.course) {
      final suivre = widget.suivreCommande ?? CourseService().streamCommande;
      _suivi = suivre(reference).listen(_suivreCommande, onError: horsSession);
    } else {
      final suivre = widget.suivreRecharge ?? PortefeuilleService().streamRecharge;
      _suivi = suivre(reference).listen(_suivreRecharge, onError: horsSession);
    }
  }

  static Future<String?> _sessionParDefaut() =>
      AuthRepository.firebasePret ? AuthRepository().uidDeLaSessionConservee() : Future.value(null);

  void _suivreCommande(CommandePaiement? commande) {
    if (commande == null || !mounted) return;
    switch (commande.statut) {
      case StatutCommande.enAttente:
        return;
      case StatutCommande.payee:
        final courseId = commande.courseId;
        if (courseId == null) return;
        _terminer(_Etat.confirme);
        _courseId = courseId;
        _ouvrirSuivi();
      default:
        _terminer(_Etat.refuse);
    }
  }

  void _suivreRecharge(AvancementRecharge? recharge) {
    if (recharge == null || !mounted) return;
    switch (recharge.statut) {
      case StatutRecharge.enAttente:
        return;
      case StatutRecharge.reussie:
        _terminer(_Etat.rechargee);
      default:
        _terminer(_Etat.refuse);
    }
  }

  void _terminer(_Etat etat) {
    unawaited(_suivi?.cancel());
    _delai?.cancel();
    setState(() => _etat = etat);
  }

  void _ouvrirSuivi() {
    final courseId = _courseId;
    if (courseId == null) return;
    final ouvrir = widget.ouvrirSuivi;
    if (ouvrir != null) {
      ouvrir(context, courseId);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => SuiviCoursePage(courseId: courseId)));
  }

  @override
  Widget build(BuildContext context) {
    final course = sortePaiement(widget.reference) != SortePaiement.recharge;
    final (IconData icone, Color couleur, String titre, String texte) = switch (_etat) {
      _Etat.verification => (
          Icons.hourglass_top_rounded,
          AppColors.vert,
          'Paiement reçu, confirmation en cours…',
          'Nous vérifions votre paiement auprès d\'Orange Money. Ne payez pas une seconde fois.',
        ),
      _Etat.confirme => (
          Icons.check_circle_rounded,
          AppColors.vert,
          'Paiement confirmé',
          'Votre course est créée : les chauffeurs les plus proches la reçoivent.',
        ),
      _Etat.rechargee => (
          Icons.check_circle_rounded,
          AppColors.vert,
          'Recharge effectuée',
          'Votre solde Sprint a été crédité.',
        ),
      _Etat.refuse => (
          Icons.cancel_rounded,
          AppColors.danger,
          'Paiement non abouti',
          course
              ? "Aucune course n'a été créée. Vous pouvez recommander depuis Sprint."
              : "Votre solde n'a pas été crédité. Vous pouvez réessayer depuis Sprint.",
        ),
      _Etat.annule => (
          Icons.cancel_rounded,
          AppColors.texteDiscret,
          'Paiement annulé',
          "Aucune somme n'a été débitée. Vous pouvez réessayer depuis Sprint.",
        ),
      _Etat.horsSession => (
          Icons.phone_iphone_rounded,
          AppColors.vert,
          'Paiement transmis à Orange Money',
          'Revenez dans l\'application Sprint : votre course ou votre recharge s\'y affiche dès sa confirmation.',
        ),
      _Etat.tropLong => (
          Icons.schedule_rounded,
          AppColors.texteDiscret,
          'Confirmation plus longue que prévu',
          course
              ? 'Votre course apparaîtra dans Activité dès que le paiement sera confirmé. Ne payez pas une seconde fois.'
              : 'Votre solde sera crédité dès que le paiement sera confirmé. Ne payez pas une seconde fois.',
        ),
    };
    final (String action, VoidCallback onAction) = switch (_etat) {
      _Etat.confirme => ('Suivre ma course', _ouvrirSuivi),
      _Etat.rechargee => ('Voir mon portefeuille', () => context.go(AppRoutes.compteTab)),
      _Etat.tropLong when course => ('Voir mes courses', () => context.go(AppRoutes.activiteTab)),
      _Etat.horsSession => ('Ouvrir Sprint', () => context.go(AppRoutes.welcome)),
      _ => ('Retour à l\'accueil', () => context.go(AppRoutes.welcome)),
    };
    return SousPageOnyx(
      child: Scaffold(
        body: SafeArea(
          child: Center(
            // Défilable : texte agrandi ou petit écran, rien n'est jamais coupé.
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                key: ValueKey(_etat),
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_etat == _Etat.verification)
                    const SizedBox(
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.vert),
                    )
                  else
                    Icon(icone, size: 72, color: couleur),
                  const SizedBox(height: 28),
                  Text(
                    titre,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    texte,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14.5, color: AppColors.texteDiscret, height: 1.45),
                  ),
                  if (_etat != _Etat.verification) ...[
                    const SizedBox(height: 32),
                    PrimaryButton(label: action, onPressed: onAction),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
