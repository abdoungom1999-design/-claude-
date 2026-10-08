import 'package:flutter/material.dart';
import '../../firebase_options.dart';
import '../config/api_config.dart';
import '../theme/app_colors.dart';
import 'onyx_vert.dart';

/// Structure commune aux écrans de connexion et d'inscription Sprint, en
/// charte « Onyx & Light » : fond très clair, repère de marque (logo dans
/// une tuile Onyx), titre en Onyx, formulaire dans une carte « verre ».
/// Pas de photo. Les champs et boutons du formulaire prennent le style
/// Onyx & Light par [ThemeOnyxVert].
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

  /// Conservée pour la compatibilité des écrans d'authentification qui
  /// l'appellent déjà ; le repère de marque est désormais le logo.
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget form;
  final Widget? footer;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    final peutRevenir = showBackButton && Navigator.of(context).canPop();

    return ThemeOnyxVert(
      child: Scaffold(
        backgroundColor: AppColors.fond,
        body: FondOnyxVert(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 48,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (peutRevenir)
                              IconButton(
                                onPressed: () => Navigator.of(context).pop(),
                                tooltip: 'Retour',
                                icon: const Icon(Icons.arrow_back_rounded, color: AppColors.texte),
                              )
                            else
                              const SizedBox.shrink(),
                            if (_authentificationSimulee) const _BadgeModeDemo(),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Align(alignment: Alignment.centerLeft, child: TuileLogo(taille: 64)),
                      const SizedBox(height: 22),
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.texte,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        style: const TextStyle(color: AppColors.texteDiscret, fontSize: 15, height: 1.35),
                      ),
                      const SizedBox(height: 26),
                      CarteVerre(padding: const EdgeInsets.fromLTRB(20, 24, 20, 20), child: form),
                      if (footer != null) ...[
                        const SizedBox(height: 18),
                        footer!,
                      ],
                    ],
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

/// Authentification simulée : ni Firebase ni API configurés. Avec
/// Firebase (cas du site et de l'APK), la connexion est réelle : pas de
/// badge.
bool get _authentificationSimulee => ApiConfig.modeDemo && !DefaultFirebaseOptions.estConfigure;

/// Repère discret indiquant que l'authentification est simulée (voir
/// [_authentificationSimulee]) : aucune donnée saisie n'est réellement
/// envoyée ni persistée.
class _BadgeModeDemo extends StatelessWidget {
  const _BadgeModeDemo();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.texte.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.texte.withValues(alpha: 0.18)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.science_outlined, color: AppColors.texte, size: 13),
          SizedBox(width: 5),
          Text(
            'MODE DÉMO',
            style: TextStyle(color: AppColors.texte, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }
}
