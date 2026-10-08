import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/demo/demo_data.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/token_storage.dart';
import '../../../core/notifications/notifications_push.dart';
import '../../../firebase_options.dart';
import 'connexion_telephone.dart';

/// Authentification Client, Conducteur et Admin.
///
/// Bascule automatiquement selon [DefaultFirebaseOptions.estConfigure] :
/// - Firebase configuré (vraies clés dans `firebase_options.dart`) :
///   vraie authentification via FirebaseAuth, profil persisté dans la
///   collection Firestore `users` (document indexé par l'UID Firebase).
/// - Sinon (projet Firebase pas encore créé côté Groupe Santine) :
///   authentification simulée localement (voir [DemoData]), pour que
///   la démo déployée continue de fonctionner sans interruption tant
///   que ce n'est pas fait.
///
/// Note sur l'email : Client et Conducteur utilisent leur VRAIE
/// adresse email comme identifiant FirebaseAuth — nécessaire pour la
/// vérification par email obligatoire (voir
/// [inscrireClient]/[inscrireConducteur]). Avant cette étape, un email
/// synthétique dérivé du téléphone était utilisé (ex.
/// `+221771234501@sprint-client.app`) ; il a été abandonné car un lien
/// de vérification envoyé à une adresse inventée ne peut jamais être
/// reçu, ce qui aurait bloqué définitivement l'inscription.
///
/// L'écran de connexion accepte désormais indifféremment l'email ou le
/// téléphone (champ mixte) : [_resoudreEmail] utilise directement la
/// saisie si elle contient un '@', sinon la traite comme un téléphone
/// et demande au serveur ([ConnexionTelephone]) l'adresse email associée
/// avant d'appeler FirebaseAuth. L'annuaire Firestore
/// `annuaire_telephones` n'est plus lisible par l'app : le serveur ne
/// rend l'email qu'à celui qui connaît le mot de passe.
///
/// Sécurité (voir `firestore.rules`) : le document `users/{uid}` est
/// privé (propriétaire et Admin uniquement), car il contient les pièces
/// KYC et les statuts de modération. Ce qui doit être visible des autres
/// est publié à part par [_publierProfilEtAnnuaire] :
/// - `profils_publics/{uid}` : nom, téléphone, rôle (chat, appel) ;
/// - `annuaire_telephones/{role}_{telephone}` : uid et email, pour la
///   connexion par téléphone. Écrit et lu par le serveur seul ([ConnexionTelephone.synchroniserAnnuaire]
///   publie l'entrée du compte connecté) : l'app n'y a plus aucun accès.
/// Les comptes créés avant ces règles sont publiés à leur prochaine
/// connexion, ou d'un coup par l'Admin (voir
/// `AdminKycService.synchroniserProfilsPublics`).
class AuthRepository {
  AuthRepository({ConnexionTelephone? connexionTelephone})
      : _connexionTelephone = connexionTelephone ?? ConnexionTelephone();

