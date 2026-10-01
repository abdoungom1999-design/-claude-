import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Ce que le client peut se faire livrer : une carte illustrée et un libellé.
class ObjetLivrable {
  const ObjetLivrable({required this.libelle, required this.icone, this.image});

  final String libelle;

  /// Pictogramme élégant, affiché tant que [image] est absente.
  final IconData icone;

  /// Photo embarquée (`assets/livraison/…`). Absente ou illisible : fond
  /// clair et pictogramme, jamais d'image cassée.
  final String? image;
}

/// Services illustrés par défaut (voir `assets/livraison/LISEZ-MOI.txt`).
const livrablesParDefaut = <ObjetLivrable>[
  ObjetLivrable(
      libelle: 'Colis',
      icone: Icons.inventory_2_outlined,
      image: 'assets/livraison/colis.jpg'),
  ObjetLivrable(
      libelle: 'Repas',
      icone: Icons.lunch_dining_outlined,
      image: 'assets/livraison/repas.jpg'),
  ObjetLivrable(
      libelle: 'Courses',
      icone: Icons.shopping_bag_outlined,
      image: 'assets/livraison/courses.jpg'),
];

/// Carrousel horizontal de cartes illustrées (état vide de l'onglet
/// Livraison), aux bords très arrondis, avec un libellé dessous : montre
/// d'un coup d'œil tout ce qu'on peut se faire livrer. Illustratif (aucun
/// appui) ; le dernier élément dépasse un peu pour inviter à faire défiler.
class CarrouselLivrables extends StatelessWidget {
  const CarrouselLivrables({super.key, this.objets = livrablesParDefaut});

  final List<ObjetLivrable> objets;

  /// Le défilement déborde sur les marges de la carte qui le contient (16 px)
  /// pour que les cartes ne soient pas coupées net au bord du texte.
  static const debord = 16.0;

  static const largeurCarte = 128.0;
  static const hauteurCarte = 150.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, contraintes) {
        final largeur = contraintes.maxWidth + 2 * debord;
        return SizedBox(
          height: hauteurCarte + 30,
          child: OverflowBox(
            minWidth: largeur,
            maxWidth: largeur,
            child: SizedBox(
              width: largeur,
              height: hauteurCarte + 30,
              // Doigt, souris et pavé tactile : le carrousel se fait défiler
              // aussi à la souris sur ordinateur.
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                    PointerDeviceKind.stylus
                  },
                ),
                child: ListView.separated(
                  key: const ValueKey('carrousel-livrables'),
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: debord),
                  itemCount: objets.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) => _CarteLivrable(objet: objets[i]),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CarteLivrable extends StatelessWidget {
  const _CarteLivrable({required this.objet});

  final ObjetLivrable objet;

  @override
  Widget build(BuildContext context) {
    final repli = DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, AppColors.fondClair],
        ),
      ),
      child: Center(child: Icon(objet.icone, color: AppColors.onyx, size: 40)),
    );
    return SizedBox(
      width: CarrouselLivrables.largeurCarte,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: CarrouselLivrables.largeurCarte,
            height: CarrouselLivrables.hauteurCarte,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.bordVerre),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 14,
                    offset: Offset(0, 6))
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(21),
              child: objet.image == null
                  ? repli
                  : Image.asset(
                      objet.image!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => repli,
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              objet.libelle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onyx),
            ),
          ),
        ],
      ),
    );
  }
}
