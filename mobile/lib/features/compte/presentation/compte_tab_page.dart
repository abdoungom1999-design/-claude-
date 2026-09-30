import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/demo/demo_data.dart';
import '../../../core/notifications/carte_notifications.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_fcfa.dart';
import '../../../core/widgets/onyx_light.dart';
import '../../../core/widgets/payment_method_selector.dart';
import '../../../core/widgets/premium_dialog.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/section_list_tile.dart';
import '../../../core/widgets/stat_tile.dart';
import '../../../core/widgets/wallet_card.dart';
import '../../../firebase_options.dart';
import '../../auth/data/auth_repository.dart';
import '../../portefeuille/data/portefeuille_service.dart';
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
  const CompteTabPage({super.key, this.service, this.clientId, this.profil, this.demo});

  /// Injectables pour les tests : accès au portefeuille, client connecté,
  /// flux du profil, et [demo] pour forcer le mode démo.
  final PortefeuilleService? service;
  final String? clientId;
  final Stream<Map<String, dynamic>?>? profil;
  final bool? demo;

  @override
  State<CompteTabPage> createState() => _CompteTabPageState();
}

class _CompteTabPageState extends State<CompteTabPage> {
  final _authRepository = AuthRepository();
  late final PortefeuilleService _portefeuille = widget.service ?? PortefeuilleService();

  /// Préférence locale, mode démo seulement : avec Firebase, l'interrupteur
  /// est enregistré dans `portefeuilles/{uid}` (voir [_definirPreference]).
  bool _payerAvecSolde = false;

  /// Solde en direct (Firebase réel, client connecté) ; `null` en mode démo.
  Stream<Portefeuille>? _fluxPortefeuille;

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
  }

  void _ouvrir(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  /// Recharge du portefeuille. Firebase réel : le serveur crée la demande,
  /// le client paie chez l'opérateur et le solde n'est crédité qu'à la
  /// confirmation de celui-ci (jamais sur la foi de l'app). Mode démo :
  /// crédit fictif immédiat.
  Future<void> _recharger(Portefeuille portefeuille) async {
    final choix = await showModalBottomSheet<_ChoixRecharge>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _RechargeSheet(rechargePossibleFcfa: portefeuille.rechargePossibleFcfa),
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

  Widget _carteWallet(Portefeuille portefeuille) => WalletCard(
        soldeFcfa: portefeuille.soldeFcfa,
        payerAvecSolde: portefeuille.payerAvecSolde,
        onTogglePaiement: _definirPreference,
        onRecharger: () => _recharger(portefeuille),
      );

  Future<void> _seDeconnecter() async {
    await _authRepository.deconnecter();
    if (mounted) context.go(AppRoutes.welcome);
  }

  @override
  Widget build(BuildContext context) {
    // Charte Onyx & Light : fond clair à halos, cartes « verre », texte Onyx.
    return ThemeOnyxLight(
      child: Scaffold(
        backgroundColor: AppColors.fondClair,
        body: FondOnyxLight(
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
        final nomFirestore = (snapshot.data?['nom'] as String?)?.trim();
        final nomAffiche = (nomFirestore != null && nomFirestore.isNotEmpty) ? nomFirestore : DemoData.monNomClient;
        final initiale = nomAffiche.isNotEmpty ? nomAffiche[0].toUpperCase() : '?';
        return Row(
          children: [
            // Avatar Onyx cerclé d'orange : l'orange reste un accent.
            Container(
              width: 62,
              height: 62,
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.orange),
              child: Container(
                decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.onyx),
                alignment: Alignment.center,
                child: Text(
                  initiale,
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700),
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
                    style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppColors.onyx),
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
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: AppColors.onyx),
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
  const _RechargeSheet({required this.rechargePossibleFcfa});

  /// Ce qui peut encore être ajouté avant le plafond du solde.
  final int rechargePossibleFcfa;

  @override
  State<_RechargeSheet> createState() => _RechargeSheetState();
}

class _RechargeSheetState extends State<_RechargeSheet> {
  int? _montantChoisi = _montantsRecharge[1];
  PaymentMethod _methode = PaymentMethod.wave;
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
          color: AppColors.fondClairHaut,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
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
                  decoration: BoxDecoration(color: AppColors.greyBorder, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Recharger mon portefeuille',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppColors.onyx),
              ),
              const SizedBox(height: 6),
              const Text(
                'Le solde sert uniquement à payer vos courses. Il n\'est pas retirable.',
                style: TextStyle(fontSize: 12.5, color: AppColors.texteDiscret),
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
                    selectedColor: AppColors.orange,
                    showCheckmark: false,
                    side: BorderSide.none,
                    labelStyle: TextStyle(
                      color: selectionne ? Colors.white : AppColors.onyx,
                      fontWeight: FontWeight.w600,
                    ),
                    backgroundColor: AppColors.fondClair,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide.none),
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
                    borderSide: const BorderSide(color: Color(0xFFD1D1D6)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.onyx, width: 1.4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text('Payer avec', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.onyx)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                children: [PaymentMethod.wave, PaymentMethod.orangeMoney].map((methode) {
                  final selectionne = methode == _methode;
                  return ChoiceChip(
                    key: ValueKey('operateur-${methode.apiValue}'),
                    label: Text(methode.label),
                    selected: selectionne,
                    onSelected: (_) => setState(() => _methode = methode),
                    selectedColor: AppColors.onyx,
                    showCheckmark: false,
                    side: BorderSide.none,
                    labelStyle: TextStyle(
                      color: selectionne ? Colors.white : AppColors.onyx,
                      fontWeight: FontWeight.w600,
                    ),
                    backgroundColor: AppColors.fondClair,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide.none),
                  );
                }).toList(),
              ),
              if (erreur != null) ...[
                const SizedBox(height: 12),
                Text(erreur, key: const ValueKey('erreur-recharge'), style: const TextStyle(fontSize: 12.5, color: Colors.red)),
              ],
              const SizedBox(height: 22),
              PrimaryButton(
                label: 'Confirmer la recharge',
                onPressed: erreur != null ? null : () => Navigator.of(context).pop(_ChoixRecharge(_montantChoisi!, _methode)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
