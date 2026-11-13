import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/demo/demo_data.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/notifications/carte_notifications.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_fcfa.dart';
import '../../../core/widgets/onyx_vert.dart';
import '../../../core/widgets/payment_method_selector.dart';
import '../../../core/widgets/premium_dialog.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/section_list_tile.dart';
import '../../../core/widgets/stat_tile.dart';
import '../../../core/widgets/wallet_card.dart';
import '../../../firebase_options.dart';
import '../../auth/data/auth_repository.dart';
import '../../portefeuille/data/portefeuille_service.dart';
import '../../portefeuille/data/retraits.dart';
import '../../portefeuille/presentation/mouvements_portefeuille_page.dart';
import '../../portefeuille/presentation/recharge_portefeuille_page.dart';
import 'aide_support_page.dart';
import 'conditions_utilisation_page.dart';
import 'courses_a_noter_page.dart';
import 'favoris_page.dart';
import 'informations_personnelles_page.dart';
import 'inviter_amis_page.dart';
import 'parametres_page.dart';
import 'politique_confidentialite_page.dart';
import 'securite_page.dart';

const _montantsRecharge = [1000, 2000, 5000, 10000, 20000];

/// Onglet Compte : profil, portefeuille, statistiques et menu de
/// paramètres.
class CompteTabPage extends StatefulWidget {
  const CompteTabPage({
    super.key,
    this.service,
    this.clientId,
    this.profil,
    this.demo,
    this.compteDeTest,
    this.retraits,
    this.retraitsDisponibles = retraitsOuverts,
  });

  /// Injectables pour les tests : accès au portefeuille, client connecté,
  /// flux du profil, et [demo] pour forcer le mode démo.
  final PortefeuilleService? service;
  final String? clientId;
  final Stream<Map<String, dynamic>?>? profil;
  final bool? demo;

  /// Force l'état « compte de test » (le faux Wave et, pendant l'essai, Orange
  /// Money sont proposés pour recharger) au lieu de le lire dans le profil.
  final bool? compteDeTest;

  /// Retraits du solde (lot B) : accès injectable, et ouverture (par défaut
  /// le réglage en service [retraitsOuverts] ; fermé, rien n'apparaît).
  final RetraitService? retraits;
  final bool retraitsDisponibles;

  @override
  State<CompteTabPage> createState() => _CompteTabPageState();
}

class _CompteTabPageState extends State<CompteTabPage> {
  final _authRepository = AuthRepository();
  late final PortefeuilleService _portefeuille = widget.service ?? PortefeuilleService();
  late final RetraitService _retraits = widget.retraits ?? RetraitService();

  /// Préférence locale, mode démo seulement : avec Firebase, l'interrupteur
  /// est enregistré dans `portefeuilles/{uid}` (voir [_definirPreference]).
  bool _payerAvecSolde = false;

  /// Solde en direct (Firebase réel, client connecté) ; `null` en mode démo.
  Stream<Portefeuille>? _fluxPortefeuille;

  /// Retraits ouverts et client connecté : retrait en attente de versement
  /// (au plus un), suivi en direct.
  StreamSubscription<Retrait?>? _suiviRetrait;
  Retrait? _retraitEnCours;

  /// Dernier profil lu (en-tête) : numéro du compte proposé pour un retrait.
  Map<String, dynamic>? _profilConnu;

  String? get _uid {
    if (widget.demo == true) return null;
    if (widget.clientId case final id?) return id;
    return DefaultFirebaseOptions.estConfigure ? FirebaseAuth.instance.currentUser?.uid : null;
  }

  @override
  void initState() {
    super.initState();
    final uid = _uid;
    if (uid != null) _fluxPortefeuille = _portefeuille.streamPortefeuille(uid);
    if (uid != null && widget.retraitsDisponibles) {
      try {
        _suiviRetrait = _retraits.streamRetraitEnCours(uid).listen(
              (retrait) {
                if (mounted) setState(() => _retraitEnCours = retrait);
              },
              // Lecture impossible : pas de bandeau ; le serveur refuse de
              // toute façon une seconde demande.
              onError: (Object _) {},
            );
      } on Object {
        // Suivi impossible à ouvrir : pas de bouton « Retirer », l'onglet
        // reste utilisable.
        _suiviRetrait = null;
      }
    }
  }

