import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// En-tête de la Tour de Contrôle : titre de la page et profil Admin.
/// En mode démo seulement : recherche globale et notifications
/// (visuelles, sans données réelles derrière).
class AdminTopbar extends StatelessWidget {
  const AdminTopbar({super.key, required this.titreSection, this.compteAdmin});

  final String titreSection;

  /// Email du compte Admin connecté ; `null` en mode démo.
  final String? compteAdmin;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: const BoxDecoration(
        color: AppColors.fondBarre,
        border: Border(bottom: BorderSide(color: AppColors.bordVerre)),
      ),
      child: Row(
        children: [
          Text(
            titreSection,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: AppColors.onyx),
          ),
          const SizedBox(width: 32),
          if (compteAdmin != null)
            const Spacer()
          else
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(21),
                    border: Border.all(color: AppColors.bordVerre),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.search, size: 19, color: AppColors.texteDiscret),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Rechercher une course, un chauffeur, un client…',
                          style: TextStyle(fontSize: 13, color: AppColors.texteDiscret),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (compteAdmin == null) ...[
            const SizedBox(width: 20),
            const _BoutonIcone(icon: Icons.notifications_outlined, badge: true),
          ],
          const SizedBox(width: 14),
          _ProfilAdmin(compte: compteAdmin),
        ],
      ),
    );
  }
}

class _BoutonIcone extends StatelessWidget {
  const _BoutonIcone({required this.icon, this.badge = false});

  final IconData icon;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.bordVerre),
          ),
          child: Icon(icon, size: 19, color: AppColors.onyx),
        ),
        if (badge)
          Positioned(
            top: -1,
            right: -1,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: AppColors.bleu,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

class _ProfilAdmin extends StatelessWidget {
  const _ProfilAdmin({this.compte});

  final String? compte;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.onyx,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.bleu, width: 2),
          ),
          alignment: Alignment.center,
          child: const Text(
            'GS',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Admin Santine',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.onyx),
            ),
            Text(
              compte ?? 'Super administrateur',
              style: const TextStyle(fontSize: 11, color: AppColors.texteDiscret),
            ),
          ],
        ),
      ],
    );
  }
}
