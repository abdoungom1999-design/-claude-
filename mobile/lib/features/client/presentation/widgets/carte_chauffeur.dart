import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../evaluations/data/evaluation_service.dart';
import '../../../evaluations/presentation/evaluation_course.dart';

/// Identité du chauffeur assigné, affichée au client dès que la course est
/// acceptée : nom complet, note, véhicule (modèle) et plaque
/// d'immatriculation, pour reconnaître la bonne moto.
///
/// [profil] est le profil public du chauffeur (`profils_publics`) :
/// `nom`, `vehiculeId` (marque, modèle, année), `plaqueImmatriculation`,
/// `noteSomme` / `noteNombre`. `null` sans [erreur] : chargement en cours.
/// Une information manquante est dite comme telle, jamais inventée.
class CarteChauffeur extends StatelessWidget {
  const CarteChauffeur({
    super.key,
    required this.profil,
    required this.clientABord,
    this.erreur = false,
    this.onReessayer,
  });

  final Map<String, dynamic>? profil;

  /// Course en cours (client à bord), sinon le chauffeur est en approche.
  final bool clientABord;

  /// Le profil n'a pas pu être lu.
  final bool erreur;
  final VoidCallback? onReessayer;

  static String? _texte(Map<String, dynamic>? profil, String cle) {
    final valeur = (profil?[cle] as String?)?.trim();
    return valeur == null || valeur.isEmpty ? null : valeur;
  }

  /// "Moussa Diop" -> "MD".
  static String initiales(String nom) {
    final mots = nom.split(RegExp(r'\s+')).where((m) => m.isNotEmpty).toList();
    if (mots.isEmpty) return '?';
    final premiere = mots.first[0];
    return (mots.length > 1 ? premiere + mots.last[0] : premiere).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.greyBorder),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Etat(clientABord: clientABord),
          const SizedBox(height: 14),
          if (erreur)
            _Erreur(onReessayer: onReessayer)
          else if (profil == null)
            const _Chargement()
          else
            _Identite(profil: profil!),
        ],
      ),
    );
  }
}

class _Etat extends StatelessWidget {
  const _Etat({required this.clientABord});

  final bool clientABord;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: const BoxDecoration(color: AppColors.vert, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            clientABord ? 'Course en cours' : 'Chauffeur trouvé · il arrive',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.vert),
          ),
        ),
      ],
    );
  }
}

class _Identite extends StatelessWidget {
  const _Identite({required this.profil});

  final Map<String, dynamic> profil;

  @override
  Widget build(BuildContext context) {
    final nom = CarteChauffeur._texte(profil, 'nom') ?? 'Chauffeur Sprint';
    final vehicule = CarteChauffeur._texte(profil, 'vehiculeId');
    final plaque = CarteChauffeur._texte(profil, 'plaqueImmatriculation');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.orange, AppColors.orangeDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                CarteChauffeur.initiales(nom),
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nom,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.15),
                  ),
                  const SizedBox(height: 5),
                  // Réductible : jamais de débordement, même en grande police.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: BadgeNoteChauffeur(note: NoteChauffeur.depuisProfil(profil)),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Divider(height: 1, color: AppColors.greyBorder),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, contraintes) {
            // Écran très étroit : la plaque passe sous le véhicule.
            final etroit = contraintes.maxWidth < 300;
            final vehiculeEtPlaque = [
              Expanded(child: _Vehicule(vehicule: vehicule)),
              if (!etroit) ...[const SizedBox(width: 10), _Plaque(plaque: plaque)],
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: AppColors.orangeLight, borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.two_wheeler_rounded, color: AppColors.orange, size: 22),
                    ),
                    const SizedBox(width: 12),
                    ...vehiculeEtPlaque,
                  ],
                ),
                if (etroit) ...[
                  const SizedBox(height: 12),
                  _Plaque(plaque: plaque),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Vehicule extends StatelessWidget {
  const _Vehicule({required this.vehicule});

  final String? vehicule;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Véhicule', style: TextStyle(fontSize: 11.5, color: AppColors.grey, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(
          vehicule ?? 'Non renseigné',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: vehicule == null ? AppColors.grey : AppColors.text,
          ),
        ),
      ],
    );
  }
}

/// Plaque d'immatriculation : la première chose que le client vérifie
/// quand la moto arrive.
class _Plaque extends StatelessWidget {
  const _Plaque({required this.plaque});

  final String? plaque;

  @override
  Widget build(BuildContext context) {
    if (plaque == null) {
      return const Text('Plaque non renseignée', style: TextStyle(fontSize: 12, color: AppColors.grey));
    }
    return Semantics(
      label: 'Plaque $plaque',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.text, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          plaque!,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: 1),
        ),
      ),
    );
  }
}

class _Chargement extends StatelessWidget {
  const _Chargement();

  Widget _barre(double largeur, double hauteur) => Container(
        width: largeur,
        height: hauteur,
        decoration: BoxDecoration(color: AppColors.greyLight, borderRadius: BorderRadius.circular(6)),
      );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Chargement des informations du chauffeur',
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: const BoxDecoration(color: AppColors.greyLight, shape: BoxShape.circle),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [_barre(160, 18), const SizedBox(height: 10), _barre(110, 12), const SizedBox(height: 10), _barre(190, 12)],
          ),
        ],
      ),
    );
  }
}

class _Erreur extends StatelessWidget {
  const _Erreur({required this.onReessayer});

  final VoidCallback? onReessayer;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.info_outline_rounded, color: AppColors.grey),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            "Les informations de votre chauffeur n'ont pas pu être chargées.",
            style: TextStyle(fontSize: 13.5, height: 1.35),
          ),
        ),
        if (onReessayer != null) TextButton(onPressed: onReessayer, child: const Text('Réessayer')),
      ],
    );
  }
}
