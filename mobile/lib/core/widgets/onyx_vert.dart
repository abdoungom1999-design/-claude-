import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'logo_sprint.dart';

/// Briques de la charte « Onyx & Vert » : fond Onyx en dégradé avec des halos
/// verts, cartes « verre » (blanc très translucide, liseré fin, flou), texte
/// clair, vert vibrant pour ce qui agit. Un écran est enveloppé dans
/// [EcranOnyxVert] (onglets) ou [SousPageOnyx] (pages poussées) ; les champs,
/// boutons et cartes partagés prennent d'eux-mêmes le style de la charte.
class ThemeOnyxVert extends InheritedWidget {
  const ThemeOnyxVert({super.key, required super.child, this.flou = true});

  /// Flou de fond des cartes « verre ». Désactivé (`false`) sur les écrans
  /// denses (tableaux de bord Admin, longues listes) : la carte reste
  /// translucide, sans flou, ce qui est bien plus léger à afficher.
  final bool flou;

  /// Flou activé pour les cartes de cet écran (vrai par défaut).
  static bool flouActif(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeOnyxVert>()?.flou ?? true;

  @override
  bool updateShouldNotify(ThemeOnyxVert ancien) => ancien.flou != flou;
}

/// Fond d'écran Onyx & Vert : dégradé gris très sombre vers Onyx, avec deux
/// halos verts (en haut à droite, plus doux en bas à gauche) qui donnent au
/// verre quelque chose à flouter et créent la lueur de la charte.
class FondOnyxVert extends StatelessWidget {
  const FondOnyxVert({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.fondHaut, AppColors.fond, AppColors.fond],
          stops: [0, 0.55, 1],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned(top: -150, right: -130, child: _Halo(taille: 430, couleur: AppColors.vert, opacite: 0.20)),
          const Positioned(bottom: -190, left: -160, child: _Halo(taille: 420, couleur: AppColors.vertFonce, opacite: 0.11)),
          child,
        ],
      ),
    );
  }
}

class _Halo extends StatelessWidget {
  const _Halo({required this.taille, required this.couleur, required this.opacite});

  final double taille;
  final Color couleur;
  final double opacite;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: Container(
          width: taille,
          height: taille,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [couleur.withValues(alpha: opacite), couleur.withValues(alpha: 0)]),
          ),
        ),
      ),
    );
  }
}

/// Carte « verre » : blanc très translucide sur fond flouté, dégradé léger
/// (plus clair en haut à gauche), liseré fin, grands arrondis, ombre profonde
/// peinte seulement AUTOUR de la carte (jamais au travers du verre).
/// [contour] la cerne d'une ligne colorée (vert pour une sélection) et
/// [lueur] y ajoute un halo de la même couleur. [sombre] la teinte Onyx
/// presque opaque, pour une carte posée sur une carte géographique claire ou
/// sur une photo : le blanc à 8 % n'y ferait pas assez de contraste.
class CarteVerre extends StatelessWidget {
  const CarteVerre({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.rayon = 28,
    this.contour,
    this.lueur = false,
    this.sombre = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double rayon;
  final Color? contour;
  final bool lueur;
  final bool sombre;

  @override
  Widget build(BuildContext context) {
    final arrondi = BorderRadius.circular(rayon);
    final flou = ThemeOnyxVert.flouActif(context);
    final contenu = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: sombre
              ? const [Color(0xF50B0B0C), Color(0xEE0B0B0C)]
              : const [Color(0x1FFFFFFF), Color(0x0AFFFFFF)],
        ),
        borderRadius: arrondi,
        border: Border.all(color: contour ?? AppColors.bordVerre, width: contour == null ? 1 : 1.4),
      ),
      // Material transparent : les ListTile / InkWell de la carte y peignent
      // leur effet de pression au-dessus du fond verre (sinon masqué).
      child: Padding(padding: padding, child: Material(type: MaterialType.transparency, child: child)),
    );
    return Stack(
      clipBehavior: Clip.none,
      // Les contraintes du parent passent telles quelles à la carte : dans une
      // rangée (Expanded), elle remplit sa place au lieu de se réduire à son
      // contenu pendant que l'ombre, elle, garde la place entière.
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: ClipPath(
              clipper: _Exterieur(rayon),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: arrondi,
                  boxShadow: [
                    const BoxShadow(color: AppColors.shadow, blurRadius: 32, offset: Offset(0, 14)),
                    if (lueur) BoxShadow(color: (contour ?? AppColors.vert).withValues(alpha: 0.22), blurRadius: 26),
                  ],
                ),
              ),
            ),
          ),
        ),
        ClipRRect(
          borderRadius: arrondi,
          child: flou ? BackdropFilter(filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24), child: contenu) : contenu,
        ),
      ],
    );
  }
}

