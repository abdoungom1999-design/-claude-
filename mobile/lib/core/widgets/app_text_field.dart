import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Champ de saisie Sprint, charte « Onyx & Vert » : surface de verre sombre,
/// liseré fin, pictogramme gris qui passe au vert au focus, contour vert
/// épais au focus, erreur en rouge lisible sur fond sombre.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.readOnly = false,
    this.keyboardType,
    this.maxLines = 1,
    this.validator,
    this.onChanged,
    this.onTap,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final bool readOnly;
  final TextInputType? keyboardType;
  final int maxLines;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder bord(Color couleur, [double epaisseur = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: couleur, width: epaisseur),
        );
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      readOnly: readOnly,
      keyboardType: keyboardType,
      maxLines: obscureText ? 1 : maxLines,
      validator: validator,
      onChanged: onChanged,
      onTap: onTap,
      style: const TextStyle(color: AppColors.texte, fontSize: 15.5, fontWeight: FontWeight.w500),
      cursorColor: AppColors.vert,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.texteDiscret, fontSize: 14),
        prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 20) : null,
        prefixIconColor: WidgetStateColor.resolveWith(
          (etats) => etats.contains(WidgetState.focused) ? AppColors.vert : AppColors.texteDiscret,
        ),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: AppColors.verre,
        labelStyle: const TextStyle(color: AppColors.texteDiscret, fontWeight: FontWeight.w500),
        floatingLabelStyle: const TextStyle(color: AppColors.vert, fontWeight: FontWeight.w600),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        border: bord(AppColors.bord),
        enabledBorder: bord(AppColors.bord),
        focusedBorder: bord(AppColors.vert, 1.8),
        errorBorder: bord(AppColors.danger, 1.4),
        focusedErrorBorder: bord(AppColors.danger, 1.8),
      ),
    );
  }
}
