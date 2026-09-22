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
/// Note sur le téléphone comme identifiant : FirebaseAuth s'appuie sur
/// email + mot de passe. Client et Conducteur s'identifient par
/// numéro de téléphone dans l'UI (pas d'email obligatoire), donc on
/// dérive un email synthétique stable à partir du téléphone (ex.
/// `+221771234501@sprint-client.app`) — un contournement courant pour
/// utiliser l'auth email/mot de passe avec un identifiant téléphone.
/// Ce n'est PAS une vérification par SMS/OTP réelle : à ajouter à part
/// (Firebase Phone Auth) si le Groupe Santine veut confirmer les
/// numéros pour de vrai.
class AuthRepository {
  final _tokenStorage = TokenStorage();

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  Future<void> inscrireClient({
    required String nom,
    required String telephone,
    required String motDePasse,
  }) async {
    if (!DefaultFirebaseOptions.estConfigure) {
      return _authentifierEnModeDemo();
    }
    try {
      final identifiants = await _auth.createUserWithEmailAndPassword(
        email: _emailClient(telephone),
        password: motDePasse,
      );
      await _firestore.collection('users').doc(identifiants.user!.uid).set({
        'role': 'client',
        'nom': nom,
        'telephone': telephone,
        'statut': 'ACTIF',
        'creeLe': FieldValue.serverTimestamp(),
      });
    } on FirebaseAuthException catch (e) {
      throw ApiException.depuisFirebaseAuth(e);
    }
  }

  Future<void> connecterClient({
    required String telephone,
    required String motDePasse,
  }) async {
    if (!DefaultFirebaseOptions.estConfigure) {
      return _authentifierEnModeDemo();
    }
    try {
      await _auth.signInWithEmailAndPassword(
        email: _emailClient(telephone),
        password: motDePasse,
      );
    } on FirebaseAuthException catch (e) {
      throw ApiException.depuisFirebaseAuth(e);
    }
  }

  /// Soumet le dossier complet d'inscription Conducteur (identité,
  /// véhicule, pièces justificatives). Le profil Firestore est créé
  /// avec `estValide: false` : le chauffeur atterrit sur
  /// [ValidationPendingPage] tant qu'un administrateur ne l'a pas
  /// validé. En mode démo, la même règle est appliquée localement via
  /// [DemoData.soumettreDossierConducteur].
  Future<void> inscrireConducteur({
    required String nom,
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
        email: _emailConducteur(telephone),
        password: motDePasse,
      );
      await _firestore.collection('users').doc(identifiants.user!.uid).set({
        'role': 'conducteur',
        'nom': nom,
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

  Future<void> connecterConducteur({
    required String telephone,
    required String motDePasse,
  }) async {
    if (!DefaultFirebaseOptions.estConfigure) {
      return _authentifierEnModeDemo();
    }
    try {
      await _auth.signInWithEmailAndPassword(
        email: _emailConducteur(telephone),
        password: motDePasse,
      );
    } on FirebaseAuthException catch (e) {
      throw ApiException.depuisFirebaseAuth(e);
    }
  }

  /// Comptes Admin créés hors application (Console Firebase ou
  /// Firestore directement) : pas d'inscription publique, uniquement
  /// une connexion par un vrai email.
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

  Future<void> deconnecter() async {
    if (DefaultFirebaseOptions.estConfigure) {
      await _auth.signOut();
    }
    await _tokenStorage.effacerTokens();
  }

  String _emailClient(String telephone) =>
      '${_nettoyerTelephone(telephone)}@sprint-client.app';

  String _emailConducteur(String telephone) =>
      '${_nettoyerTelephone(telephone)}@sprint-conducteur.app';

  String _nettoyerTelephone(String telephone) =>
      telephone.trim().replaceAll(RegExp(r'\s+'), '');

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
