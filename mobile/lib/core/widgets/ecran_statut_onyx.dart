import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'onyx_vert.dart';

/// Écran d'état plein page (dossier en examen, e-mail à vérifier, compte
/// suspendu…) en charte « Onyx & Vert » : fond Onyx à halos verts, repère de
/// marque, carte « verre » centrale (médaillon, titre, texte) et actions
/// en bas. Sans navigation : ces écrans ne servent qu'à informer.
///
/// Le contenu défile si l'écran est trop court (petit téléphone, clavier).
class EcranStatutOnyx extends StatelessWidget {
  const EcranStatutOnyx({
    super.key,
    required this.icone,
    required this.titre,
    required this.texte,
    this.couleurAlerte,
    this.contenu = const [],
    this.actions = const [],
    this.haloLogo = false,
  });

  final IconData icone;
  final String titre;
  final String texte;

  /// Couleur d'alerte du médaillon (rouge pour un compte désactivé).
  /// `null` : médaillon vert (contour, lueur et icône), la couleur de la charte.
  final Color? couleurAlerte;

  /// Éléments sous le texte, dans la carte (pastille, étapes, indicateur).
  final List<Widget> contenu;

  /// Boutons sous la carte (principal, secondaire, lien discret).
  final List<Widget> actions;

  /// Halo lumineux qui pulse autour du logo (écran de célébration). Éteint
  /// par défaut : les autres écrans de statut ne changent pas.
  final bool haloLogo;

  @override
  Widget build(BuildContext context) {
    return EcranOnyxVert(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: haloLogo ? const HaloLogoSprint() : const TuileLogo(taille: 56)),
                    const SizedBox(height: 28),
                    CarteVerre(
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _Medaillon(icone: icone, couleurAlerte: couleurAlerte),
                          const SizedBox(height: 24),
                          Text(
                            titre,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              color: AppColors.texte,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            texte,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 14, color: AppColors.texteDiscret, height: 1.6),
                          ),
                          for (final element in contenu) ...[const SizedBox(height: 20), element],
                        ],
                      ),
                    ),
                    if (actions.isNotEmpty) const SizedBox(height: 24),
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      actions[i],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Logo Sprint entouré d'un halo vert et doré qui pulse doucement (célébration
/// de l'activation du compte). Sans mouvement si l'appareil demande de réduire
/// les animations.
class HaloLogoSprint extends StatefulWidget {
  const HaloLogoSprint({super.key, this.taille = 56});

  final double taille;

  @override
  State<HaloLogoSprint> createState() => _HaloLogoSprintState();
}

class _HaloLogoSprintState extends State<HaloLogoSprint> with SingleTickerProviderStateMixin {
  late final AnimationController _pulsation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _pulsation.stop();
      _pulsation.value = 0.6;
    } else if (!_pulsation.isAnimating) {
      _pulsation.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulsation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulsation,
      builder: (context, enfant) {
        final v = Curves.easeInOut.transform(_pulsation.value);
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.taille * 0.3),
            boxShadow: [
              BoxShadow(color: AppColors.vert.withValues(alpha: 0.35 + 0.35 * v), blurRadius: 22 + 26 * v, spreadRadius: 2 + 6 * v),
              BoxShadow(color: AppColors.etoile.withValues(alpha: 0.18 + 0.28 * v), blurRadius: 40 + 30 * v, spreadRadius: 4 * v),
            ],
          ),
          child: enfant,
        );
      },
      child: TuileLogo(taille: widget.taille),
    );
  }
}

class _Medaillon extends StatelessWidget {
  const _Medaillon({required this.icone, this.couleurAlerte});

  final IconData icone;
  final Color? couleurAlerte;

  @override
  Widget build(BuildContext context) {
    final alerte = couleurAlerte;
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        color: alerte == null ? AppColors.vertTeinte : alerte.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: (alerte ?? AppColors.vert).withValues(alpha: alerte == null ? 0.7 : 0.4), width: 1.4),
        boxShadow: alerte == null
            ? [BoxShadow(color: AppColors.vert.withValues(alpha: 0.28), blurRadius: 28, offset: const Offset(0, 8))]
            : null,
      ),
      alignment: Alignment.center,
      child: Icon(icone, size: 40, color: alerte ?? AppColors.vert),
    );
  }
}

