import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Ce que le client peut se faire livrer : un cercle et un libellé.
class ObjetLivrable {
  const ObjetLivrable({required this.libelle, required this.icone, this.image});

  final String libelle;

  /// Icône temporaire, affichée tant que [image] est absente.
  final IconData icone;

  /// Image embarquée (`assets/livraison/…`), rognée en cercle. Absente ou
  /// illisible : l'icône prend le relais.
  final String? image;
}

/// Objets illustrés par défaut (voir `assets/livraison/LISEZ-MOI.txt`).
const livrablesParDefaut = <ObjetLivrable>[
  ObjetLivrable(libelle: 'Colis', icone: Icons.inventory_2_outlined, image: 'assets/livraison/colis.png'),
  ObjetLivrable(libelle: 'Repas', icone: Icons.lunch_dining_outlined, image: 'assets/livraison/repas.png'),
  ObjetLivrable(libelle: 'Courses', icone: Icons.shopping_bag_outlined, image: 'assets/livraison/courses.png'),
  ObjetLivrable(libelle: 'Cadeaux', icone: Icons.card_giftcard_outlined, image: 'assets/livraison/cadeaux.png'),
];

/// Rangée de petits cercles illustrés (état vide de l'onglet Livraison) :
/// montre d'un coup d'œil tout ce qu'on peut se faire livrer. Purement
/// illustrative (aucun appui).
class RangeeLivrables extends StatelessWidget {
  const RangeeLivrables({super.key, this.objets = livrablesParDefaut});

  final List<ObjetLivrable> objets;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('rangee-livrables'),
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [for (final objet in objets) _Cercle(objet: objet)],
    );
  }
}

class _Cercle extends StatelessWidget {
  const _Cercle({required this.objet});

  final ObjetLivrable objet;

  @override
  Widget build(BuildContext context) {
    final icone = Icon(objet.icone, color: AppColors.onyx, size: 26);
    return SizedBox(
      width: 68,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: AppColors.bordVerre),
              boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 10, offset: Offset(0, 4))],
            ),
            child: ClipOval(
              child: objet.image == null
                  ? Center(child: icone)
                  : Image.asset(
                      objet.image!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Center(child: icone),
                    ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            objet.libelle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.onyx),
          ),
        ],
      ),
    );
  }
}
