import 'package:flutter/material.dart';

/// Charte « Onyx & Vert » (octobre 2026, voulue par le client) : fonds noir
/// Onyx et gris très sombres, texte clair, vert vibrant pour tout ce qui agit
/// ou est actif (boutons Commander et Payer, icônes actives, contours), texte
/// Onyx sur les boutons verts. Plus aucun orange. Verre et dégradés
/// conservés : surfaces translucides, halos verts, lueur des boutons.
///
/// Les couleurs se lisent par leur RÔLE (fond, carte, texte, action), jamais
/// en valeur écrite dans un écran. Contrastes mesurés (WCAG, rapport
/// luminance) : texte clair sur fond 18:1, texte discret 7,9:1 sur fond et
/// 6,6:1 sur les champs, Onyx sur vert 11:1, vert sur fond 11:1.
class AppColors {
  AppColors._();

  // ── Fonds ────────────────────────────────────────────────────────────────

  /// Onyx : fond d'écran de base. Même valeur que dans `web/index.html`,
  /// `web/manifest.json` et les thèmes Android (écran de démarrage) : à
  /// changer partout à la fois.
  static const Color onyx = Color(0xFF0B0B0C);
  static const Color fond = onyx;

  /// Haut du dégradé de fond : gris très sombre, un peu plus clair que [fond].
  static const Color fondHaut = Color(0xFF151517);

  /// Surface pleine (carte, feuille, boîte de dialogue, menu).
  static const Color carte = Color(0xFF161619);

  /// Surface relevée : champs, pastilles, puces non sélectionnées.
  static const Color carteHaute = Color(0xFF1F1F23);

  /// Barre de navigation du bas.
  static const Color fondBarre = Color(0xFF0F0F11);

  // ── Textes ───────────────────────────────────────────────────────────────

  /// Texte principal, pictogrammes courants (blanc légèrement tiède).
  static const Color texte = Color(0xFFF5F5F7);

  /// Texte secondaire, indications, pictogrammes inactifs. 7,9:1 sur [fond].
  static const Color texteDiscret = Color(0xFFA3A3AB);

  // ── Action : le vert ─────────────────────────────────────────────────────

  /// Vert vibrant : boutons d'action (Commander, Payer…), icônes et onglets
  /// actifs, contours de sélection, liens. TOUJOURS avec du texte [onyx] dessus
  /// quand il sert de fond ; sur fond sombre il sert aussi de texte et de
  /// pictogramme (11:1).
  static const Color vert = Color(0xFF22E07A);

  /// Fin de dégradé des boutons verts, état pressé. Onyx dessus : 7:1.
  static const Color vertFonce = Color(0xFF14B861);

  /// Fond vert très sombre : pastille d'icône, ligne sélectionnée.
  static const Color vertTeinte = Color(0xFF183629);

  /// Dégradé des boutons d'action.
  static const LinearGradient degradeAction = LinearGradient(
    colors: [vert, vertFonce],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Verre, contours, ombres ──────────────────────────────────────────────

  /// Verre : blanc très translucide sur fond sombre (8 %), à poser sur un
  /// fond qui a de quoi être flouté (halos, photo, carte).
  static const Color verre = Color(0x14FFFFFF);

  /// Liseré du verre (12 % de blanc) et séparateurs fins.
  static const Color bordVerre = Color(0x1FFFFFFF);

  /// Contour plein d'un champ ou d'un séparateur (2,2:1 sur [fond]).
  static const Color bord = Color(0xFF3A3A41);

  /// Ombres : noir profond, les ombres claires ne se voient pas sur sombre.
  static const Color shadow = Color(0x66000000);
  static const Color shadowSoft = Color(0x40000000);

  // ── États (lisibles sur fond sombre : 5,7:1 et plus) ─────────────────────

  static const Color alerte = Color(0xFFFFD23F);
  static const Color danger = Color(0xFFFF5C5C);

  /// Étoiles de notation (jaune d'or, nettement distinct d'un orange).
  static const Color etoile = Color(0xFFF7CE46);

  // ── TRANSITOIRE ──────────────────────────────────────────────────────────
  // Anciens noms de la charte « Onyx & Light », encore lus par des fichiers
  // hors de la zone de design en attente d'autorisation du client
  // (lib/core/navigation/home_shell_page.dart,
  // lib/core/notifications/carte_notifications.dart). Valeurs de la charte
  // sombre ; à supprimer dès que ces fichiers sont migrés (le garde-fou de
  // palette, test/palette_onyx_vert_test.dart, n'autorise leur usage que là).
  static const Color orange = vert;
  static const Color bleu = vert;
  static const Color bleuClair = vertTeinte;
  static const Color background = fond;
  static const Color grey = texteDiscret;
  static const Color greyLight = carteHaute;
  static const Color greyBorder = bord;
}
