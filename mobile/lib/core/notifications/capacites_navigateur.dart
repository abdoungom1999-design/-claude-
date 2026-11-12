import 'capacites_navigateur_stub.dart' if (dart.library.js_interop) 'capacites_navigateur_web.dart' as plateforme;

/// Ce que le navigateur dit de lui-même, utile aux notifications push et au
/// retour dans Sprint après un paiement.
class CapacitesNavigateur {
  const CapacitesNavigateur({
    this.iphone = false,
    this.ecranAccueil = false,
    this.android = false,
    this.vueIntegree = false,
  });

  /// iPhone ou iPad (Safari, ou le site installé sur l'écran d'accueil).
  final bool iphone;

  /// Le site tourne comme une app installée (écran d'accueil), pas dans un
  /// onglet du navigateur. Sur iPhone, c'est la condition pour pouvoir
  /// recevoir des notifications (iOS 16.4 minimum).
  final bool ecranAccueil;

  /// Téléphone ou tablette Android (navigateur, ou site installé).
  final bool android;

  /// Page affichée à l'intérieur d'une autre application Android (vue web
  /// intégrée), pas dans un vrai navigateur : un lien vers une application
  /// n'y aboutit pas.
  final bool vueIntegree;
}

/// Lit les capacités du navigateur ; valeurs neutres hors navigateur.
CapacitesNavigateur lireCapacitesNavigateur() => plateforme.lireCapacites();
