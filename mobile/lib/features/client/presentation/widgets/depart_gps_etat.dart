import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// Où en est le départ de l'écran de commande (voir [DepartGps]).
enum EtatDepartGps {
  /// La position GPS du client est en cours de recherche.
  recherche,

  /// Le départ est la position GPS du client : « Ma position actuelle ».
  actif,

  /// Position introuvable : GPS coupé, autorisation refusée ou délai dépassé.
  indisponible,

  /// Le client a choisi ou saisi lui-même son adresse de départ.
  manuel,
}

/// Ligne sous le champ de départ : dit au client d'où le chauffeur viendra le
/// chercher, et lui laisse reprendre sa position GPS quand il a changé le
/// départ ou que la localisation a échoué.
class DepartGpsEtat extends StatelessWidget {
  const DepartGpsEtat({
    super.key,
    required this.etat,
    required this.onUtiliserMaPosition,
    this.messageActif = messageActifPassager,
  });

  /// Message du départ pris sur le GPS, pour une course moto.
  static const messageActifPassager = 'Votre chauffeur viendra vous chercher à votre position GPS exacte.';

  /// Message du départ pris sur le GPS, pour un colis : le colis n'est pas
  /// forcément là où se trouve le client.
  static const messageActifColis =
      'Le chauffeur récupérera le colis à votre position GPS exacte. Modifiez l\'adresse si le colis est ailleurs.';

  final EtatDepartGps etat;
  final VoidCallback onUtiliserMaPosition;

  /// Ce que le client lit quand le départ est sa position GPS.
  final String messageActif;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      alignment: Alignment.topCenter,
      child: switch (etat) {
        EtatDepartGps.recherche => const _Ligne(
            chargement: true,
            texte: 'Recherche de votre position GPS…',
          ),
        EtatDepartGps.actif => _Ligne(
            icone: Icons.check_circle_rounded,
            couleur: AppColors.vert,
            texte: messageActif,
          ),
        EtatDepartGps.indisponible => _Ligne(
            icone: Icons.location_off_outlined,
            texte: 'Position GPS introuvable. Autorisez la localisation ou saisissez votre adresse de départ.',
            action: _Action(libelle: 'Réessayer', onPressed: onUtiliserMaPosition),
          ),
        EtatDepartGps.manuel => _Ligne(
            action: _Action(
              libelle: 'Utiliser ma position actuelle',
              icone: Icons.my_location,
              onPressed: onUtiliserMaPosition,
            ),
          ),
      },
    );
  }
}

class _Action {
  const _Action({required this.libelle, required this.onPressed, this.icone});

  final String libelle;
  final IconData? icone;
  final VoidCallback onPressed;
}

class _Ligne extends StatelessWidget {
  const _Ligne({this.texte, this.icone, this.couleur = AppColors.texteDiscret, this.chargement = false, this.action});

  final String? texte;
  final IconData? icone;
  final Color couleur;
  final bool chargement;
  final _Action? action;

  @override
  Widget build(BuildContext context) {
    final texte = this.texte;
    final action = this.action;
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      // Le texte puis, dessous, l'action : rien ne déborde sur un petit écran
      // ou avec un texte agrandi.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (texte != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: chargement
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.vert),
                        )
                      : Icon(icone, size: 16, color: couleur),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    texte,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.texteDiscret, height: 1.35),
                  ),
                ),
              ],
            ),
          if (action != null) _BoutonAction(action: action),
        ],
      ),
    );
  }
}

class _BoutonAction extends StatelessWidget {
  const _BoutonAction({required this.action});

  final _Action action;

  @override
  Widget build(BuildContext context) {
    final style = TextButton.styleFrom(
      foregroundColor: AppColors.vert,
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
    );
    final icone = action.icone;
    if (icone == null) {
      return TextButton(onPressed: action.onPressed, style: style, child: Text(action.libelle));
    }
    return TextButton.icon(
      onPressed: action.onPressed,
      style: style,
      icon: Icon(icone, size: 16),
      label: Text(action.libelle),
    );
  }
}
