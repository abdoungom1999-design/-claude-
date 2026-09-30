import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'capacites_navigateur.dart';

/// Détection dans le navigateur : iPhone / iPad (y compris iPadOS, qui se
/// présente comme un Mac tactile) et site lancé depuis l'écran d'accueil.
CapacitesNavigateur lireCapacites() {
  try {
    final navigateur = globalContext['navigator'] as JSObject;
    final agent = navigateur['userAgent'].dartify() as String? ?? '';
    final plateforme = navigateur['platform'].dartify() as String? ?? '';
    final pointsTactiles = (navigateur['maxTouchPoints'].dartify() as num?)?.toInt() ?? 0;
    final iphone = RegExp('iPhone|iPad|iPod').hasMatch(agent) || (plateforme == 'MacIntel' && pointsTactiles > 1);

    // Safari (iOS) : navigator.standalone ; autres : mode d'affichage.
    final standaloneSafari = navigateur['standalone'].dartify() as bool? ?? false;
    final media = globalContext.callMethod<JSObject>('matchMedia'.toJS, '(display-mode: standalone)'.toJS);
    final standaloneMedia = media['matches'].dartify() as bool? ?? false;
    return CapacitesNavigateur(iphone: iphone, ecranAccueil: standaloneSafari || standaloneMedia);
  } catch (_) {
    return const CapacitesNavigateur();
  }
}
