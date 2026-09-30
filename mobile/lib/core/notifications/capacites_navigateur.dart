import 'capacites_navigateur_stub.dart' if (dart.library.js_interop) 'capacites_navigateur_web.dart' as plateforme;

/// Ce que le navigateur dit de lui-même, utile aux notifications push.
class CapacitesNavigateur {
  const CapacitesNavigateur({this.iphone = false, this.ecranAccueil = false});

  /// iPhone ou iPad (Safari, ou le site installé sur l'écran d'accueil).
  final bool iphone;

  /// Le site tourne comme une app installée (écran d'accueil), pas dans un
  /// onglet du navigateur. Sur iPhone, c'est la condition pour pouvoir
  /// recevoir des notifications (iOS 16.4 minimum).
  final bool ecranAccueil;
}

/// Lit les capacités du navigateur ; valeurs neutres hors navigateur.
CapacitesNavigateur lireCapacitesNavigateur() => plateforme.lireCapacites();
