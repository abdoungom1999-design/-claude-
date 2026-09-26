import 'maintien_ecran_stub.dart' if (dart.library.js_interop) 'maintien_ecran_web.dart' as plateforme;

/// Garde l'écran du téléphone allumé tant que le chauffeur est en ligne
/// (API Screen Wake Lock du navigateur).
///
/// Pourquoi : l'app est une application web. Un navigateur mobile coupe
/// la géolocalisation dès que l'écran se verrouille ou que l'onglet
/// passe en arrière-plan ; empêcher la mise en veille est le seul moyen,
/// côté web, de continuer à envoyer la position. Sans effet sur les
/// navigateurs qui ne supportent pas cette API (Safari avant iOS 16.4).
class MaintienEcran {
  Future<void> activer() => plateforme.activer();

  Future<void> desactiver() => plateforme.desactiver();
}
