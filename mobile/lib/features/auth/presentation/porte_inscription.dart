import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/firebase/fonctions_cloud.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../firebase_options.dart';
import '../data/auth_repository.dart';
import '../data/reglage_inscription.dart';
import '../data/role_du_compte.dart';
import '../data/validation_telephone.dart';
import 'bienvenue_sprint_page.dart';
import 'validation_telephone_page.dart';

/// Le compte connecté, tel que la porte le lit.
class CompteConnecte {
  const CompteConnecte({required this.uid, required this.emailVerifie, required this.creeLe});

  final String uid;
  final bool emailVerifie;

  /// Création du compte Firebase Auth (posée par Google) ; `null` si inconnue.
  final DateTime? creeLe;
}

/// Le compte connecté à l'instant ; `null` sans connexion, en démo ou en test.
CompteConnecte? compteFirebaseConnecte() {
  if (!DefaultFirebaseOptions.estConfigure) return null;
  try {
    final utilisateur = FirebaseAuth.instance.currentUser;
    if (utilisateur == null) return null;
    return CompteConnecte(
      uid: utilisateur.uid,
      emailVerifie: utilisateur.emailVerified,
      creeLe: utilisateur.metadata.creationTime,
    );
  } on Object {
    // Firebase pas démarré (tests, démo) : rien à vérifier.
    return null;
  }
}

/// Dernière étape de l'inscription d'un NOUVEAU compte, entre la vérification
/// de l'e-mail (écran des espaces Client et Chauffeur) et l'espace lui-même :
///   1. validation du numéro par SMS (écran du code à 6 chiffres) ;
///   2. message « Bienvenue chez SPRINT » (écran, une seule fois).
///
/// Elle ne fait RIEN, et ne lit rien, tant que [ReglageInscription] est fermé
/// (état de la publication 126), pour un compte créé avant l'ouverture du
/// tunnel, ou tant que son e-mail n'est pas vérifié (l'espace affiche alors son
/// propre écran « Vérifiez votre adresse e-mail », comme avant) : [enfant] est
/// rendu tel quel, sans aucune lecture ni aucun appel de plus. Aucun paiement,
/// aucune course, aucun compte de test n'est concerné.
///
/// Toute défaillance (profil illisible, serveur lent, réponse inattendue) laisse
/// passer vers l'espace : la porte n'enferme jamais personne par accident. Elle
/// ne remplace pas le serveur, qui contrôle la validation et la bienvenue
/// lui-même (`functions/src/inscription.ts`).
class PorteInscription extends StatefulWidget {
  const PorteInscription({
    super.key,
    required this.enfant,
    this.reglage = const ReglageInscription(),
    this.compteConnecte,
    this.lireProfil,
    this.service,
    this.declencherBienvenue,
    this.enregistrerNumero,
    this.surDeconnexion,
    this.passeAvant,
    this.retenirPasse,
    this.delaiSurveillance = const Duration(seconds: 3),
    this.delaiReponse = const Duration(seconds: 10),
  });

  /// L'espace du compte (accueil Client ou accueil Chauffeur).
  final Widget enfant;
  final ReglageInscription reglage;

  // Accès à Firebase, remplaçables dans les tests.
  final CompteConnecte? Function()? compteConnecte;
  final Future<Map<String, dynamic>?> Function(String uid)? lireProfil;
  final ValidationTelephone? service;
  final Future<Map<String, dynamic>> Function()? declencherBienvenue;
  final Future<void> Function(String numero)? enregistrerNumero;
  final Future<void> Function()? surDeconnexion;

  /// « Plus tard » déjà choisi sur cet appareil (validation facultative).
  final Future<bool> Function(String uid)? passeAvant;
  final Future<void> Function(String uid)? retenirPasse;

  /// Intervalle de relecture de l'e-mail pendant qu'il n'est pas vérifié.
  final Duration delaiSurveillance;

  /// Au plus ce temps pour lire le profil ou demander la bienvenue : au-delà, l'espace s'ouvre.
  final Duration delaiReponse;

  @override
  State<PorteInscription> createState() => _PorteInscriptionState();
}

enum _Etat { aEvaluer, chargement, validation, bienvenue, libre }

class _PorteInscriptionState extends State<PorteInscription> {
  _Etat _etat = _Etat.aEvaluer;
  Timer? _surveillance;
  Map<String, dynamic>? _profil;
  late final ValidationTelephone _service = widget.service ?? ValidationTelephone();

  @override
  void initState() {
    super.initState();
    _verifier();
  }

  @override
  void didUpdateWidget(PorteInscription ancienne) {
    super.didUpdateWidget(ancienne);
    _verifier();
  }

  @override
  void dispose() {
    _surveillance?.cancel();
    super.dispose();
  }

  CompteConnecte? _compte() => (widget.compteConnecte ?? compteFirebaseConnecte)();

  /// Cette personne est-elle concernée ? Fermé ou compte ancien : jamais, sans rien lire.
  bool _concerne(CompteConnecte? compte) => widget.reglage.ouvert && compte != null && widget.reglage.estNouveau(compte.creeLe);

