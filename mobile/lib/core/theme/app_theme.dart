import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'app_colors.dart';

/// Thème unique de l'app : sombre, charte « Onyx & Vert » (voir
/// [AppColors]). Tout composant Material (champs, boîtes de dialogue,
/// feuilles, puces, interrupteurs…) hérite d'ici d'un style cohérent : fond
/// Onyx, texte clair, vert vibrant pour l'action et l'état actif, texte Onyx
/// sur les boutons verts.
class AppTheme {
  AppTheme._();

  static const _rayonControle = 16.0;

  /// Nom historique du thème (l'app n'a qu'un thème, désormais sombre) :
  /// conservé tant que `lib/app.dart`, hors de la zone de design, l'appelle.
  static ThemeData get light => sombre;

  static ThemeData get sombre {
    const schema = ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.vert,
      onPrimary: AppColors.onyx,
      primaryContainer: AppColors.vertTeinte,
      onPrimaryContainer: AppColors.vert,
      secondary: AppColors.vert,
      onSecondary: AppColors.onyx,
      secondaryContainer: AppColors.vertTeinte,
      onSecondaryContainer: AppColors.vert,
      tertiary: AppColors.vert,
      onTertiary: AppColors.onyx,
      error: AppColors.danger,
      onError: AppColors.onyx,
      errorContainer: Color(0xFF3B1D1F),
      onErrorContainer: AppColors.danger,
      surface: AppColors.carte,
      onSurface: AppColors.texte,
      onSurfaceVariant: AppColors.texteDiscret,
      outline: AppColors.bord,
      outlineVariant: AppColors.bordVerre,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: AppColors.texte,
      onInverseSurface: AppColors.onyx,
      inversePrimary: AppColors.vertFonce,
      surfaceTint: Colors.transparent,
      surfaceContainerLowest: AppColors.fond,
      surfaceContainerLow: AppColors.carte,
      surfaceContainer: AppColors.carte,
      surfaceContainerHigh: AppColors.carteHaute,
      surfaceContainerHighest: AppColors.carteHaute,
    );

    final base = ThemeData(brightness: Brightness.dark, useMaterial3: true, colorScheme: schema);
    final textes = base.textTheme;
    // Styles dérivés du thème (et non écrits de zéro) : ils gardent la famille
    // de police de la plateforme.
    TextStyle style(TextStyle? depart, {double? taille, FontWeight? graisse, Color? couleur, double? interlettre, double? hauteur}) =>
        (depart ?? const TextStyle()).copyWith(
          fontSize: taille,
          fontWeight: graisse,
          color: couleur,
          letterSpacing: interlettre,
          height: hauteur,
        );

