import 'dart:convert';

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// L'adresse de téléchargement est celle d'un PDF (envoyé sous `{cle}.pdf`
/// dans Firebase Storage).
bool estUrlPdf(String? source) {
  if (source == null || source.startsWith('data:')) return false;
  final chemin = Uri.tryParse(source)?.path;
  if (chemin == null) return false;
  try {
    return Uri.decodeComponent(chemin).toLowerCase().endsWith('.pdf');
  } on ArgumentError {
    return false;
  }
}

/// Affiche une photo de document chauffeur, quel que soit son format de
/// stockage : URL Firebase Storage (format actuel) ou data URI Base64
/// (repli, et documents envoyés avant la migration vers Storage — voir
/// `ConducteurDocumentsService`). Un PDF ne s'affiche pas en image : une
/// pastille « Document PDF » le représente (l'Admin l'ouvre en plein écran).
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

    if (estUrlPdf(valeur)) {
      return SizedBox(
        width: width,
        height: height,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.picture_as_pdf_outlined, color: AppColors.vert, size: 40),
              SizedBox(height: 8),
              Text('Document PDF', style: TextStyle(fontSize: 12.5, color: AppColors.texteDiscret)),
            ],
          ),
        ),
      );
    }

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
              child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.vert),
            ),
          ),
        );
      },
      errorBuilder: (_, __, ___) => placeholder,
    );
  }
}