  @override
  void dispose() {
    _suiviRetrait?.cancel();
    super.dispose();
  }

  void _ouvrir(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  /// Recharge du portefeuille. Firebase réel : le serveur crée la demande,
  /// le client paie chez l'opérateur et le solde n'est crédité qu'à la
  /// confirmation de celui-ci (jamais sur la foi de l'app). Mode démo :
  /// crédit fictif immédiat.
  Future<void> _recharger(Portefeuille portefeuille) async {
    final testeurOrangeMoney =
        widget.compteDeTest ?? (_uid != null && await _authRepository.chargerTesteurOrangeMoney());
    if (!mounted) return;
    final choix = await showModalBottomSheet<_ChoixRecharge>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _RechargeSheet(
        rechargePossibleFcfa: portefeuille.rechargePossibleFcfa,
        // Sans Firebase (mode démo), pas de compte de test : Wave y reste proposé, comme avant.
        moyens: moyensMobileMoneyPour(testeur: testeurOrangeMoney, demo: _uid == null),
        retraitPossible: _suiviRetrait != null,
      ),
    );
    if (choix == null || !mounted) return;

    if (_uid == null) {
      setState(() => DemoData.rechargerPortefeuille(choix.montantFcfa));
      PremiumDialog.afficher(
        context,
        icon: Icons.account_balance_wallet_outlined,
        titre: 'Portefeuille rechargé',
        message: 'Votre solde a été crédité de ${choix.montantFcfa} FCFA.',
        succes: true,
      );
      return;
    }

    final resultat = await Navigator.of(context).push<Object>(
      MaterialPageRoute(
        builder: (_) => RechargePortefeuillePage(
          montantFcfa: choix.montantFcfa,
          methode: choix.methode,
          service: _portefeuille,
        ),
      ),
    );
    if (!mounted) return;
    if (resultat == true) {
      PremiumDialog.afficher(
        context,
        icon: Icons.account_balance_wallet_outlined,
        titre: 'Portefeuille rechargé',
        message: 'Votre solde a été crédité de ${formaterFcfa(choix.montantFcfa)}.',
        succes: true,
      );
    } else if (resultat is String) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(resultat)));
    }
  }

  Future<void> _definirPreference(bool valeur) async {
    final uid = _uid;
    if (uid == null) {
      setState(() => _payerAvecSolde = valeur);
      return;
    }
    try {
      await _portefeuille.definirPayerAvecSolde(uid, valeur);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Impossible d'enregistrer ce réglage. Vérifiez votre connexion.")),
      );
    }
  }

  /// Retrait du solde vers Orange Money ou Wave : la feuille demande d'abord
  /// au serveur ce qui peut être retiré (argent réellement payé, plafond du
  /// jour) ; le serveur réserve ensuite le montant (débité du solde), un Admin
  /// Sprint l'envoie sous 48 h, frais de l'opérateur déduits, ou le refuse et
  /// le montant revient sur le solde.
  Future<void> _retirer() async {
    if (_retraitEnCours case final enCours?) {
      await PremiumDialog.afficher(
        context,
        icon: Icons.hourglass_top_rounded,
        titre: 'Retrait déjà en cours',
        message: '${_resumeRetrait(enCours)} Vous pourrez faire une nouvelle demande une fois celle-ci traitée.',
      );
      return;
    }
    final demande = await showModalBottomSheet<_RetraitDemande>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _RetraitSheet(
        charger: _retraits.infos,
        numeroPropose: numeroSenegal(_profilConnu?['telephone'] as String? ?? '') ?? '',
        envoyer: (montantFcfa, moyen, numero) =>
            _retraits.demander(montantFcfa: montantFcfa, moyen: moyen, numero: numero),
      ),
    );
    if (demande == null || !mounted) return;
    await PremiumDialog.afficher(
      context,
      icon: Icons.check_circle_outline_rounded,
      titre: 'Demande de retrait envoyée',
      message: '${formaterFcfa(demande.montantFcfa)} ont été retirés de votre solde. Sprint vous les envoie sous '
          '$delaiVersementHeures h sur votre compte ${demande.moyen.label} (${formaterNumero(demande.numero)}), '
          'frais de transfert de l\'opérateur déduits. Vous serez prévenu dès l\'envoi.',
      succes: true,
    );
  }

  static String _resumeRetrait(Retrait retrait) =>
      '${formaterFcfa(retrait.montantFcfa)} vers ${retrait.moyen?.label ?? 'votre mobile money'} '
      '(${retrait.numeroLisible}), envoyés sous $delaiVersementHeures h, frais de transfert déduits.';

  Widget _carteWallet(Portefeuille portefeuille) => WalletCard(
        soldeFcfa: portefeuille.soldeFcfa,
        payerAvecSolde: portefeuille.payerAvecSolde,
        onTogglePaiement: _definirPreference,
        onRecharger: () => _recharger(portefeuille),
        onRetirer: _suiviRetrait == null ? null : _retirer,
      );

  Future<void> _seDeconnecter() async {
    await _authRepository.deconnecter();
    if (mounted) context.go(AppRoutes.welcome);
  }

  @override
  Widget build(BuildContext context) {
    // Charte Onyx & Vert : fond Onyx à halos verts, cartes « verre », texte clair.
    return ThemeOnyxVert(
      child: Scaffold(
        backgroundColor: AppColors.fond,
        body: FondOnyxVert(
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
              children: [
                _entete(),
                const SizedBox(height: 22),
                const CarteNotifications(),
                const SizedBox(height: 22),
                if (_fluxPortefeuille case final flux?)
                  StreamBuilder<Portefeuille>(
                    stream: flux,
                    builder: (context, instantane) => _carteWallet(instantane.data ?? const Portefeuille()),
                  )
                else
                  _carteWallet(
                    Portefeuille(soldeFcfa: DemoData.soldePortefeuilleFcfa, payerAvecSolde: _payerAvecSolde),
                  ),
                if (_retraitEnCours case final retrait?) ...[
                  const SizedBox(height: 12),
                  _BandeauRetrait(texte: 'Retrait en cours : ${_resumeRetrait(retrait)}'),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(
                      child: StatTile(label: 'Note', valeur: '${DemoData.noteMoyenneClient}', icon: Icons.star_outline_rounded),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: StatTile(label: 'Courses', valeur: '${DemoData.coursesEffectueesClient}', icon: Icons.route_outlined),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: StatTile(
                        label: 'Réservations',
                        valeur: '${DemoData.reservationsClient}',
                        icon: Icons.event_available_outlined,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: StatTile(label: 'Favoris', valeur: '${DemoData.favorisClient}', icon: Icons.favorite_border_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                const _TitreSection('Compte'),
                _GroupeMenu(
                  children: [
                    if (_fluxPortefeuille != null)
                      SectionListTile(
                        icon: Icons.receipt_long_outlined,
                        label: 'Mouvements du portefeuille',
                        onTap: () => _ouvrir(MouvementsPortefeuillePage(service: _portefeuille)),
                      ),
                    SectionListTile(
                      icon: Icons.badge_outlined,
                      label: 'Informations personnelles',
                      onTap: () => _ouvrir(const InformationsPersonnellesPage()),
                    ),
                    SectionListTile(
                      icon: Icons.shield_outlined,
                      label: 'Sécurité',
                      onTap: () => _ouvrir(const SecuritePage()),
                    ),
                    SectionListTile(
                      icon: Icons.favorite_border_rounded,
                      label: 'Favoris',
                      onTap: () => _ouvrir(const FavorisPage()),
                    ),
                    SectionListTile(
                      icon: Icons.star_border_rounded,
                      label: 'Courses à noter',
                      onTap: () => _ouvrir(const CoursesANoterPage()),
                    ),
                    SectionListTile(
                      icon: Icons.person_add_alt_outlined,
                      label: 'Inviter des amis',
                      onTap: () => _ouvrir(const InviterAmisPage()),
                    ),
                    SectionListTile(
                      icon: Icons.help_outline_rounded,
                      label: 'Aide & Support',
                      onTap: () => _ouvrir(const AideSupportPage()),
                    ),
                    SectionListTile(
                      icon: Icons.settings_outlined,
                      label: 'Paramètres',
                      onTap: () => _ouvrir(const ParametresPage()),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const _TitreSection('Informations légales'),
                _GroupeMenu(
                  children: [
                    SectionListTile(
                      icon: Icons.description_outlined,
                      label: 'Conditions d\'utilisation',
                      onTap: () => _ouvrir(const ConditionsUtilisationPage()),
                    ),
                    SectionListTile(
                      icon: Icons.privacy_tip_outlined,
                      label: 'Politique de confidentialité',
                      onTap: () => _ouvrir(const PolitiqueConfidentialitePage()),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _GroupeMenu(
                  children: [
                    SectionListTile(
                      icon: Icons.logout_rounded,
                      label: 'Se déconnecter',
                      onTap: _seDeconnecter,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _entete() {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: widget.profil ?? _authRepository.profilUtilisateurStream(),
      builder: (context, snapshot) {
        if (snapshot.data case final profil?) _profilConnu = profil;
        final nomFirestore = (snapshot.data?['nom'] as String?)?.trim();
        final nomAffiche = (nomFirestore != null && nomFirestore.isNotEmpty) ? nomFirestore : DemoData.monNomClient;
        final initiale = nomAffiche.isNotEmpty ? nomAffiche[0].toUpperCase() : '?';
        return Row(
          children: [
            // Avatar Onyx cerclé de vert : le vert marque ce qui est actif.
            Container(
              width: 62,
              height: 62,
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.vert),
              child: Container(
                decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.onyx),
                alignment: Alignment.center,
                child: Text(
                  initiale,
                  style: const TextStyle(color: AppColors.texte, fontSize: 24, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nomAffiche,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppColors.texte),
                  ),
                  const SizedBox(height: 2),
                  const Text('Client Sprint', style: TextStyle(fontSize: 13, color: AppColors.texteDiscret)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TitreSection extends StatelessWidget {
  const _TitreSection(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 0, 10),
      child: Text(
        texte,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: AppColors.texte),
      ),
    );
  }
}

/// Lignes de menu réunies dans une carte « verre », séparées par un filet.
class _GroupeMenu extends StatelessWidget {
  const _GroupeMenu({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return CarteVerre(
      rayon: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 56, color: AppColors.bordVerre),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Montant et opérateur choisis pour une recharge.
class _ChoixRecharge {
  const _ChoixRecharge(this.montantFcfa, this.methode);

  final int montantFcfa;
  final PaymentMethod methode;
}

class _RechargeSheet extends StatefulWidget {
  const _RechargeSheet({required this.rechargePossibleFcfa, required this.moyens, required this.retraitPossible});

  /// Ce qui peut encore être ajouté avant le plafond du solde.
  final int rechargePossibleFcfa;

  /// Opérateurs de mobile money proposés à ce client ([moyensMobileMoneyPour]).
  /// Vide pour un client ordinaire, pour l'instant : le faux Wave est réservé
  /// aux comptes de test et Orange Money n'est pas encore ouvert à tous.
  final List<PaymentMethod> moyens;

  /// Retraits ouverts pour ce compte (bouton « Retirer » affiché).
  final bool retraitPossible;

  @override
  State<_RechargeSheet> createState() => _RechargeSheetState();
}

class _RechargeSheetState extends State<_RechargeSheet> {
  int? _montantChoisi = _montantsRecharge[1];
  late PaymentMethod _methode = widget.moyens.isEmpty ? PaymentMethod.wave : widget.moyens.first;
  final _autreMontant = TextEditingController();

  @override
  void dispose() {
    _autreMontant.dispose();
    super.dispose();
  }

  /// Message d'erreur du montant saisi ; `null` s'il est valide.
  String? get _erreur {
    final montant = _montantChoisi;
    if (montant == null) return 'Saisissez un montant.';
    if (montant < LimitesPortefeuille.rechargeMinFcfa) {
      return 'Recharge minimale : ${formaterFcfa(LimitesPortefeuille.rechargeMinFcfa)}.';
    }
    if (montant > LimitesPortefeuille.rechargeMaxFcfa) {
      return 'Recharge maximale : ${formaterFcfa(LimitesPortefeuille.rechargeMaxFcfa)}.';
    }
    if (montant > widget.rechargePossibleFcfa) {
      return widget.rechargePossibleFcfa == 0
          ? 'Votre solde a atteint le plafond de ${formaterFcfa(LimitesPortefeuille.soldeMaxFcfa)}.'
          : 'Le solde est plafonné à ${formaterFcfa(LimitesPortefeuille.soldeMaxFcfa)} : '
              'vous pouvez encore ajouter ${formaterFcfa(widget.rechargePossibleFcfa)}.';
    }
    return null;
  }

  void _saisie(String texte) {
    setState(() => _montantChoisi = int.tryParse(texte.replaceAll(RegExp(r'\s'), '')));
  }

  @override
  Widget build(BuildContext context) {
    final erreur = _erreur;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        decoration: const BoxDecoration(
          color: AppColors.carte,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          border: Border(top: BorderSide(color: AppColors.bordVerre)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: AppColors.bord, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Recharger mon portefeuille',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppColors.texte),
              ),
              const SizedBox(height: 6),
              Text(
                widget.retraitPossible
                    ? 'Le solde sert à payer vos courses. Il peut aussi être retiré (bouton « Retirer »), '
                        'hors argent de test.'
                    : 'Le solde sert uniquement à payer vos courses. Il n\'est pas retirable.',
                style: const TextStyle(fontSize: 12.5, color: AppColors.texteDiscret),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _montantsRecharge.map((montant) {
                  final selectionne = montant == _montantChoisi && _autreMontant.text.isEmpty;
                  return ChoiceChip(
                    label: Text('$montant FCFA'),
                    selected: selectionne,
                    onSelected: (_) => setState(() {
                      _autreMontant.clear();
                      _montantChoisi = montant;
                    }),
                    selectedColor: AppColors.vert,
                    showCheckmark: false,
                    side: BorderSide(color: selectionne ? AppColors.vert : AppColors.bord),
                    labelStyle: TextStyle(
                      color: selectionne ? AppColors.onyx : AppColors.texte,
                      fontWeight: FontWeight.w700,
                    ),
                    backgroundColor: AppColors.carteHaute,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('autre-montant'),
                controller: _autreMontant,
                keyboardType: TextInputType.number,
                onChanged: _saisie,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Autre montant (FCFA)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.bord),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.vert, width: 1.6),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              if (widget.moyens.isEmpty)
                Container(
                  key: const ValueKey('recharge-pas-encore-ouverte'),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.carteHaute, borderRadius: BorderRadius.circular(14)),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 18, color: AppColors.texteDiscret),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "La recharge en ligne n'est pas encore ouverte à votre compte. "
                          'Vous pourrez recharger votre solde dès son ouverture.',
                          style: TextStyle(fontSize: 13, color: AppColors.texte, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                const Text('Payer avec', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.texte)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  children: widget.moyens.map((methode) {
                    final selectionne = methode == _methode;
                    return ChoiceChip(
                      key: ValueKey('operateur-${methode.apiValue}'),
                      label: Text(methode.label),
                      selected: selectionne,
                      onSelected: (_) => setState(() => _methode = methode),
                      selectedColor: AppColors.vert,
                      showCheckmark: false,
                      side: BorderSide(color: selectionne ? AppColors.vert : AppColors.bord),
                      labelStyle: TextStyle(
                        color: selectionne ? AppColors.onyx : AppColors.texte,
                        fontWeight: FontWeight.w700,
                      ),
                      backgroundColor: AppColors.carteHaute,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                // Dit quels moyens débitent vraiment : le faux Wave n'est que de l'argent de test.
                Text(
                  mentionPaiement(widget.moyens),
                  key: const ValueKey('mention-recharge'),
                  style: const TextStyle(fontSize: 12, color: AppColors.texteDiscret),
                ),
              ],
              if (erreur != null) ...[
                const SizedBox(height: 12),
                Text(erreur, key: const ValueKey('erreur-recharge'), style: const TextStyle(fontSize: 12.5, color: AppColors.danger)),
              ],
              const SizedBox(height: 22),
              PrimaryButton(
                label: 'Confirmer la recharge',
                onPressed: erreur != null || widget.moyens.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(_ChoixRecharge(_montantChoisi!, _methode)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Retrait accepté par le serveur (montant déjà retiré du solde).
class _RetraitDemande {
  const _RetraitDemande(this.montantFcfa, this.moyen, this.numero);

  final int montantFcfa;
  final MoyenRetrait moyen;

  /// Numéro tel que retenu (9 chiffres).
  final String numero;
}

/// Retrait du solde. La feuille demande d'abord au serveur ce qui peut être
/// retiré maintenant ([InfosRetrait] : argent réellement payé, plafond du
/// jour), puis propose ce maximum, Orange Money ou Wave, et le numéro du
/// compte. La demande part d'ici : une erreur du serveur s'affiche dans la
/// feuille, pour corriger sans tout ressaisir.
class _RetraitSheet extends StatefulWidget {
  const _RetraitSheet({required this.charger, required this.numeroPropose, required this.envoyer});

  /// Ce qui peut être retiré ; erreurs : [ApiException].
  final Future<InfosRetrait> Function() charger;

  /// Numéro du compte s'il est valide, vide sinon.
  final String numeroPropose;

  /// Envoie la demande au serveur ; erreurs : [ApiException].
  final Future<int> Function(int montantFcfa, MoyenRetrait moyen, String numero) envoyer;

  @override
  State<_RetraitSheet> createState() => _RetraitSheetState();
}

class _RetraitSheetState extends State<_RetraitSheet> {
  InfosRetrait? _infos;
  String? _erreurChargement;
  final _montant = TextEditingController();
  late final _numero = TextEditingController(text: formaterNumero(widget.numeroPropose));
  MoyenRetrait _moyen = MoyenRetrait.orangeMoney;
  bool _envoi = false;
  String? _erreurServeur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _montant.dispose();
    _numero.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    if (_infos != null || _erreurChargement != null) {
      setState(() {
        _infos = null;
        _erreurChargement = null;
      });
    }
    try {
      final infos = await widget.charger();
      if (!mounted) return;
      setState(() {
        _infos = infos;
        _montant.text = '${infos.maximumFcfa}';
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _erreurChargement = e.message);
    } on Object {
      if (mounted) setState(() => _erreurChargement = 'Vérification impossible. Vérifiez votre connexion et réessayez.');
    }
  }

  int? get _montantSaisi => int.tryParse(_montant.text.replaceAll(RegExp(r'[\s  ]'), ''));

  String? _erreurMontant(InfosRetrait infos) {
    final montant = _montantSaisi;
    if (montant == null) return 'Saisissez un montant.';
    if (montant < retraitMinFcfa) return 'Retrait minimal : ${formaterFcfa(retraitMinFcfa)}.';
    if (montant > infos.maximumFcfa) return 'Vous pouvez retirer au plus ${formaterFcfa(infos.maximumFcfa)} maintenant.';
    return null;
  }

  String? get _erreurNumero => numeroSenegal(_numero.text) == null
      ? 'Numéro invalide : 9 chiffres, commençant par 70, 75, 76, 77 ou 78.'
      : null;

  /// Pourquoi rien ne peut être retiré maintenant (maximum sous le minimum).
  static (String, String) _indisponible(InfosRetrait infos) {
    if (infos.enCours) {
      return (
        'Retrait déjà en cours',
        'Vous pourrez faire une nouvelle demande une fois la précédente traitée.',
      );
    }
    if (infos.soldeFcfa < retraitMinFcfa) {
      return (
        'Solde insuffisant',
        'Le retrait minimal est de ${formaterFcfa(retraitMinFcfa)}. Votre solde : ${formaterFcfa(infos.soldeFcfa)}.',
      );
    }
    if (infos.resteDuJourFcfa < retraitMinFcfa) {
      return (
        'Plafond du jour atteint',
        'Les retraits sont limités à ${formaterFcfa(retraitMaxJourFcfa)} par jour. Réessayez demain.',
      );
    }
    return (
      'Rien à retirer pour l\'instant',
      'Seul l\'argent réellement payé (Orange Money) peut être retiré. Votre solde vient de recharges en mode '
          'test : il sert à payer vos courses.',
    );
  }

  Future<void> _confirmer() async {
    final montant = _montantSaisi;
    final numero = numeroSenegal(_numero.text);
    if (montant == null || numero == null) return;
    setState(() {
      _envoi = true;
      _erreurServeur = null;
    });
    try {
      await widget.envoyer(montant, _moyen, numero);
      if (mounted) Navigator.of(context).pop(_RetraitDemande(montant, _moyen, numero));
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _envoi = false;
          _erreurServeur = e.message;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _envoi = false;
          _erreurServeur = 'Demande impossible. Vérifiez votre connexion et réessayez.';
        });
      }
    }
  }

  InputDecoration _decoration(String libelle, {String? aide}) => InputDecoration(
        isDense: true,
        labelText: libelle,
        helperText: aide,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.bord),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.vert, width: 1.6),
        ),
      );

  Widget _erreur(String texte, String cle) => Padding(
        padding: const EdgeInsets.only(top: 6, left: 4),
        child: Text(texte, key: ValueKey(cle), style: const TextStyle(fontSize: 12.5, color: AppColors.danger)),
      );

  static const _discret = TextStyle(fontSize: 12.5, color: AppColors.texteDiscret, height: 1.4);

  List<Widget> _contenu(BuildContext context) {
    final infos = _infos;
    if (_erreurChargement case final erreur?) {
      return [
        Text(erreur, key: const ValueKey('erreur-chargement-retrait'), style: const TextStyle(color: AppColors.danger)),
        const SizedBox(height: 22),
        PrimaryButton(label: 'Réessayer', onPressed: _charger),
      ];
    }
    if (infos == null) {
      return const [
        SizedBox(height: 12),
        Center(child: CircularProgressIndicator(color: AppColors.vert)),
        SizedBox(height: 14),
        Text('Vérification de ce que vous pouvez retirer…', textAlign: TextAlign.center, style: _discret),
        SizedBox(height: 12),
      ];
    }
    if (infos.maximumFcfa < retraitMinFcfa) {
      final (titre, texte) = _indisponible(infos);
      return [
        Text(titre, key: const ValueKey('retrait-indisponible'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.texte)),
        const SizedBox(height: 6),
        Text(texte, style: _discret),
        const SizedBox(height: 22),
        PrimaryButton(label: 'Compris', onPressed: () => Navigator.of(context).pop()),
      ];
    }
    final erreurMontant = _erreurMontant(infos);
    final erreurNumero = _erreurNumero;
    final montant = _montantSaisi;
    final pret = erreurMontant == null && erreurNumero == null;
    return [
      Text(
        'Vous pouvez retirer jusqu\'à ${formaterFcfa(infos.maximumFcfa)} maintenant'
        '${infos.retirableFcfa < infos.soldeFcfa ? ' (le reste de votre solde est de l\'argent de test, qui sert à payer vos courses)' : ''}'
        '${infos.resteDuJourFcfa < retraitMaxJourFcfa ? ' ; plafond du jour : encore ${formaterFcfa(infos.resteDuJourFcfa)}' : ''}.',
        key: const ValueKey('retirable'),
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.texte, height: 1.4),
      ),
      const SizedBox(height: 6),
      Text(
        'Le montant est retiré de votre solde dès la demande. Sprint vous l\'envoie sous $delaiVersementHeures h, '
        'frais de transfert de l\'opérateur déduits. En cas de refus, il revient sur votre solde. Plafond : '
        '${formaterFcfa(retraitMaxJourFcfa)} par jour.',
        style: _discret,
      ),
      const SizedBox(height: 18),
      TextField(
        key: const ValueKey('montant-retrait'),
        controller: _montant,
        enabled: !_envoi,
        keyboardType: TextInputType.number,
        onChanged: (_) => setState(() => _erreurServeur = null),
        decoration: _decoration('Montant à retirer (FCFA)'),
      ),
      if (erreurMontant != null) _erreur(erreurMontant, 'erreur-montant-retrait'),
      const SizedBox(height: 18),
      const Text('Recevoir sur', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.texte)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 10,
        children: MoyenRetrait.values.map((moyen) {
          final selectionne = moyen == _moyen;
          return ChoiceChip(
            key: ValueKey('moyen-retrait-${moyen.apiValue}'),
            label: Text(moyen.label),
            selected: selectionne,
            onSelected: _envoi ? null : (_) => setState(() => _moyen = moyen),
            selectedColor: AppColors.vert,
            showCheckmark: false,
            side: BorderSide(color: selectionne ? AppColors.vert : AppColors.bord),
            labelStyle: TextStyle(
              color: selectionne ? AppColors.onyx : AppColors.texte,
              fontWeight: FontWeight.w700,
            ),
            backgroundColor: AppColors.carteHaute,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          );
        }).toList(),
      ),
      const SizedBox(height: 14),
      TextField(
        key: const ValueKey('numero-retrait'),
        controller: _numero,
        enabled: !_envoi,
        keyboardType: TextInputType.phone,
        onChanged: (_) => setState(() => _erreurServeur = null),
        decoration: _decoration('Numéro ${_moyen.label}', aide: 'Le numéro qui recevra l\'argent.'),
      ),
      if (erreurNumero != null && _numero.text.trim().isNotEmpty) _erreur(erreurNumero, 'erreur-numero-retrait'),
      if (pret && montant != null) ...[
        const SizedBox(height: 14),
        Text(
          'Vous recevrez ${formaterFcfa(montant)} sur le ${formaterNumero(numeroSenegal(_numero.text)!)} '
          '(${_moyen.label}), moins les frais de transfert.',
          key: const ValueKey('resume-retrait'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.texte, height: 1.4),
        ),
      ],
      if (_erreurServeur case final erreur?) _erreur(erreur, 'erreur-serveur-retrait'),
      const SizedBox(height: 22),
      PrimaryButton(
        label: 'Confirmer le retrait',
        isLoading: _envoi,
        onPressed: pret && !_envoi ? _confirmer : null,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        decoration: const BoxDecoration(
          color: AppColors.carte,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          border: Border(top: BorderSide(color: AppColors.bordVerre)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: AppColors.bord, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Retirer mon solde',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppColors.texte),
              ),
              const SizedBox(height: 10),
              ..._contenu(context),
            ],
          ),
        ),
      ),
    );
  }
}

/// Retrait en attente de versement, sous la carte du portefeuille.
class _BandeauRetrait extends StatelessWidget {
  const _BandeauRetrait({required this.texte});

  final String texte;

  @override
  Widget build(BuildContext context) {
    return CarteVerre(
      key: const ValueKey('bandeau-retrait'),
      rayon: 20,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.hourglass_top_rounded, size: 20, color: AppColors.vert),
          const SizedBox(width: 12),
          Expanded(
            child: Text(texte, style: const TextStyle(fontSize: 13, color: AppColors.texte, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
