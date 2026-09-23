import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/demo/demo_data.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/token_storage.dart';
import '../../../firebase_options.dart';

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
/// et retrouve la vraie adresse email associée dans Firestore avant
/// d'appeler FirebaseAuth.
///
/// Important : les comptes créés avant ce changement (email
/// synthétique, sans champ `email` dans leur document Firestore) ne
/// peuvent plus être retrouvés par [_emailPourTelephone]. Il faut les
/// supprimer (Firebase Console > Authentication, et le document
/// correspondant dans Firestore > `users`) et réinscrire ces comptes
/// de test.
class AuthRepository {
  final _tokenStorage = TokenStorage();

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
        'email': email,
        'telephone': telephone,
        'statut': 'ACTIF',
        'creeLe': FieldValue.serverTimestamp(),
      });
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
      final email = await _resoudreEmail(identifiant, role: 'client');
      await _auth.signInWithEmailAndPassword(email: email, password: motDePasse);
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
        'email': email,
        'telephone': telephone,
        'vehiculeId': vehiculeId,
        'plaqueImmatriculation': plaqueImmatriculation,
        'statut': 'HORS_LIGNE',
        'estValide': false,
        'creeLe': FieldValue.serverTimestamp(),
      });
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
      final email = await _resoudreEmail(identifiant, role: 'conducteur');
      await _auth.signInWithEmailAndPassword(email: email, password: motDePasse);
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
    if (DefaultFirebaseOptions.estConfigure) {
      await _auth.signOut();
    }
    await _tokenStorage.effacerTokens();
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
  /// s'il contient un '@', sinon traité comme un téléphone et retrouvé
  /// via [_emailPourTelephone].
  Future<String> _resoudreEmail(String identifiant, {required String role}) async {
    final valeur = identifiant.trim();
    if (valeur.contains('@')) return valeur;
    return _emailPourTelephone(valeur, role: role);
  }

  /// Retrouve l'email réel associé à un numéro de téléphone (et un
  /// rôle, pour éviter qu'un même numéro utilisé à la fois côté Client
  /// et Conducteur ne se mélange), à partir de la collection
  /// Firestore `users`.
  Future<String> _emailPourTelephone(String telephone, {required String role}) async {
    final resultat = await _firestore
        .collection('users')
        .where('telephone', isEqualTo: telephone.trim())
        .where('role', isEqualTo: role)
        .limit(1)
        .get();

    if (resultat.docs.isEmpty) {
      throw ApiException('Numéro ou mot de passe incorrect.');
    }
    return resultat.docs.first.data()['email'] as String;
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