  void _verifier({bool depuisMinuteur = false}) {
    if (_etat != _Etat.aEvaluer) return;
    // Fermé (état livré) : rien du tout, pas même un regard sur le compte connecté.
    if (!widget.reglage.ouvert) return;
    final compte = _compte();
    if (!_concerne(compte)) {
      _surveillance?.cancel();
      _surveillance = null;
      return;
    }
    if (!compte!.emailVerifie) {
      // L'espace montre « Vérifiez votre adresse e-mail » ; on attend qu'elle le soit.
      _surveillance ??= Timer.periodic(widget.delaiSurveillance, (_) => _verifier(depuisMinuteur: true));
      return;
    }
    _surveillance?.cancel();
    _surveillance = null;
    if (depuisMinuteur) {
      _passer(_Etat.chargement);
    } else {
      _etat = _Etat.chargement; // dans initState ou didUpdateWidget : la construction suit
    }
    unawaited(_evaluer(compte));
  }

  Future<Map<String, dynamic>?> _lireProfil(String uid) => (widget.lireProfil ?? _profilFirestore)(uid);

  static Future<Map<String, dynamic>?> _profilFirestore(String uid) async =>
      (await FirebaseFirestore.instance.collection('users').doc(uid).get()).data();

  Future<bool> _passeAvant(String uid) async {
    try {
      final passe = widget.passeAvant;
      if (passe != null) return await passe(uid);
      return await MemoireSecurisee(cle: 'sprint_validation_tel_passee_$uid').lire() == '1';
    } on Object {
      return false;
    }
  }

  Future<void> _retenirPasse(String uid) async {
    try {
      final retenir = widget.retenirPasse;
      if (retenir != null) return await retenir(uid);
      await MemoireSecurisee(cle: 'sprint_validation_tel_passee_$uid').ecrire('1');
    } on Object {
      // Mémoire refusée : la personne reverra l'écran à la prochaine ouverture, rien de plus.
    }
  }

  void _passer(_Etat suivant) {
    if (mounted) setState(() => _etat = suivant);
  }

  Future<void> _evaluer(CompteConnecte compte) async {
    Map<String, dynamic>? profil;
    try {
      profil = await _lireProfil(compte.uid).timeout(widget.delaiReponse);
    } on Object {
      return _passer(_Etat.libre);
    }
    final role = profil?['role'];
    if (profil == null || (role != 'client' && role != 'conducteur')) return _passer(_Etat.libre);
    _profil = profil;

    if (widget.reglage.validation != EtatValidationTelephone.fermee && !numeroValide(profil)) {
      final obligatoire = widget.reglage.validation == EtatValidationTelephone.obligatoire;
      if (obligatoire || !await _passeAvant(compte.uid)) return _passer(_Etat.validation);
    }
    await _terminer();
  }

  /// Numéro validé (ou non demandé) : « Bienvenue chez SPRINT », une seule fois.
  Future<void> _terminer() async {
    final profil = _profil;
    if (profil == null || !widget.reglage.bienvenue || profil['bienvenueEnvoyeeLe'] != null) return _passer(_Etat.libre);
    try {
      final reponse = await (widget.declencherBienvenue ?? _bienvenueServeur)().timeout(widget.delaiReponse);
      if (reponse['envoye'] == true) return _passer(_Etat.bienvenue);
    } on Object {
      // Le serveur décide : sans réponse, l'espace s'ouvre sans écran de bienvenue.
    }
    _passer(_Etat.libre);
  }

  static Future<Map<String, dynamic>> _bienvenueServeur() => FonctionsCloud.appeler('declencherBienvenue', {});

  Future<void> _plusTard() async {
    final uid = _compte()?.uid;
    if (uid != null) await _retenirPasse(uid);
    await _terminer();
  }

  Future<void> _deconnecter() async {
    final personnalise = widget.surDeconnexion;
    if (personnalise != null) return personnalise();
    await AuthRepository().deconnecter();
    if (mounted) context.go(AppRoutes.espacePro);
  }

  @override
  Widget build(BuildContext context) {
    switch (_etat) {
      case _Etat.aEvaluer:
      case _Etat.libre:
        return widget.enfant;
      case _Etat.chargement:
        return const Scaffold(
          backgroundColor: AppColors.fond,
          body: Center(child: CircularProgressIndicator(color: AppColors.vert)),
        );
      case _Etat.validation:
        return ValidationTelephonePage(
          numeroInitial: _profil?['telephone'] as String? ?? '',
          service: _service,
          surValide: () => unawaited(_terminer()),
          surDeconnexion: _deconnecter,
          enregistrerNumero: widget.enregistrerNumero ?? (numero) => AuthRepository().mettreAJourTelephone(numero),
          surPlusTard: widget.reglage.validation == EtatValidationTelephone.facultative ? _plusTard : null,
        );
      case _Etat.bienvenue:
        return BienvenueSprintPage(
          role: _profil?['role'] as String? ?? 'client',
          prenom: prenomPour(_profil),
          surContinuer: () => _passer(_Etat.libre),
        );
    }
  }
}
