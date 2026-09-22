import 'package:flutter/material.dart';

/// Identité visuelle Sprint : dominante blanche, appels à l'action en orange,
/// textes et structures en noir.
class AppColors {
  AppColors._();

  static const Color orange = Color(0xFFFF6600);
  static const Color orangeDark = Color(0xFFCC4E00);
  static const Color orangeLight = Color(0xFFFFE9DB);
  static const Color background = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF000000);
  static const Color grey = Color(0xFF6B6B6B);
  static const Color greyLight = Color(0xFFF4F4F4);
  static const Color greyBorder = Color(0xFFE0E0E0);

  /// Ombres douces (cartes, champs, boutons) : noir à très faible opacité
  /// plutôt qu'un gris plat, pour un rendu "premium" cohérent partout.
  static const Color shadow = Color(0x1F000000);
  static const Color shadowSoft = Color(0x14000000);

  /// Surfaces "noir profond premium" : réservées à des éléments ponctuels
  /// qui appellent un fond sombre par nature (héros Welcome, carte
  /// Portefeuille), jamais au thème général de l'app qui reste blanc à
  /// dominante orange (identité Sprint / Groupe Santine).
  static const Color noirProfond = Color(0xFF0E0E0E);
  static const Color noirProfondClair = Color(0xFF1C1C1C);
}
