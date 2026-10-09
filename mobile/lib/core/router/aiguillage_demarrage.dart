import 'dart:async';
import 'app_routes.dart';

/// Démarrage de l'app : une personne déjà connectée arrive directement sur
/// son accueil, sans repasser par Bienvenue, le numéro de téléphone ni le
/// mot de passe.
///
/// Firebase conserve la session sur l'appareil (téléphone, navigateur) jusqu'à
/// un appui sur « Se déconnecter ». Au premier aiguillage, on attend que
/// Firebase l'ait relue (asynchrone sur le web : sans cela, un écran lisant le
/// compte connecté trop tôt croirait que personne ne l'est) ; on ne montre
/// rien d'autre que l'écran de démarrage tant que ce n'est pas fait. À
/// l'adresse de Bienvenue (`/`), un compte connecté est envoyé vers :
/// - `/conducteur` pour un chauffeur ;
/// - `/admin` pour un administrateur ;
/// - `/accueil` pour un client (et si le rôle reste introuvable).
///
/// Les autres adresses ne sont jamais redirigées ici (les écrans gardent
/// leurs propres garde-fous : e-mail à vérifier, dossier chauffeur, rôle
/// Admin). Sans session, ou si quoi que ce soit échoue, rien ne change :
/// l'écran de Bienvenue s'affiche, comme avant.
///
/// Les accès à Firebase sont injectés : la logique se teste sans Firebase.
class AiguillageDemarrage {
  AiguillageDemarrage({
    required this.pret,
    required this.attendreSession,
    required this.uidConnecte,
    required this.roleDe,
  });

  /// Firebase est-il relié et démarré ? Sinon (démo, test) : aucune
  /// redirection, et l'aiguillage répond tout de suite, sans attente.
  final bool Function() pret;

  /// Attend la première lecture de la session conservée.
  final Future<void> Function() attendreSession;

  /// Compte connecté à l'instant (sans attendre), `null` si personne.
  final String? Function() uidConnecte;

  /// Rôle (`client`, `conducteur`, `admin`) du compte, `null` si introuvable.
  final Future<String?> Function(String uid) roleDe;

  Future<void>? _lectureDeLaSession;
  bool _sessionLue = false;

  /// Où envoyer pour l'adresse [emplacement] : une adresse, ou `null` pour
  /// rester où l'on est. À brancher sur `GoRouter(redirect: …)`. Répond sans
  /// attendre (valeur directe) chaque fois que c'est possible.
  FutureOr<String?> destination(String emplacement) {
    if (!_firebasePret()) return null;
    if (_sessionLue) return _decider(emplacement);
    return (_lectureDeLaSession ??= _lireLaSession()).then((_) => _decider(emplacement));
  }

  bool _firebasePret() {
    try {
      return pret();
    } on Object {
      return false;
    }
  }

  Future<void> _lireLaSession() async {
    try {
      await attendreSession();
    } on Object {
      // Session illisible : on décidera avec ce que Firebase connaît déjà.
    }
    _sessionLue = true;
  }

  FutureOr<String?> _decider(String emplacement) {
    if (emplacement != AppRoutes.welcome) return null;
    final String? uid;
    try {
      uid = uidConnecte();
    } on Object {
      return null;
    }
    if (uid == null) return null;
    return _accueilDuRole(uid);
  }

  Future<String> _accueilDuRole(String uid) async {
    String? role;
    try {
      role = await roleDe(uid);
    } on Object {
      role = null;
    }
    return switch (role) {
      'conducteur' => AppRoutes.conducteur,
      'admin' => AppRoutes.admin,
      _ => AppRoutes.home,
    };
  }
}
