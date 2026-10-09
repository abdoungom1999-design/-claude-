import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/bouton_rond_verre.dart';

/// Initiale, en majuscule, du prénom : premier mot du nom complet saisi à
/// l'inscription (« Prénom Nom »). `null` si le nom est absent, vide ou ne
/// commence pas par une lettre (numéro de téléphone, symbole…) : l'avatar
/// affiche alors l'icône de profil.
String? initialeDuPrenom(String? nomComplet) {
  final prenom = (nomComplet ?? '').trim().split(RegExp(r'\s+')).first;
  if (prenom.isEmpty) return null;
  final premiere = String.fromCharCode(prenom.runes.first);
  if (!RegExp(r'\p{L}', unicode: true).hasMatch(premiere)) return null;
  // Une seule lettre, même si la majuscule s'écrit sur deux (« ß » devient « SS »).
  return String.fromCharCode(premiere.toUpperCase().runes.first);
}

/// En-tête de l'accueil client : à gauche la marque « Sprint » et son
/// slogan discret dessous ; à droite la cloche des notifications et l'avatar
/// du client (initiale de son prénom, icône de profil à défaut). Posé sur la
/// carte : le texte est lisible grâce au voile et à l'ombre légère.
class EnteteAccueil extends StatelessWidget {
  const EnteteAccueil({
    super.key,
    required this.profil,
    required this.onNotifications,
    required this.onCompte,
    this.nomRepli,
  });

  /// Slogan sous le nom de marque : court (une ligne), un seul endroit à
  /// changer.
  static const slogan = 'Vite arrivé, bien arrivé';

  /// Flux du profil du client (`users/{uid}`) : seul le champ `nom` sert ici.
  final Stream<Map<String, dynamic>?> profil;
  final VoidCallback onNotifications;
  final VoidCallback onCompte;

  /// Nom affiché tant que le profil n'a pas de nom : celui de la démo quand
  /// l'app n'est pas reliée à Firebase. `null` avec un vrai compte : l'avatar
  /// montre alors l'icône de profil, jamais le nom d'un autre.
  final String? nomRepli;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          const Expanded(child: _Marque()),
          const SizedBox(width: 12),
          BoutonRondVerre(icon: Icons.notifications_outlined, tooltip: 'Notifications', onTap: onNotifications),
          const SizedBox(width: 10),
          StreamBuilder<Map<String, dynamic>?>(
            stream: profil,
            builder: (context, instantane) {
              final brut = instantane.data?['nom'];
              final nom = brut is String ? brut.trim() : '';
              return AvatarProfil(initiale: initialeDuPrenom(nom.isNotEmpty ? nom : nomRepli), onTap: onCompte);
            },
          ),
        ],
      ),
    );
  }
}

class _Marque extends StatelessWidget {
  const _Marque();

  @override
  Widget build(BuildContext context) {
    // Ombre légère : le texte reste lisible sur une carte claire ou chargée.
    const ombre = [Shadow(color: AppColors.shadow, blurRadius: 8)];
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Sprint',
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 26,
            height: 1.05,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            color: AppColors.texte,
            shadows: ombre,
          ),
        ),
        SizedBox(height: 2),
        Text(
          EnteteAccueil.slogan,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.2,
            fontWeight: FontWeight.w500,
            color: AppColors.texteDiscret,
            shadows: ombre,
          ),
        ),
      ],
    );
  }
}

/// Avatar rond du client : initiale de son prénom en clair sur Onyx, cerclé
/// de vert (le vert marque ce qui est actif, comme sur l'écran Compte), avec
/// une lueur verte discrète. Sans initiale, l'icône de profil prend sa place.
class AvatarProfil extends StatelessWidget {
  const AvatarProfil({super.key, required this.initiale, required this.onTap});

  /// Une lettre majuscule, ou `null` pour l'icône de profil.
  final String? initiale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lettre = initiale;
    return Tooltip(
      message: 'Mon compte',
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            const BoxShadow(color: AppColors.shadow, blurRadius: 20, offset: Offset(0, 8)),
            BoxShadow(color: AppColors.vert.withValues(alpha: 0.28), blurRadius: 14),
          ],
        ),
        child: Material(
          color: AppColors.fond,
          shape: const CircleBorder(side: BorderSide(color: AppColors.vert, width: 2)),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: BoutonRondVerre.diametre,
              height: BoutonRondVerre.diametre,
              child: Center(
                // Fondu court : pas de saut d'image quand le nom arrive après la première image.
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: lettre == null
                      ? const Icon(Icons.person_rounded, key: ValueKey('profil-par-defaut'), size: 22, color: AppColors.texte)
                      : ExcludeSemantics(
                          child: Text(
                            lettre,
                            key: ValueKey('initiale-$lettre'),
                            style: const TextStyle(fontSize: 18, height: 1, fontWeight: FontWeight.w800, color: AppColors.texte),
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