/// Action principale d'un écran d'état : vert plein, texte Onyx (appel à l'action).
class BoutonStatutPrincipal extends StatelessWidget {
  const BoutonStatutPrincipal({
    super.key,
    required this.label,
    required this.onPressed,
    this.enCours = false,
    this.icone,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool enCours;
  final IconData? icone;

  @override
  Widget build(BuildContext context) {
    final actif = onPressed != null && !enCours;
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: actif ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.vert,
          foregroundColor: AppColors.onyx,
          disabledBackgroundColor: AppColors.texte.withValues(alpha: 0.08),
          disabledForegroundColor: AppColors.texte.withValues(alpha: 0.35),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        child: enCours
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.onyx),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icone != null) ...[Icon(icone, size: 20), const SizedBox(width: 8)],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Action secondaire : verre sombre à bord fin, texte clair.
class BoutonStatutSecondaire extends StatelessWidget {
  const BoutonStatutSecondaire({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.verre,
          foregroundColor: AppColors.texte,
          disabledForegroundColor: AppColors.texte.withValues(alpha: 0.35),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: AppColors.bordVerre),
          ),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
      ),
    );
  }
}

/// Lien discret sous les boutons (« Se déconnecter »).
class LienStatut extends StatelessWidget {
  const LienStatut({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: Text(
        label,
        style: const TextStyle(color: AppColors.texteDiscret, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Pastille d'état (« Vérification en cours »).
class PastilleStatut extends StatelessWidget {
  const PastilleStatut({super.key, required this.icone, required this.label});

  final IconData icone;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.vert.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 16, color: AppColors.vert),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.texte),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Les trois étapes d'un dossier chauffeur : reçu, vérification, activation.
/// [etapeCourante] : 0 = reçu, 1 = vérification en cours, 2 = compte activé
/// en cours, 3 = les trois étapes sont terminées. [eclat] : la barre et les
/// pastilles terminées s'illuminent en vert éclatant (célébration de
/// l'activation) ; `false` par défaut, l'écran reste celui d'avant.
class EtapesDossier extends StatelessWidget {
  const EtapesDossier({super.key, this.etapeCourante = 1, this.eclat = false});

  final int etapeCourante;
  final bool eclat;

  static const _etapes = ['Dossier reçu', 'Vérification', 'Compte activé'];

  @override
  Widget build(BuildContext context) {
    if (!eclat) return _construire(1);
    final sansAnimation = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: sansAnimation ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, intensite, _) => _construire(intensite),
    );
  }

  /// [intensite] de 0 (éteint) à 1 (éclat complet) ; sans [eclat], toujours 1
  /// et aucun éclat n'est dessiné.
  Widget _construire(double intensite) {
    const vertEclatant = Color(0xFF7DFFB3);
    final couleurVive = eclat ? Color.lerp(AppColors.vert, vertEclatant, 0.7 * intensite)! : AppColors.vert;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _etapes.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 13),
                child: Container(
                  height: eclat && i <= etapeCourante ? 2 + 1.5 * intensite : 2,
                  decoration: BoxDecoration(
                    color: i <= etapeCourante ? couleurVive : AppColors.texte.withValues(alpha: 0.12),
                    boxShadow: eclat && i <= etapeCourante
                        ? [BoxShadow(color: AppColors.vert.withValues(alpha: 0.7 * intensite), blurRadius: 10 * intensite)]
                        : null,
                  ),
                ),
              ),
            ),
          _Etape(
            label: _etapes[i],
            etat: i < etapeCourante ? 2 : (i == etapeCourante ? 1 : 0),
            couleur: couleurVive,
            eclat: eclat ? intensite : null,
          ),
        ],
      ],
    );
  }
}

/// [etat] : 0 à venir, 1 en cours, 2 terminée.
class _Etape extends StatelessWidget {
  const _Etape({required this.label, required this.etat, this.couleur = AppColors.vert, this.eclat});

  final String label;
  final int etat;
  final Color couleur;

  /// Intensité de l'éclat (0 à 1) d'une pastille terminée ; `null` : pas d'éclat.
  final double? eclat;

  @override
  Widget build(BuildContext context) {
    final terminee = etat == 2;
    final enCours = etat == 1;
    return SizedBox(
      width: 72,
      child: Column(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: terminee || enCours ? couleur : Colors.transparent,
              border: Border.all(
                color: terminee || enCours ? Colors.transparent : AppColors.texte.withValues(alpha: 0.18),
              ),
              boxShadow: terminee && eclat != null
                  ? [BoxShadow(color: AppColors.vert.withValues(alpha: 0.75 * eclat!), blurRadius: 14 * eclat!, spreadRadius: 2 * eclat!)]
                  : null,
            ),
            alignment: Alignment.center,
            child: terminee
                ? const Icon(Icons.check_rounded, size: 16, color: AppColors.onyx)
                : (enCours ? const Icon(Icons.hourglass_top_rounded, size: 15, color: AppColors.onyx) : null),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.25,
              fontWeight: enCours ? FontWeight.w800 : FontWeight.w600,
              color: etat == 0 ? AppColors.texteDiscret : AppColors.texte,
            ),
          ),
        ],
      ),
    );
  }
}
