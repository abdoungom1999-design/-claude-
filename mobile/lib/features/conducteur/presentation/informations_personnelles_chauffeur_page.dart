import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/image_document.dart';
import '../../../core/widgets/onyx_vert.dart';
import '../../../core/widgets/premium_dialog.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/data/auth_repository.dart';
import '../data/fiche_chauffeur.dart';

/// « Informations personnelles » du chauffeur (menu « Plus » de son onglet
/// Compte) : même parcours et même présentation que la page du client
/// (`InformationsPersonnellesPage`) — profil chargé, avatar, champs les uns
/// sous les autres, « Enregistrer les modifications », confirmation, la page
/// reste ouverte — avec en plus sa moto (marque, modèle, couleur) et sa
/// plaque.
///
/// Dossier validé : le téléphone change aussitôt ; nom, moto et plaque
/// partent en vérification chez Sprint (pièces à l'appui) avant que ses
/// clients ne voient le changement (voir [planifierFiche]).
class InformationsPersonnellesChauffeurPage extends StatefulWidget {
  const InformationsPersonnellesChauffeurPage({super.key, required this.service, this.chargerProfil});

  final FicheChauffeurService service;

  /// Lecture du profil `users/{uid}` ; `null` : compte connecté
  /// ([AuthRepository.chargerProfilUtilisateur], comme côté client).
  final Future<Map<String, dynamic>?> Function()? chargerProfil;

  @override
  State<InformationsPersonnellesChauffeurPage> createState() => _InformationsPersonnellesChauffeurPageState();
}

class _InformationsPersonnellesChauffeurPageState extends State<InformationsPersonnellesChauffeurPage> {
  final _formKey = GlobalKey<FormState>();
  final _prenom = TextEditingController();
  final _nom = TextEditingController();
  final _email = TextEditingController();
  final _telephone = TextEditingController();
  final _marque = TextEditingController();
  final _modele = TextEditingController();
  final _couleur = TextEditingController();
  final _plaque = TextEditingController();

