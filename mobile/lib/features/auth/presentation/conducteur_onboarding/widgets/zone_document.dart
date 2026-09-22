import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';

enum _EtatDocument { aucun, enCours, termine }

/// Zone de "téléchargement" d'un document justificatif : simulée (aucun
/// vrai fichier n'est lu), avec une barre de progression puis un
/// check vert, pour un rendu strict et professionnel malgré le mode
/// démo.
class ZoneDocument extends StatefulWidget {
  const ZoneDocument({
    super.key,
    required this.titre,
    required this.description,
    required this.icon,
    required this.onStatutChange,
  });

  final String titre;
  final String description;
  final IconData icon;
  final ValueChanged<bool> onStatutChange;

  @override
  State<ZoneDocument> createState() => _ZoneDocumentState();
}

class _ZoneDocumentState extends State<ZoneDocument> {
  _EtatDocument _etat = _EtatDocument.aucun;

  void _demarrerUpload() {
    if (_etat != _EtatDocument.aucun) return;
    setState(() => _etat = _EtatDocument.enCours);
  }

  void _uploadTermine() {
    if (!mounted) return;
    setState(() => _etat = _EtatDocument.termine);
    widget.onStatutChange(true);
  }

  @override
  Widget build(BuildContext context) {
    final termine = _etat == _EtatDocument.termine;

    return InkWell(
      onTap: _demarrerUpload,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: termine ? AppColors.vert.withValues(alpha: 0.06) : AppColors.greyLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: termine ? AppColors.vert.withValues(alpha: 0.4) : AppColors.greyBorder,
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: termine ? AppColors.vert.withValues(alpha: 0.14) : Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                termine ? Icons.check_circle_rounded : widget.icon,
                color: termine ? AppColors.vert : AppColors.grey,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.titre,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                  ),
                  const SizedBox(height: 3),
                  if (_etat == _EtatDocument.enCours)
                    _BarreProgression(onTermine: _uploadTermine)
                  else
                    Text(
                      termine ? 'Document ajouté' : widget.description,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: termine ? AppColors.vert : AppColors.grey,
                        fontWeight: termine ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                ],
              ),
            ),
            if (_etat == _EtatDocument.aucun)
              const Icon(Icons.add_a_photo_outlined, color: AppColors.grey, size: 20),
          ],
        ),
      ),
    );
  }
}

class _BarreProgression extends StatefulWidget {
  const _BarreProgression({required this.onTermine});

  final VoidCallback onTermine;

  @override
  State<_BarreProgression> createState() => _BarreProgressionState();
}

class _BarreProgressionState extends State<_BarreProgression> {
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1100),
      onEnd: widget.onTermine,
      builder: (context, valeur, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: valeur,
                minHeight: 5,
                backgroundColor: AppColors.greyBorder,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.orange),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Téléchargement… ${(valeur * 100).round()}%',
              style: const TextStyle(fontSize: 10.5, color: AppColors.orange, fontWeight: FontWeight.w600),
            ),
          ],
        );
      },
    );
  }
}