  final _tokenStorage = TokenStorage();
  final ConnexionTelephone _connexionTelephone;

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  Future<void> inscrireClient({
    required String nom,
    required String email,
    required String telephone,
    required String motDePasse,
  }) async {
    if (!DefaultFirebaseOptions.estConfigure) {
      return _authentifierEnModeDemo();
    }
    try {
      final identifiants = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: motDePasse,
      );
      await identifiants.user!.sendEmailVerification();
      await _firestore.collection('users').doc(identifiants.user!.uid).set({
        'role': 'client',
        'nom': nom,
        // Email tel que normalisé par FirebaseAuth (minuscules) : les
        // règles exigent qu'il soit identique à celui du jeton.
        'email': identifiants.user!.email ?? email,
        'telephone': telephone,
        'statut': 'ACTIF',
        'creeLe': FieldValue.serverTimestamp(),
      });
      await _publierProfilEtAnnuaire();
    } on FirebaseAuthException catch (e) {
      throw ApiException.depuisFirebaseAuth(e);
    }
  }

  /// [identifiant] : email ou numéro de téléphone, saisis
  /// indifféremment dans le même champ (voir [_resoudreEmail]).
  Future<void> connecterClient({
    required String identifiant,
    required String motDePasse,
  }) async {
    if (!DefaultFirebaseOptions.estConfigure) {
      return _authentifierEnModeDemo();
    }
    try {
      final email = await _resoudreEmail(identifiant, role: 'client', motDePasse: motDePasse);
      await _auth.signInWithEmailAndPassword(email: email, password: motDePasse);
      await _publierProfilEtAnnuaire();
    } on FirebaseAuthException catch (e) {
      throw ApiException.depuisFirebaseAuth(e);
    }
  }

  /// Soumet le dossier complet d'inscription Conducteur (identité,
  /// véhicule, pièces justificatives). Le profil Firestore est créé
  /// avec `estValide: false` : le chauffeur atterrit sur
  /// [ValidationPendingPage] tant qu'un administrateur ne l'a pas
  /// validé (et, avant même cela, sur l'écran de vérification email
  /// tant que son adresse n'est pas confirmée). En mode démo, la même
  /// règle KYC est appliquée localement via
  /// [DemoData.soumettreDossierConducteur].
  Future<void> inscrireConducteur({
    required String nom,
    required String email,
    required String telephone,
    required String motDePasse,
    required String vehiculeId,
    required String plaqueImmatriculation,
  }) async {
    if (!DefaultFirebaseOptions.estConfigure) {
      await _authentifierEnModeDemo();
      DemoData.soumettreDossierConducteur(
        nom: nom,
        telephone: telephone,
        vehiculeId: vehiculeId,
        plaqueImmatriculation: plaqueImmatriculation,
      );
      return;
    }
    try {
      final identifiants = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: motDePasse,
      );
      await identifiants.user!.sendEmailVerification();
      await _firestore.collection('users').doc(identifiants.user!.uid).set({
        'role': 'conducteur',
        'nom': nom,
        'email': identifiants.user!.email ?? email,
        'telephone': telephone,
        'vehiculeId': vehiculeId,
        'plaqueImmatriculation': plaqueImmatriculation,
        'statut': 'HORS_LIGNE',
        'estValide': false,
        'creeLe': FieldValue.serverTimestamp(),
      });
      await _publierProfilEtAnnuaire();
    } on FirebaseAuthException catch (e) {
      throw ApiException.depuisFirebaseAuth(e);
    }
  }

  /// [identifiant] : email ou numéro de téléphone, saisis
  /// indifféremment dans le même champ (voir [_resoudreEmail]).
  Future<void> connecterConducteur({
    required String identifiant,
    required String motDePasse,
  }) async {
    if (!DefaultFirebaseOptions.estConfigure) {
      return _authentifierEnModeDemo();
    }
    try {
      final email = await _resoudreEmail(identifiant, role: 'conducteur', motDePasse: motDePasse);
      await _auth.signInWithEmailAndPassword(email: email, password: motDePasse);
      await _publierProfilEtAnnuaire();
    } on FirebaseAuthException catch (e) {
      throw ApiException.depuisFirebaseAuth(e);
    }
  }

  /// Comptes Admin créés hors application (Console Firebase ou
  /// Firestore directement) : pas d'inscription publique, uniquement
  /// une connexion par un vrai email. Volontairement pas soumis à la
  /// vérification email obligatoire (voir [inscrireClient]) : ce sont
  /// des comptes internes provisionnés à la main, pas une inscription
  /// publique à sécuriser contre les faux comptes.
  ///
  /// Un mot de passe correct ne suffit pas : le document `users/{uid}`
  /// doit porter `role: 'admin'` (posé à la main dans la Console
  /// Firebase, voir FIREBASE_SETUP.md étape 6 — les règles Firestore
  /// interdisent à quiconque de se l'attribuer). Sinon la session est
  /// fermée aussitôt. C'est un confort d'interface : la vraie barrière
  /// reste `firestore.rules`, qui refuse toute action Admin à un compte
  /// sans ce rôle, même en contournant l'app.
  Future<void> connecterAdmin({
    required String email,
    required String motDePasse,
  }) async {
    if (!DefaultFirebaseOptions.estConfigure) {
      return _authentifierEnModeDemo();
    }
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: motDePasse);
    } on FirebaseAuthException catch (e) {
      throw ApiException.depuisFirebaseAuth(e);
    }
    if (!await estAdmin()) {
      await _auth.signOut();
      throw ApiException("Ce compte n'a pas les droits administrateur.");
    }
  }

  /// `true` si l'utilisateur connecté a le rôle Admin (`users/{uid}`,
  /// `role == 'admin'`). Toujours `true` en mode démo (pas de backend),
  /// pour que le tableau de bord de démonstration reste accessible.
  Future<bool> estAdmin() async {
    if (!DefaultFirebaseOptions.estConfigure) return true;
    final utilisateur = _auth.currentUser ?? await _auth.authStateChanges().first;
    if (utilisateur == null) return false;
    try {
      final doc = await _firestore.collection('users').doc(utilisateur.uid).get();
      return doc.data()?['role'] == 'admin';
    } on FirebaseException {
      return false;
    }
  }

  /// Renvoie l'email de vérification au compte actuellement connecté
  /// (bouton "Renvoyer l'email" de l'écran de blocage).
  Future<void> renvoyerEmailVerification() async {
    final utilisateur = _auth.currentUser;
    if (utilisateur == null) return;
    try {
      await utilisateur.sendEmailVerification();
    } on FirebaseAuthException catch (e) {
      throw ApiException.depuisFirebaseAuth(e);
    }
  }

  /// Recharge l'état du compte Firebase (nécessaire : `emailVerified`
  /// ne se met pas à jour tout seul côté client après un clic sur le
  /// lien reçu par email) et retourne si l'email est désormais vérifié.
  Future<bool> rafraichirEtVerifierEmail() async {
    final utilisateur = _auth.currentUser;
    if (utilisateur == null) return false;
    await utilisateur.reload();
    return _auth.currentUser?.emailVerified ?? false;
  }

  Future<void> deconnecter() async {
    // Le téléphone ne doit plus recevoir les notifications de ce compte :
    // à faire avant la déconnexion, tant que les règles l'autorisent.
    await NotificationsPush.instance.desactiver();
    if (DefaultFirebaseOptions.estConfigure) {
      await _auth.signOut();
    }
    await _tokenStorage.effacerTokens();
  }

  /// Flux temps réel du document Firestore `users/{uid}` de
  /// l'utilisateur connecté (nom, email, téléphone…), pour afficher le
  /// vrai profil sur l'onglet Compte sans données de démo en dur. Émet
  /// `null` en mode démo (pas de projet Firebase configuré) ou si
  /// personne n'est connecté — l'appelant retombe alors sur [DemoData].
  Stream<Map<String, dynamic>?> profilUtilisateurStream() {
    if (!DefaultFirebaseOptions.estConfigure) return Stream.value(null);
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(null);
    return _firestore.collection('users').doc(uid).snapshots().map((doc) => doc.data());
  }

  /// Charge une fois le profil Firestore de l'utilisateur connecté,
  /// pour pré-remplir le formulaire "Informations personnelles". `null`
  /// en mode démo ou si personne n'est connecté.
  Future<Map<String, dynamic>?> chargerProfilUtilisateur() async {
    if (!DefaultFirebaseOptions.estConfigure) return null;
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    final doc = await _firestore.collection('users').doc(uid).get();
    return doc.data();
  }

  /// Met à jour le nom et le téléphone du profil Firestore de
  /// l'utilisateur connecté ("Informations personnelles"). Ne modifie
  /// jamais l'email d'authentification Firebase — un changement
  /// d'email exigerait une réauthentification et une nouvelle
  /// vérification, hors périmètre ici. En mode démo, répercute le
  /// changement dans [DemoData] pour garder l'expérience cohérente.
  Future<void> mettreAJourProfil({
    required String nom,
    required String telephone,
  }) async {
    if (!DefaultFirebaseOptions.estConfigure) {
      final parties = nom.trim().split(RegExp(r'\s+'));
      DemoData.mettreAJourProfilClient(
        prenom: parties.isNotEmpty ? parties.first : '',
        nom: parties.length > 1 ? parties.sublist(1).join(' ') : '',
        telephone: telephone,
        email: DemoData.monEmailClient,
      );
      return;
    }
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _firestore.collection('users').doc(uid).update({
      'nom': nom,
      'telephone': telephone,
    });
    // Numéro changé : le serveur publie la nouvelle entrée d'annuaire et
    // retire l'ancienne (l'ancien numéro ne permet plus de se connecter).
    await _publierProfilEtAnnuaire();
  }

  /// Envoie l'email de réinitialisation de mot de passe (bouton "Mot
  /// de passe oublié ?" de l'écran de connexion). En mode démo (pas de
  /// projet Firebase configuré), simule un aller-retour réussi sans
  /// contacter Firebase, aucun email réel ne pouvant être envoyé.
  Future<void> reinitialiserMotDePasse(String email) async {
    if (!DefaultFirebaseOptions.estConfigure) {
      await Future.delayed(const Duration(milliseconds: 500));
      return;
    }
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw ApiException.depuisFirebaseAuth(e);
    }
  }

  /// Résout l'identifiant saisi sur l'écran de connexion (champ mixte
  /// email/téléphone) vers un email FirebaseAuth : utilisé tel quel
  /// s'il contient un '@', sinon traité comme un téléphone et résolu par
  /// le serveur ([ConnexionTelephone.emailPour]) : il vérifie le mot de
  /// passe et ne rend l'email qu'à son propriétaire, pour un rôle donné
  /// (un même numéro peut servir côté Client et côté Conducteur).
  Future<String> _resoudreEmail(String identifiant, {required String role, required String motDePasse}) async {
    final valeur = identifiant.trim();
    if (valeur.contains('@')) return valeur;
    return _connexionTelephone.emailPour(role: role, telephone: valeur, motDePasse: motDePasse);
  }

  /// Identifiant du document d'annuaire pour ce couple rôle/téléphone,
  /// `null` si le numéro ne peut pas servir d'identifiant Firestore.
  static String? cleAnnuaire(String role, String telephone) {
    final numero = telephone.trim();
    if (numero.isEmpty || numero.contains('/')) return null;
    return '${role}_$numero';
  }

  /// Publie (ou met à jour) le profil public et l'entrée d'annuaire de
  /// l'utilisateur connecté à partir de son profil privé `users/{uid}`
  /// (l'entrée d'annuaire est publiée par le serveur, sans attendre sa
  /// réponse). Appelé après inscription, connexion et modification du
  /// profil. Jamais bloquant : un échec (règles pas encore publiées,
  /// numéro déjà revendiqué par un autre compte…) n'empêche pas la
  /// connexion, il désactive seulement la connexion par téléphone pour ce
  /// compte.
  Future<void> _publierProfilEtAnnuaire() async {
    final utilisateur = _auth.currentUser;
    if (utilisateur == null) return;
    try {
      final profil = (await _firestore.collection('users').doc(utilisateur.uid).get()).data();
      final role = profil?['role'];
      if (role != 'client' && role != 'conducteur') return;
      final nom = profil?['nom'] as String? ?? '';
      final telephone = profil?['telephone'] as String? ?? '';

      await _firestore.collection('profils_publics').doc(utilisateur.uid).set(
        {'nom': nom, 'telephone': telephone, 'role': role},
        SetOptions(merge: true),
      );

      unawaited(_connexionTelephone.synchroniserAnnuaire());
    } on FirebaseException {
      // Voir la doc ci-dessus : volontairement non bloquant.
    }
  }

  /// Simule un aller-retour réseau réussi (délai réaliste + jeton
  /// factice) sans contacter Firebase. Utilisé tant que le projet
  /// Firebase n'est pas configuré (voir [DefaultFirebaseOptions]).
  Future<void> _authentifierEnModeDemo() async {
    await Future.delayed(const Duration(milliseconds: 500));
    await _tokenStorage.enregistrerTokens(
      accessToken: 'demo-access-token',
      refreshToken: 'demo-refresh-token',
    );
  }
}