  FicheChauffeur _fiche = const FicheChauffeur();
  bool _chargement = true;
  bool _echecChargement = false;
  bool _enregistrement = false;
  bool _annulation = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    for (final c in [_prenom, _nom, _email, _telephone, _marque, _modele, _couleur, _plaque]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<Map<String, dynamic>?> _lireProfil() => (widget.chargerProfil ?? AuthRepository().chargerProfilUtilisateur)();

  Future<void> _charger() async {
    if (_echecChargement) setState(() => _echecChargement = false); // « Réessayer »
    try {
      final profil = await _lireProfil();
      if (!mounted) return;
      setState(() {
        _remplir(FicheChauffeur.depuis(profil));
        _chargement = false;
      });
    } on Object {
      if (mounted) setState(() => _echecChargement = true);
    }
  }

  /// Après un enregistrement : relit le profil (demande en vérification,
  /// noms mis en forme) sans écran de chargement ; en cas d'échec, la page
  /// garde ce qu'elle montre.
  Future<void> _rafraichir() async {
    try {
      final profil = await _lireProfil();
      if (mounted) setState(() => _remplir(FicheChauffeur.depuis(profil)));
    } on Object {
      // Rien à faire : la saisie reste affichée.
    }
  }

  /// Remplit le formulaire : une demande en attente (dossier validé)
  /// l'emporte, c'est ce que le chauffeur a demandé en dernier.
  void _remplir(FicheChauffeur f) {
    _fiche = f;
    final d = f.estValide ? f.modificationDemandee : null;
    final (prenom, nom) = f.prenomEtNom;
    _prenom.text = d?.prenom ?? prenom;
    _nom.text = d?.nomDeFamille ?? nom;
    _email.text = f.email;
    _telephone.text = f.telephone;
    _marque.text = d?.moto.marque ?? f.moto.marque;
    _modele.text = d?.moto.modele ?? f.moto.modele;
    _couleur.text = d?.moto.couleur ?? f.moto.couleur;
    _plaque.text = d?.plaque ?? f.plaque;
  }

  Future<void> _enregistrer() async {
    if (!_formKey.currentState!.validate()) return;
    final telephoneChange = _telephone.text.trim() != _fiche.telephone;
    setState(() {
      _enregistrement = true;
      _erreur = null;
    });
    try {
      final resultat = await widget.service.enregistrer(
        avant: _fiche,
        prenom: _prenom.text,
        nomDeFamille: _nom.text,
        telephone: _telephone.text,
        moto: MotoChauffeur(marque: _marque.text, modele: _modele.text, couleur: _couleur.text),
        plaque: _plaque.text,
      );
      if (resultat != ResultatFiche.inchange) await _rafraichir();
      if (!mounted) return;
      final (titre, message) = switch (resultat) {
        ResultatFiche.inchange => ('Informations à jour', 'Aucune modification à enregistrer.'),
        ResultatFiche.enregistre => ('Informations mises à jour', 'Vos informations personnelles ont bien été enregistrées.'),
        ResultatFiche.aVerifier => (
            'Modification envoyée',
            'Sprint vérifie votre nom, votre moto ou votre plaque avec vos pièces (permis, carte grise). '
                'Vos clients verront le changement dès sa validation.'
                '${telephoneChange ? ' Votre téléphone, lui, est déjà à jour.' : ''}',
          ),
      };
      PremiumDialog.afficher(
        context,
        icon: Icons.check_circle_outline_rounded,
        titre: titre,
        message: message,
        succes: true,
      );
    } on Object {
      if (mounted) setState(() => _erreur = 'Enregistrement impossible. Vérifiez votre connexion et réessayez.');
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  Future<void> _annulerDemande() async {
    setState(() {
      _annulation = true;
      _erreur = null;
    });
    try {
      await widget.service.annulerDemande();
      await _rafraichir();
    } on Object {
      if (mounted) setState(() => _erreur = 'Annulation impossible. Vérifiez votre connexion et réessayez.');
    } finally {
      if (mounted) setState(() => _annulation = false);
    }
  }

  /// Un refus reste signalé un mois, le temps de corriger ou d'écrire au
  /// support (une modification validée ensuite l'efface aussitôt).
  static bool _refusRecent(DateTime? refuseeLe) =>
      refuseeLe != null && DateTime.now().difference(refuseeLe) < const Duration(days: 30);

  static const _note = TextStyle(fontSize: 11.5, color: AppColors.texteDiscret, height: 1.35);

  Widget _noteSousChamp(String texte, {Key? key}) => Padding(
        padding: const EdgeInsets.only(top: 6, left: 4),
        child: Text(texte, key: key, style: _note),
      );

  @override
  Widget build(BuildContext context) {
    return SousPageOnyx(
      child: Scaffold(
        appBar: AppBar(title: const Text('Informations personnelles')),
        body: SafeArea(
          child: _echecChargement
              ? _EchecChargement(onReessayer: _charger)
              : _chargement
                  ? const Center(child: CircularProgressIndicator(color: AppColors.vert))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(child: _Avatar(initiale: _prenom.text, photo: _fiche.photo)),
                            const SizedBox(height: 28),
                            if (_fiche.estValide && _fiche.modificationDemandee != null) ...[
                              _DemandeEnAttente(
                                demande: _fiche.modificationDemandee!,
                                enCours: _annulation,
                                onAnnuler: _annulerDemande,
                              ),
                              const SizedBox(height: 20),
                            ] else if (_fiche.estValide && _refusRecent(_fiche.modificationRefuseeLe)) ...[
                              const _ModificationRefusee(),
                              const SizedBox(height: 20),
                            ],
                            AppTextField(
                              key: const ValueKey('champ-prenom'),
                              label: 'Prénom *',
                              controller: _prenom,
                              prefixIcon: Icons.person_outline,
                              onChanged: (_) => setState(() {}),
                              validator: (v) => validerNomPropre(v, champ: 'Prénom'),
                            ),
                            const SizedBox(height: 14),
                            AppTextField(
                              key: const ValueKey('champ-nom'),
                              label: 'Nom *',
                              controller: _nom,
                              prefixIcon: Icons.person_outline,
                              validator: (v) => validerNomPropre(v, champ: 'Nom'),
                            ),
                            _noteSousChamp('Comme sur votre permis de conduire : c\'est le nom que voient vos clients.'),
                            const SizedBox(height: 14),
                            AppTextField(
                              key: const ValueKey('champ-email'),
                              label: 'Email',
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              prefixIcon: Icons.mail_outline,
                              readOnly: true,
                            ),
                            _noteSousChamp('La modification de l\'email n\'est pas encore disponible ici.'),
                            const SizedBox(height: 14),
                            AppTextField(
                              key: const ValueKey('champ-telephone'),
                              label: 'Téléphone',
                              controller: _telephone,
                              keyboardType: TextInputType.phone,
                              prefixIcon: Icons.phone_outlined,
                              validator: (v) => (v == null || v.trim().length < 6) ? 'Numéro requis.' : null,
                            ),
                            const SizedBox(height: 26),
                            const Text(
                              'Ma moto',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.texte),
                            ),
                            if (_fiche.moto.description.isEmpty && _fiche.vehiculeEnregistre.isNotEmpty)
                              _noteSousChamp(
                                'Enregistré aujourd\'hui : ${_fiche.vehiculeEnregistre}. '
                                'Précisez la marque, le modèle et la couleur.',
                                key: const ValueKey('ancienne-moto'),
                              ),
                            const SizedBox(height: 12),
                            AppTextField(
                              key: const ValueKey('champ-marque'),
                              label: 'Marque *',
                              hint: 'Ex : Bajaj',
                              controller: _marque,
                              prefixIcon: Icons.two_wheeler_rounded,
                              validator: (v) => validerChampMoto(v, champ: 'Marque'),
                            ),
                            const SizedBox(height: 14),
                            AppTextField(
                              key: const ValueKey('champ-modele'),
                              label: 'Modèle *',
                              hint: 'Ex : Boxer 125',
                              controller: _modele,
                              prefixIcon: Icons.two_wheeler_rounded,
                              validator: (v) => validerChampMoto(v, champ: 'Modèle'),
                            ),
                            const SizedBox(height: 14),
                            AppTextField(
                              key: const ValueKey('champ-couleur'),
                              label: 'Couleur *',
                              hint: 'Ex : Noir',
                              controller: _couleur,
                              prefixIcon: Icons.palette_outlined,
                              validator: (v) => validerChampMoto(v, champ: 'Couleur'),
                            ),
                            const SizedBox(height: 14),
                            AppTextField(
                              key: const ValueKey('champ-plaque'),
                              label: "Plaque d'immatriculation *",
                              hint: 'Ex : DK-1234-AB',
                              controller: _plaque,
                              prefixIcon: Icons.pin_outlined,
                              validator: validerPlaque,
                            ),
                            if (_fiche.estValide)
                              _noteSousChamp(
                                'Dossier validé : un changement de nom, de moto ou de plaque est vérifié par Sprint '
                                'avec vos pièces avant d\'être visible par vos clients. Le téléphone change tout de suite.',
                                key: const ValueKey('info-verification'),
                              ),
                            if (_erreur case final erreur?) ...[
                              const SizedBox(height: 14),
                              Text(erreur, style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
                            ],
                            const SizedBox(height: 28),
                            PrimaryButton(
                              label: 'Enregistrer les modifications',
                              isLoading: _enregistrement,
                              onPressed: (_enregistrement || _annulation) ? null : _enregistrer,
                            ),
                          ],
                        ),
                      ),
                    ),
        ),
      ),
    );
  }
}

