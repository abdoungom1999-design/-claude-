import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Historique du navigateur (site et iPhone) : à appeler une fois au
/// démarrage.
///
/// Par défaut le routeur ajoute une entrée d'historique à chaque page ;
/// le geste « retour » du téléphone (ou le bouton du navigateur) remonte
/// alors cet historique, y compris jusqu'à l'écran de connexion, et ne sait
/// pas fermer les sous-pages ouvertes à la main. En mode « entrée unique »,
/// l'historique ne grossit pas : chaque geste « retour » est transmis à
/// l'app comme un simple « retour » (fermer la page en cours). Sans effet
/// hors navigateur.
void configurerHistoriqueNavigateur() {
  if (kIsWeb) SystemNavigator.selectSingleEntryHistory();
}

/// Page racine d'un espace (accueil Client, tableau de bord Chauffeur ou
/// Admin) : un « retour » ne la quitte jamais.
///
/// Sur le site, le geste « retour » sur cette page ne fait rien (ou, si
/// [surRetour] le prévoit, revient d'abord à l'onglet principal) : il ne
/// ramène ni à l'écran de connexion ni hors de l'app. Sur l'APK Android, le
/// comportement du système est conservé (le retour depuis l'accueil quitte
/// l'app).
class RacineDeSession extends StatelessWidget {
  const RacineDeSession({super.key, required this.child, this.surRetour, this.actif});

  final Widget child;

  /// Appelé à chaque « retour » sur la racine ; renvoie `true` s'il a
  /// consommé le geste (ex. retour à l'onglet principal).
  final bool Function()? surRetour;

  /// Pour les tests ; par défaut, seulement sur le site.
  final bool? actif;

  @override
  Widget build(BuildContext context) {
    final verrouille = actif ?? kIsWeb;
    return PopScope(
      canPop: !verrouille,
      onPopInvokedWithResult: (dejaFerme, _) {
        if (!dejaFerme) surRetour?.call();
      },
      child: child,
    );
  }
}