/// Tout ce qui est HORS de la carte arrondie : l'ombre n'est peinte que là,
/// sinon elle se verrait à travers le verre translucide.
class _Exterieur extends CustomClipper<Path> {
  const _Exterieur(this.rayon);

  final double rayon;

  @override
  Path getClip(Size size) => Path()
    ..fillType = PathFillType.evenOdd
    ..addRect(Rect.fromLTRB(-140, -140, size.width + 140, size.height + 180))
    ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(rayon)));

  @override
  bool shouldReclip(_Exterieur ancien) => ancien.rayon != rayon;
}

/// Logo Sprint (tuile de marbre noir, « S » blanc de verre et liseré vert),
/// avec une lueur verte discrète sur les écrans sombres.
class TuileLogo extends StatelessWidget {
  const TuileLogo({super.key, this.taille = 84});

  final double taille;

  @override
  Widget build(BuildContext context) => LogoSprint(taille: taille, ombre: true);
}

/// Habillage d'un onglet en charte Onyx & Vert : [ThemeOnyxVert] (flou des
/// cartes) et fond Onyx à halos verts. L'onglet garde son propre `Scaffold`
/// (transparent) et sa zone sûre.
class EcranOnyxVert extends StatelessWidget {
  const EcranOnyxVert({super.key, required this.child, this.flou = true});

  final Widget child;

  /// Voir [ThemeOnyxVert.flou].
  final bool flou;

  @override
  Widget build(BuildContext context) => ThemeOnyxVert(flou: flou, child: FondOnyxVert(child: child));
}

/// Habillage d'une sous-page ouverte par `Navigator.push` (Compte, Aide,
/// Support, reçus…) en charte Onyx & Vert : [EcranOnyxVert] + `Scaffold` et
/// `AppBar` transparents à texte clair. Une route poussée n'hérite pas du
/// fond de l'écran qui l'ouvre : chaque sous-page s'habille elle-même. Le
/// `Scaffold` de la page ne doit pas fixer son `backgroundColor`.
class SousPageOnyx extends StatelessWidget {
  const SousPageOnyx({super.key, required this.child, this.flou = true});

  final Widget child;

  /// Voir [ThemeOnyxVert.flou].
  final bool flou;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Style du titre dérivé du thème : il garde la police de la plateforme.
    final styleTitre = (theme.appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge ?? const TextStyle()).copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.3,
      color: AppColors.texte,
    );
    return EcranOnyxVert(
      flou: flou,
      child: Theme(
        data: theme.copyWith(
          scaffoldBackgroundColor: Colors.transparent,
          appBarTheme: AppBarTheme(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            foregroundColor: AppColors.texte,
            elevation: 0,
            scrolledUnderElevation: 0,
            titleTextStyle: styleTitre,
          ),
        ),
        child: child,
      ),
    );
  }
}

/// Titre d'un onglet (« Gains », « Compte »…) en charte Onyx & Vert.
const styleTitreEcran = TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: AppColors.texte);

/// Titre de section (« Dernières courses »…) en charte Onyx & Vert.
const styleTitreSection = TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: AppColors.texte);
