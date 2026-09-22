import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../theme/app_colors.dart';

/// Structure premium commune aux écrans de connexion/inscription Sprint :
/// un bandeau "Hero Header" plein cadre (vraie photo en arrière-plan,
/// filtre en dégradé noir profond vers orange Santine, titre, sous-titre)
/// surmonté d'une carte blanche flottante contenant le formulaire.
/// Volontairement épuré (pas d'icône superposée à la photo) pour laisser
/// l'image et le texte porter l'ambiance premium.
///
/// Note de transparence : la photo d'arrière-plan ([_urlPhotoHeaderAuth])
/// n'a pas pu être chargée ni vérifiée depuis cet environnement de
/// développement (accès direct aux CDN d'images bloqué par le bac à
/// sable — confirmé à nouveau via l'outil de fetch web, même verdict que
/// pour la photo héros de l'écran Welcome et le carrousel Accueil). Elle
/// reste en place pour la production ; en cas d'échec de chargement chez
/// un visiteur, [_FondRepliOrange] affiche automatiquement l'ancien
/// dégradé orange uni, jamais une image cassée.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.form,
    this.footer,
    this.showBackButton = true,
  });

  /// Conservée pour la compatibilité des 4 écrans d'authentification qui
  /// l'appellent déjà ; plus affichée dans le nouveau Hero Header (voir
  /// note de classe), la photo et le texte suffisant à l'ambiance visée.
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget form;
  final Widget? footer;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                title: title,
                subtitle: subtitle,
                showBackButton: showBackButton,
              ),
              Transform.translate(
                offset: const Offset(0, -28),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(
                          color: AppColors.shadow,
                          blurRadius: 24,
                          offset: Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        form,
                        if (footer != null) ...[
                          const SizedBox(height: 20),
                          footer!,
                        ],
                      ],
                    ),
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

/// Photo héros du bandeau d'authentification (rue urbaine de nuit,
/// ambiance premium). Voir la note de transparence en tête de
/// [AuthScaffold] : cette URL n'a pas pu être vérifiée depuis
/// l'environnement de développement, mais un repli en dégradé orange
/// (l'ancien fond, inchangé) s'affiche automatiquement si elle ne
/// charge pas.
const _urlPhotoHeaderAuth =
    'https://images.unsplash.com/photo-1519501025264-65ba15a82390'
    '?auto=format&fit=crop&w=1200&q=80';

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.showBackButton,
  });

  final String title;
  final String subtitle;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    final peutRevenir = showBackButton && Navigator.of(context).canPop();

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(36),
        bottomRight: Radius.circular(36),
      ),
      child: SizedBox(
        height: 280,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Vraie photo plein cadre : repli en dégradé orange (identité
            // Sprint) tant qu'elle charge, ou si elle échoue.
            Image.network(
              _urlPhotoHeaderAuth,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const _FondRepliOrange();
              },
              errorBuilder: (context, error, stackTrace) =>
                  const _FondRepliOrange(),
            ),
            // Filtre en dégradé noir profond -> orange Santine : sombre
            // et mystérieux en haut pour la lisibilité du texte, laisse
            // la photo respirer au centre, bascule chaleureusement vers
            // l'orange de marque en bas.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.5, 1.0],
                  colors: [
                    AppColors.noirProfond.withValues(alpha: 0.90),
                    AppColors.noirProfond.withValues(alpha: 0.42),
                    AppColors.orange.withValues(alpha: 0.68),
                  ],
                ),
              ),
            ),
            if (peutRevenir || ApiConfig.modeDemo)
              Positioned(
                top: 12,
                left: 20,
                right: 20,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (peutRevenir)
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      )
                    else
                      const SizedBox.shrink(),
                    if (ApiConfig.modeDemo) const _BadgeModeDemo(),
                  ],
                ),
              ),
            // Titre + sous-titre ancrés en bas du bandeau, façon affiche :
            // la photo occupe tout l'espace au-dessus, sans être coupée
            // par un bloc de contenu centré.
            Positioned(
              left: 22,
              right: 22,
              bottom: 30,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      height: 1.1,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 14)],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 14,
                      height: 1.3,
                      shadows: const [Shadow(color: Colors.black54, blurRadius: 10)],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fond de repli (ancien dégradé orange Sprint) affiché tant que la photo
/// du bandeau d'authentification charge, ou si elle échoue.
class _FondRepliOrange extends StatelessWidget {
  const _FondRepliOrange();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.orange, AppColors.orangeDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }
}

/// Repère discret indiquant que l'authentification est simulée (build web
/// sans backend public configuré, voir [ApiConfig.modeDemo]) : aucune
/// donnée saisie n'est réellement envoyée ni persistée.
class _BadgeModeDemo extends StatelessWidget {
  const _BadgeModeDemo();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.science_outlined, color: Colors.white, size: 13),
          SizedBox(width: 5),
          Text(
            'MODE DÉMO',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
