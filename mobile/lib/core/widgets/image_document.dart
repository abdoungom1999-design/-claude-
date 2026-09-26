import 'dart:convert';

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Affiche une photo de document chauffeur, quel que soit son format de
/// stockage : URL Firebase Storage (format actuel) ou data URI Base64
/// (repli, et documents envoyés avant la migration vers Storage — voir
/// `ConducteurDocumentsService`).
class ImageDocument extends StatelessWidget {
  const ImageDocument({
    super.key,
    required this.source,
    required this.placeholder,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  final String? source;
  final Widget placeholder;
  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final valeur = source;
    if (valeur == null || valeur.isEmpty) return placeholder;

    if (valeur.startsWith('data:')) {
      try {
        return Image.memory(
          base64Decode(valeur.split(',').last),
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, __, ___) => placeholder,
        );
      } on FormatException {
        return placeholder;
      }
    }

    return Image.network(
      valeur,
      width: width,
      height: height,
      fit: fit,
      // Sur le Web, si le bucket Storage n'a pas d'en-têtes CORS, Flutter
      // bascule sur une balise <img> plutôt que d'échouer.
      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
      loadingBuilder: (context, child, progression) {
        if (progression == null) return child;
        return SizedBox(
          width: width,
          height: height,
          child: const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.orange),
            ),
          ),
        );
      },
      errorBuilder: (_, __, ___) => placeholder,
    );
  }
}
