import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'notifications_push.dart';

/// Carte « Notifications » : dit où en sont les alertes de cet appareil et
/// propose de les activer.
///
/// Le site ne peut demander l'autorisation qu'à l'appui sur un bouton (règle
/// des navigateurs, encore plus stricte sur iPhone) : d'où ce bouton. En
/// [enBandeau], la carte ne s'affiche que quand il y a quelque chose à
/// faire (activer, ou installer le site sur l'iPhone) ; sinon elle est
/// invisible, pour ne pas encombrer l'écran une fois tout en place.
class CarteNotifications extends StatelessWidget {
  const CarteNotifications({super.key, this.push, this.enBandeau = false, this.raison});

  /// Injectable pour les tests ; par défaut, celui de l'application.
  final NotificationsPush? push;
  final bool enBandeau;

  /// Ce que les notifications apportent ici (« dès qu'un chauffeur accepte »...).
  final String? raison;

  @override
  Widget build(BuildContext context) {
    final service = push ?? NotificationsPush.instance;
    return ValueListenableBuilder<EtatNotifications>(
      valueListenable: service.etat,
      builder: (context, etat, _) {
        final estWeb = service.plateforme == PlateformePush.web;
        final contenu = _contenu(etat, estWeb);
        if (contenu == null || (enBandeau && !contenu.action)) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.only(bottom: enBandeau ? 12 : 0),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: contenu.action ? AppColors.vertTeinte : AppColors.carteHaute,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: contenu.action ? AppColors.vert.withValues(alpha: 0.45) : AppColors.bordVerre),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(contenu.icone, color: contenu.couleur, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(contenu.titre, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.texte)),
                      const SizedBox(height: 3),
                      Text(contenu.texte, style: const TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.texteDiscret)),
                      if (etat == EtatNotifications.aActiver) ...[
                        const SizedBox(height: 10),
                        FilledButton(
                          onPressed: service.demander,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.vert,
                            foregroundColor: AppColors.onyx,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Activer les notifications'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  ({IconData icone, Color couleur, String titre, String texte, bool action})? _contenu(EtatNotifications etat, bool estWeb) {
    final apport = raison ?? 'les messages et les courses, même quand Sprint est fermé';
    switch (etat) {
      case EtatNotifications.inconnu:
        return null;
      case EtatNotifications.aActiver:
        return (
          icone: Icons.notifications_active_rounded,
          couleur: AppColors.vert,
          titre: 'Activez les notifications',
          texte: 'Recevez $apport.',
          action: true,
        );
      case EtatNotifications.iphoneHorsEcranAccueil:
        return (
          icone: Icons.ios_share_rounded,
          couleur: AppColors.vert,
          titre: 'Installez Sprint sur votre iPhone',
          texte: 'Pour recevoir les notifications : dans Safari, touchez Partager puis « Sur l\'écran d\'accueil », '
              'ouvrez Sprint depuis son icône, puis activez les notifications (iOS 16.4 ou plus récent).',
          action: true,
        );
      case EtatNotifications.bloquees:
        return (
          icone: Icons.notifications_off_rounded,
          couleur: AppColors.texteDiscret,
          titre: 'Notifications bloquées',
          texte: estWeb
              ? 'Vous les avez refusées. Pour les recevoir, autorisez-les pour Sprint dans les réglages de votre '
                  'navigateur (ou de l\'app installée), puis rouvrez Sprint.'
              : 'Vous les avez refusées. Pour les recevoir : Réglages du téléphone > Applications > Sprint > Notifications.',
          action: false,
        );
      case EtatNotifications.nonSupportees:
        return (
          icone: Icons.notifications_off_outlined,
          couleur: AppColors.texteDiscret,
          titre: 'Notifications indisponibles',
          texte: 'Ce navigateur ne permet pas les notifications. Essayez Chrome, Edge, Firefox ou Safari récents.',
          action: false,
        );
      case EtatNotifications.activees:
        return (
          icone: Icons.notifications_active_rounded,
          couleur: AppColors.vert,
          titre: 'Notifications activées',
          texte: 'Vous recevrez $apport.',
          action: false,
        );
    }
  }
}
