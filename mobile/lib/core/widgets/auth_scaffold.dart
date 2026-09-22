import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../theme/app_colors.dart';

/// Structure premium commune aux écrans de connexion/inscription Sprint :
/// un bandeau dégradé orange à coins arrondis (icône, titre, sous-titre)
/// surmonté d'une carte blanche flottante contenant le formulaire.
/// Remplace les anciens écrans "AppBar + Column" basiques par un rendu
/// haut de gamme, cohérent sur les 5 écrans d'authentification.
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
                icon: icon,
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

class _Header extends StatelessWidget {
  const _Header({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.showBackButton,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    final peutRevenir = showBackButton && Navigator.of(context).canPop();

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 64),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.orange, AppColors.orangeDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(36),
          bottomRight: Radius.circular(36),
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Cercles décoratifs très discrets pour un rendu moins plat.
          const Positioned(
            top: -30,
            right: -30,
            child: _Cercle(taille: 120, opacite: 0.10),
          ),
          const Positioned(
            top: 40,
            right: 40,
            child: _Cercle(taille: 50, opacite: 0.12),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (peutRevenir || ApiConfig.modeDemo)
                Row(
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
              SizedBox(height: peutRevenir || ApiConfig.modeDemo ? 20 : 8),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
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

class _Cercle extends StatelessWidget {
  const _Cercle({required this.taille, required this.opacite});

  final double taille;
  final double opacite;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: taille,
      height: taille,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: opacite),
      ),
    );
  }
}
