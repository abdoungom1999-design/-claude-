import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../courses/data/course_service.dart';

/// Bandeau de la course en cours du chauffeur, affiché au-dessus de la
/// barre de navigation tant qu'une course lui est attribuée : un bouton
/// qui fait avancer la course ("Client à bord" (`acceptee` ->
/// `en_cours`), puis "Terminer la course" (`en_cours` -> `terminee`)),
/// "Naviguer" (Google Maps ou Waze vers le client, puis vers la
/// destination), et, comme côté client, "Appeler" et "Message" (badge
/// tant qu'un message du client n'a pas été lu). "Annuler la course" en
/// dernier recours (client introuvable, panne).
class CourseActiveBandeau extends StatelessWidget {
  const CourseActiveBandeau({
    super.key,
    required this.course,
    required this.enCours,
    required this.onAvancer,
    required this.onAppeler,
    required this.onMessage,
    required this.onNaviguer,
    required this.onAnnuler,
    this.messageNonLu = false,
  });

  final CourseFirestore course;

  /// Mise à jour Firestore en cours : bouton désactivé.
  final bool enCours;
  final VoidCallback onAvancer;
  final VoidCallback onAppeler;
  final VoidCallback onMessage;
  final VoidCallback onNaviguer;
  final VoidCallback onAnnuler;
  final bool messageNonLu;

  bool get _clientABord => course.statut == StatutCourse.enCours;

  @override
  Widget build(BuildContext context) {
    final colis = course.type == 'COLIS';
    // Onyx & Light : carte blanche, texte Onyx, action principale orange.
    return Material(
      color: AppColors.fondBarre,
      elevation: 8,
      shadowColor: const Color(0x33000000),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(color: AppColors.bleuClair, borderRadius: BorderRadius.circular(14)),
                    child: Icon(
                      colis ? Icons.inventory_2_outlined : Icons.two_wheeler_rounded,
                      color: AppColors.bleu,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _clientABord
                              ? (colis ? 'Livraison en cours' : 'Course en cours')
                              : (colis ? 'Récupérez le colis' : 'Rejoignez votre client'),
                          style: const TextStyle(color: AppColors.bleu, fontWeight: FontWeight.w800, fontSize: 13.5),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _clientABord ? 'Vers ${course.adresseArrivee}' : 'Départ : ${course.adresseDepart}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.onyx, fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                        // Rappel : la course est déjà réglée dans l'app.
                        Text(
                          course.libellePaiement,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.texteDiscret, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: enCours ? null : onAvancer,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.orange,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.orangeLight,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: enCours
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            _clientABord ? 'Terminer la course' : (colis ? 'Colis récupéré' : 'Client à bord'),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _BoutonContact(
                      icone: Icons.navigation_rounded,
                      libelle: 'Naviguer',
                      onPressed: onNaviguer,
                      plein: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _BoutonContact(icone: Icons.call_rounded, libelle: 'Appeler', onPressed: onAppeler),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _BoutonContact(
                      icone: Icons.chat_bubble_outline_rounded,
                      libelle: 'Message',
                      onPressed: onMessage,
                      badge: messageNonLu,
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: enCours ? null : onAnnuler,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text(
                    'Annuler la course',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.texteDiscret,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BoutonContact extends StatelessWidget {
  const _BoutonContact({
    required this.icone,
    required this.libelle,
    required this.onPressed,
    this.badge = false,
    this.plein = false,
  });

  final IconData icone;
  final String libelle;
  final VoidCallback onPressed;
  final bool badge;

  /// Bouton principal (fond blanc) : "Naviguer".
  final bool plein;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: plein ? Colors.white : AppColors.onyx,
        backgroundColor: plein ? AppColors.onyx : (badge ? AppColors.bleuClair : null),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        side: BorderSide(color: plein ? AppColors.onyx : const Color(0x26000000)),
        minimumSize: const Size.fromHeight(40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Badge(
            isLabelVisible: badge,
            smallSize: 9,
            backgroundColor: AppColors.orange,
            child: Icon(icone, size: 18),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              libelle,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
