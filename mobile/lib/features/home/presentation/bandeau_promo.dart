import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Ce que fait l'appui sur une bannière.
enum ActionBanniere { aucune, course, colis }

/// Une bannière du carrousel promo de l'Accueil.
class BanniereProm {
  const BanniereProm({
    required this.titre,
    required this.sousTitre,
    this.image,
    this.icone = Icons.two_wheeler_rounded,
    this.action = ActionBanniere.aucune,
  });

  final String titre;
  final String sousTitre;

  /// Photo embarquée (`assets/promo/…`). Absente ou illisible : fond Onyx.
  final String? image;

  /// Pictogramme discret du fond Onyx (sans photo).
  final IconData icone;
  final ActionBanniere action;
}

/// Bannières affichées par défaut. Pour changer un texte, une photo ou
/// l'action d'une bannière, modifier cette liste (voir `assets/promo/LISEZ-MOI.txt`).
const banniereParDefaut = <BanniereProm>[
  BanniereProm(
    titre: 'Vos colis livrés en sécurité',
    sousTitre: 'Livraison express partout à Dakar',
    image: 'assets/promo/colis.jpg',
    icone: Icons.inventory_2_outlined,
    action: ActionBanniere.colis,
  ),
  BanniereProm(
    titre: 'Une moto en quelques minutes',
    sousTitre: 'Le prix de la course est annoncé avant de commander',
    image: 'assets/promo/course.jpg',
    icone: Icons.two_wheeler_rounded,
    action: ActionBanniere.course,
  ),
  BanniereProm(
    titre: 'Suivez votre chauffeur en direct',
    sousTitre: 'Sa position et sa messagerie pendant toute la course',
    image: 'assets/promo/suivi.jpg',
    icone: Icons.my_location_rounded,
  ),
];

/// Carrousel de bannières : bords très arrondis, défilement automatique
/// (interrompu dès que le client touche le carrousel), pastilles de
/// position. N'avance pas quand l'onglet est masqué ni quand le système
/// demande de réduire les animations.
class BandeauPromo extends StatefulWidget {
  const BandeauPromo({
    super.key,
    this.bannieres = banniereParDefaut,
    this.surAction,
    this.intervalle = const Duration(seconds: 5),
    this.hauteur = 112,
  });

  final List<BanniereProm> bannieres;
  final ValueChanged<ActionBanniere>? surAction;
  final Duration intervalle;
  final double hauteur;

  @override
  State<BandeauPromo> createState() => _BandeauPromoState();
}

class _BandeauPromoState extends State<BandeauPromo> {
  final _pages = PageController(viewportFraction: 1);
  Timer? _minuteur;
  int _courante = 0;

  @override
  void initState() {
    super.initState();
    _armer();
  }

  void _armer() {
    _minuteur?.cancel();
    if (widget.bannieres.length < 2) return;
    _minuteur = Timer.periodic(widget.intervalle, (_) {
      if (!mounted || !_pages.hasClients) return;
      if (!TickerMode.valuesOf(context).enabled || MediaQuery.disableAnimationsOf(context)) return;
      final suivante = (_courante + 1) % widget.bannieres.length;
      _pages.animateToPage(suivante, duration: const Duration(milliseconds: 500), curve: Curves.easeInOutCubic);
    });
  }

  @override
  void dispose() {
    _minuteur?.cancel();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.bannieres.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: widget.hauteur,
          // Un geste du client relance le compte à rebours : pas de
          // changement de bannière pendant qu'il la regarde.
          child: Listener(
            onPointerDown: (_) => _minuteur?.cancel(),
            onPointerUp: (_) => _armer(),
            onPointerCancel: (_) => _armer(),
            child: PageView.builder(
              key: const ValueKey('carrousel-promo'),
              controller: _pages,
              itemCount: widget.bannieres.length,
              onPageChanged: (i) => setState(() => _courante = i),
              itemBuilder: (context, i) => _Banniere(
                banniere: widget.bannieres[i],
                onTap: () => widget.surAction?.call(widget.bannieres[i].action),
              ),
            ),
          ),
        ),
        if (widget.bannieres.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            key: const ValueKey('pastilles-promo'),
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.bannieres.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _courante ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _courante ? AppColors.onyx : AppColors.onyx.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Banniere extends StatelessWidget {
  const _Banniere({required this.banniere, required this.onTap});

  final BanniereProm banniere;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: banniere.action != ActionBanniere.aucune,
      label: '${banniere.titre}. ${banniere.sousTitre}',
      child: GestureDetector(
        onTap: banniere.action == ActionBanniere.aucune ? null : onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _FondOnyx(icone: banniere.icone),
              if (banniere.image case final chemin?)
                Image.asset(
                  chemin,
                  fit: BoxFit.cover,
                  // Photo absente : le fond Onyx reste visible, jamais d'image cassée.
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              // Voile sombre : lisibilité du texte sur n'importe quelle photo.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Color(0xCC0B0B0C), Color(0x330B0B0C)],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 14, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            banniere.titre,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            banniere.sousTitre,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 12, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                    if (banniere.action != ActionBanniere.aucune) ...[
                      const SizedBox(width: 10),
                      Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(color: AppColors.orange, shape: BoxShape.circle),
                        child: const Icon(Icons.arrow_outward_rounded, color: Colors.white, size: 18),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fond de bannière sans photo : Onyx, halo orange discret, pictogramme
/// très pâle.
class _FondOnyx extends StatelessWidget {
  const _FondOnyx({required this.icone});

  final IconData icone;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.onyxClair, AppColors.onyx],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -60,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [AppColors.orange.withValues(alpha: 0.32), AppColors.orange.withValues(alpha: 0)]),
              ),
            ),
          ),
          Positioned(
            right: 14,
            bottom: -14,
            child: Icon(icone, size: 96, color: Colors.white.withValues(alpha: 0.07)),
          ),
        ],
      ),
    );
  }
}