/// Même avatar que la page du client (cercle vert dégradé et initiale) ;
/// la photo de profil du chauffeur à la place, s'il en a une.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.initiale, required this.photo});

  final String initiale;
  final String? photo;

  @override
  Widget build(BuildContext context) {
    final cercle = Container(
      width: 76,
      height: 76,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.vert, AppColors.vertFonce],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initiale.trim().isNotEmpty ? initiale.trim()[0].toUpperCase() : '?',
        style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold),
      ),
    );
    return SizedBox(
      width: 76,
      height: 76,
      child: ClipOval(child: ImageDocument(source: photo, width: 76, height: 76, placeholder: cercle)),
    );
  }
}

/// Demande de modification envoyée, en vérification chez Sprint.
class _DemandeEnAttente extends StatelessWidget {
  const _DemandeEnAttente({required this.demande, required this.enCours, required this.onAnnuler});

  final ModificationDemandee demande;
  final bool enCours;
  final VoidCallback onAnnuler;

  static String _date(DateTime d) {
    String deux(int n) => n.toString().padLeft(2, '0');
    return '${deux(d.day)}/${deux(d.month)}';
  }

  @override
  Widget build(BuildContext context) {
    final le = demande.demandeLe;
    return Container(
      key: const ValueKey('demande-en-attente'),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
      decoration: BoxDecoration(
        color: AppColors.alerte.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.alerte.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.hourglass_top_rounded, size: 18, color: AppColors.alerte),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Modification envoyée${le == null ? '' : ' le ${_date(le)}'}, en vérification par Sprint : '
                  '${demande.nomComplet} · ${demande.motoEtPlaque}. '
                  'D\'ici là, vos clients voient vos informations actuelles.',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.texte, height: 1.4),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: enCours ? null : onAnnuler,
              child: const Text('Annuler la demande'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dernière demande refusée par Sprint.
class _ModificationRefusee extends StatelessWidget {
  const _ModificationRefusee();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('modification-refusee'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.carteHaute,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.alerte.withValues(alpha: 0.4)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: AppColors.alerte),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Votre dernière modification n\'a pas été validée par Sprint. Corrigez-la ci-dessous, ou écrivez '
              'au support depuis le Centre d\'aide.',
              style: TextStyle(fontSize: 12.5, color: AppColors.texte, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _EchecChargement extends StatelessWidget {
  const _EchecChargement({required this.onReessayer});

  final VoidCallback onReessayer;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: AppColors.texteDiscret, size: 32),
            const SizedBox(height: 12),
            const Text(
              'Impossible de charger vos informations.\nVérifiez votre connexion et réessayez.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.texte, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: onReessayer, child: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}
