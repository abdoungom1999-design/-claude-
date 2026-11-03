import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Changement d'écran commun à toute l'app sur Android (et sur ordinateur) :
/// le nouvel écran, opaque, glisse depuis la droite et chasse l'ancien, qui
/// recule légèrement vers la gauche ; au retour, l'inverse. Les deux écrans
/// ne sont jamais visibles l'un à travers l'autre.
///
/// Remplace la transition Android par défaut de Flutter :
/// - un fondu enchaîné de 450 ms, où l'ancien et le nouvel écran sont tous
///   deux semi-transparents en même temps (et où l'ancien reste affiché sous
///   le nouveau jusqu'à la fin) ;
/// - le « retour prédictif » d'Android 14 et plus, où l'écran suit le doigt
///   pendant le glissement de retour et laisse voir celui du dessous ; une
///   navigation pendant ce geste (connexion qui aboutit, par exemple) laissait
///   l'écran figé à mi-course.
/// Avec les cartes « verre » floutées et les cartes géographiques de l'app,
/// ce fondu était lourd sur un téléphone moyen : deux écrans superposés,
/// parfois figés à mi-chemin (« Espace Conducteur » par-dessus « Compte »).
///
/// Le geste de retour d'Android reste un retour normal : relâché, il revient
/// à l'écran précédent avec ce même glissement. Rien d'autre ne change : ni
/// les écrans, ni leurs boutons, ni l'ordre de navigation. Mouvement réduit
/// (réglage d'accessibilité) : changement d'écran immédiat.
class GlissementOnyxPageTransitionsBuilder extends PageTransitionsBuilder {
  const GlissementOnyxPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 260);

  /// Arrivée : depuis le bord droit jusqu'à sa place.
  static final Animatable<Offset> _arrivee =
      Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).chain(CurveTween(curve: Curves.easeOutCubic));

  /// Écran recouvert : recule d'un quart vers la gauche (toujours caché, à
  /// droite, par le nouvel écran : aucun vide entre les deux).
  static final Animatable<Offset> _recul =
      Tween<Offset>(begin: Offset.zero, end: const Offset(-0.25, 0)).chain(CurveTween(curve: Curves.easeOutCubic));

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Fond Onyx opaque sous chaque écran : même un écran au fond transparent
    // ne laisse jamais voir celui du dessous.
    final ecran = ColoredBox(color: AppColors.fond, child: child);
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return ecran;
    return SlideTransition(
      position: secondaryAnimation.drive(_recul),
      child: SlideTransition(position: animation.drive(_arrivee), child: ecran),
    );
  }
}

/// iPhone et Mac : le glissement natif d'iOS (le nouvel écran arrive par la
/// droite, l'ancien recule) et son geste de retour depuis le bord gauche,
/// inchangés, sur le même fond Onyx opaque que sur Android : aucun écran ne
/// se voit à travers un autre, même un écran au fond transparent.
class GlissementNatifOnyxPageTransitionsBuilder extends PageTransitionsBuilder {
  const GlissementNatifOnyxPageTransitionsBuilder();

  static const _natif = CupertinoPageTransitionsBuilder();

  @override
  Duration get transitionDuration => _natif.transitionDuration;

  @override
  Duration get reverseTransitionDuration => _natif.reverseTransitionDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition => _natif.delegatedTransition;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      _natif.buildTransitions(route, context, animation, secondaryAnimation, ColoredBox(color: AppColors.fond, child: child));
}
