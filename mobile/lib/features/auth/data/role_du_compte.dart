import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Une petite mémoire de l'appareil : une seule valeur texte.
abstract class MemoireLocale {
  Future<String?> lire();
  Future<void> ecrire(String valeur);
  Future<void> effacer();
}

/// [MemoireLocale] adossée au stockage sécurisé de l'appareil (Keychain iOS,
/// Keystore Android, stockage du navigateur sur le web).
class MemoireSecurisee implements MemoireLocale {
  const MemoireSecurisee({this.cle = 'sprint_role_du_compte'});

  final String cle;
  final FlutterSecureStorage _stockage = const FlutterSecureStorage();

  @override
  Future<String?> lire() => _stockage.read(key: cle);

  @override
  Future<void> ecrire(String valeur) => _stockage.write(key: cle, value: valeur);

  @override
  Future<void> effacer() => _stockage.delete(key: cle);
}

/// Rôle (`client`, `conducteur` ou `admin`) du compte connecté, retenu sur
/// l'appareil à chaque connexion.
///
/// Au démarrage, l'app envoie la personne connectée directement dans son
/// espace, sans attendre le réseau : lire le rôle sur le serveur peut prendre
/// plusieurs secondes (réseau faible, tunnel) ou échouer, et un chauffeur ne
/// doit pas se retrouver dans l'espace Client pour autant. Le rôle retenu ne
/// donne aucun droit (les écrans et `firestore.rules` décident de ce qui est
/// permis) : il sert seulement à choisir l'écran d'arrivée. Il est revérifié
/// en arrière-plan à chaque ouverture et oublié à la déconnexion.
///
/// Rien ici ne lève d'erreur : sans mémoire (stockage refusé, première
/// ouverture après la mise à jour), le rôle est lu en ligne comme avant.
class RoleDuCompte {
  RoleDuCompte({required this.memoire, required this.lireEnLigne});

  final MemoireLocale memoire;

  /// Lecture du rôle dans la base (copie de l'appareil puis serveur), `null`
  /// si introuvable.
  final Future<String?> Function(String uid) lireEnLigne;

  /// Rôle du compte [uid] : celui retenu sur l'appareil, sans attendre ; à
  /// défaut, celui lu en ligne (retenu pour la fois suivante), au plus [delai].
  /// Réseau trop lent : on n'attend pas davantage (`null`), mais la réponse,
  /// quand elle arrive, est retenue pour l'ouverture suivante.
  Future<String?> pour(String uid, {Duration delai = const Duration(seconds: 5)}) async {
    final retenu = await _retenu(uid);
    if (retenu != null) {
      unawaited(actualiser(uid));
      return retenu;
    }
    final lecture = _enLigne(uid);
    final role = await lecture.timeout(delai, onTimeout: () => null);
    if (role != null) {
      await memoriser(uid, role);
    } else {
      unawaited(lecture.then((tardif) => tardif == null ? null : memoriser(uid, tardif)));
    }
    return role;
  }

  /// Relit le rôle en ligne et le retient. Appelé après une connexion, et en
  /// arrière-plan à chaque ouverture : un rôle changé côté serveur est pris en
  /// compte à l'ouverture suivante.
  Future<void> actualiser(String uid) async {
    final role = await _enLigne(uid);
    if (role != null) await memoriser(uid, role);
  }

  Future<void> memoriser(String uid, String role) async {
    try {
      await memoire.ecrire('$uid|$role');
    } on Object {
      // Confort seulement : sans mémoire, le rôle est relu en ligne.
    }
  }

  /// À la déconnexion : le prochain compte ne doit pas hériter de ce rôle.
  Future<void> oublier() async {
    try {
      await memoire.effacer();
    } on Object {
      // Le rôle retenu est de toute façon propre à un compte (voir [_retenu]).
    }
  }

  Future<String?> _retenu(String uid) async {
    try {
      final valeur = await memoire.lire();
      if (valeur == null) return null;
      final coupure = valeur.indexOf('|');
      if (coupure <= 0 || valeur.substring(0, coupure) != uid) return null;
      final role = valeur.substring(coupure + 1);
      return role.isEmpty ? null : role;
    } on Object {
      return null;
    }
  }

  Future<String?> _enLigne(String uid) async {
    try {
      return await lireEnLigne(uid);
    } on Object {
      return null;
    }
  }
}