    OutlineInputBorder bord(Color couleur, [double epaisseur = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(_rayonControle),
          borderSide: BorderSide(color: couleur, width: epaisseur),
        );

    final boutonPlein = ElevatedButton.styleFrom(
      backgroundColor: AppColors.vert,
      foregroundColor: AppColors.onyx,
      disabledBackgroundColor: AppColors.carteHaute,
      disabledForegroundColor: AppColors.texteDiscret.withValues(alpha: 0.6),
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      textStyle: style(textes.labelLarge, taille: 15.5, graisse: FontWeight.w800, interlettre: 0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_rayonControle)),
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.fond,
      canvasColor: AppColors.fond,
      dividerColor: AppColors.bordVerre,
      dividerTheme: const DividerThemeData(color: AppColors.bordVerre, thickness: 1, space: 1),
      splashColor: AppColors.vert.withValues(alpha: 0.10),
      highlightColor: AppColors.vert.withValues(alpha: 0.06),
      iconTheme: const IconThemeData(color: AppColors.texte),
      textTheme: base.textTheme.apply(bodyColor: AppColors.texte, displayColor: AppColors.texte),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.fond,
        foregroundColor: AppColors.texte,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: style(textes.titleLarge, taille: 18, graisse: FontWeight.w800, interlettre: -0.3, couleur: AppColors.texte),
      ),
      // Action : vert plein, texte Onyx.
      elevatedButtonTheme: ElevatedButtonThemeData(style: boutonPlein),
      filledButtonTheme: FilledButtonThemeData(style: boutonPlein),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.vert,
          side: const BorderSide(color: AppColors.vert, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: style(textes.labelLarge, taille: 15, graisse: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_rayonControle)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.vert,
          textStyle: style(textes.labelLarge, graisse: FontWeight.w700),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.vert,
        foregroundColor: AppColors.onyx,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.carteHaute,
        hintStyle: style(textes.bodyMedium, taille: 14, couleur: AppColors.texteDiscret),
        labelStyle: style(textes.bodyMedium, graisse: FontWeight.w500, couleur: AppColors.texteDiscret),
        floatingLabelStyle: style(textes.bodyMedium, graisse: FontWeight.w600, couleur: AppColors.vert),
        prefixIconColor: AppColors.texteDiscret,
        suffixIconColor: AppColors.texteDiscret,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        border: bord(AppColors.bord),
        enabledBorder: bord(AppColors.bord),
        focusedBorder: bord(AppColors.vert, 1.8),
        errorBorder: bord(AppColors.danger, 1.5),
        focusedErrorBorder: bord(AppColors.danger, 1.8),
        errorStyle: style(textes.bodySmall, couleur: AppColors.danger),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.vert,
        selectionColor: AppColors.vert.withValues(alpha: 0.30),
        selectionHandleColor: AppColors.vert,
      ),
      cardTheme: CardThemeData(
        color: AppColors.carte,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.bordVerre),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.carte,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.bordVerre),
        ),
        titleTextStyle: style(textes.titleLarge, taille: 18, graisse: FontWeight.w800, couleur: AppColors.texte),
        contentTextStyle: style(textes.bodyMedium, taille: 14, couleur: AppColors.texteDiscret, hauteur: 1.4),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.carte,
        modalBackgroundColor: AppColors.carte,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: Colors.black.withValues(alpha: 0.62),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.carteHaute,
        contentTextStyle: style(textes.bodyMedium, taille: 13.5, graisse: FontWeight.w600, couleur: AppColors.texte),
        actionTextColor: AppColors.vert,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.bordVerre),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.carteHaute,
        selectedColor: AppColors.vert,
        disabledColor: AppColors.carteHaute,
        side: const BorderSide(color: AppColors.bordVerre),
        labelStyle: style(textes.labelLarge, graisse: FontWeight.w600, couleur: AppColors.texte),
        secondaryLabelStyle: style(textes.labelLarge, graisse: FontWeight.w700, couleur: AppColors.onyx),
        checkmarkColor: AppColors.onyx,
        iconTheme: const IconThemeData(color: AppColors.texte),
        shape: const StadiumBorder(),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (etats) => etats.contains(WidgetState.selected) ? AppColors.onyx : AppColors.texteDiscret,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (etats) => etats.contains(WidgetState.selected) ? AppColors.vert : AppColors.carteHaute,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (etats) => etats.contains(WidgetState.selected) ? AppColors.vert : AppColors.bord,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (etats) => etats.contains(WidgetState.selected) ? AppColors.vert : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(AppColors.onyx),
        side: const BorderSide(color: AppColors.texteDiscret, width: 1.5),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (etats) => etats.contains(WidgetState.selected) ? AppColors.vert : AppColors.texteDiscret,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.vert,
        linearTrackColor: AppColors.carteHaute,
        circularTrackColor: Colors.transparent,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.texteDiscret,
        textColor: AppColors.texte,
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        iconColor: AppColors.vert,
        collapsedIconColor: AppColors.texteDiscret,
        textColor: AppColors.texte,
        collapsedTextColor: AppColors.texte,
        shape: Border(),
        collapsedShape: Border(),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.vert,
        unselectedLabelColor: AppColors.texteDiscret,
        indicatorColor: AppColors.vert,
        dividerColor: AppColors.bordVerre,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.carteHaute,
        surfaceTintColor: Colors.transparent,
        textStyle: style(textes.bodyMedium, taille: 14, couleur: AppColors.texte),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.bordVerre),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.carteHaute,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.bordVerre),
        ),
        textStyle: style(textes.bodySmall, taille: 12, couleur: AppColors.texte),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(Colors.white.withValues(alpha: 0.24)),
      ),
    );
  }
}
