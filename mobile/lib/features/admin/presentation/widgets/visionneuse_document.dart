import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/image_document.dart';

/// Ouvre une pièce justificative en plein écran pour l'audit : zoom
/// (molette, pincement ou boutons), déplacement, rotation par quart de
/// tour (photos prises de travers) et retour à l'échelle d'origine.
Future<void> ouvrirVisionneuseDocument(
  BuildContext context, {
  required String titre,
  required String source,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black,
    builder: (_) => _VisionneuseDocument(titre: titre, source: source),
  );
}

class _VisionneuseDocument extends StatefulWidget {
  const _VisionneuseDocument({required this.titre, required this.source});

  final String titre;
  final String source;

  @override
  State<_VisionneuseDocument> createState() => _VisionneuseDocumentState();
}

class _VisionneuseDocumentState extends State<_VisionneuseDocument> {
  static const _echelleMin = 1.0;
  static const _echelleMax = 8.0;

  final _transformation = TransformationController();
  int _quartsDeTour = 0;
  Size _zoneVisible = Size.zero;

  @override
  void dispose() {
    _transformation.dispose();
    super.dispose();
  }

  /// Zoome autour du centre de l'écran, dans les bornes de l'InteractiveViewer.
  void _zoomer(double facteur) {
    final actuelle = _transformation.value.getMaxScaleOnAxis();
    final cible = (actuelle * facteur).clamp(_echelleMin, _echelleMax);
    final ratio = cible / actuelle;
    final cx = _zoneVisible.width / 2;
    final cy = _zoneVisible.height / 2;
    _transformation.value = Matrix4.translationValues(cx, cy, 0)
      ..multiply(Matrix4.diagonal3Values(ratio, ratio, 1))
      ..multiply(Matrix4.translationValues(-cx, -cy, 0))
      ..multiply(_transformation.value);
  }

  void _reinitialiser() => _transformation.value = Matrix4.identity();

  void _pivoter() {
    setState(() => _quartsDeTour = (_quartsDeTour + 1) % 4);
    _reinitialiser();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, contraintes) {
                _zoneVisible = contraintes.biggest;
                return InteractiveViewer(
                  transformationController: _transformation,
                  minScale: _echelleMin,
                  maxScale: _echelleMax,
                  child: SizedBox.fromSize(
                    size: contraintes.biggest,
                    child: RotatedBox(
                      quarterTurns: _quartsDeTour,
                      child: ImageDocument(
                        source: widget.source,
                        fit: BoxFit.contain,
                        placeholder: const Center(
                          child: Text('Image illisible', style: TextStyle(color: Colors.white70)),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 12, 16),
              color: Colors.black.withValues(alpha: 0.6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.titre,
                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fermer',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(40),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _BoutonOutil(icone: Icons.zoom_out_rounded, info: 'Dézoomer', onTap: () => _zoomer(1 / 1.5)),
                    _BoutonOutil(icone: Icons.fit_screen_rounded, info: 'Taille réelle', onTap: _reinitialiser),
                    _BoutonOutil(icone: Icons.zoom_in_rounded, info: 'Zoomer', onTap: () => _zoomer(1.5)),
                    _BoutonOutil(icone: Icons.rotate_right_rounded, info: 'Pivoter', onTap: _pivoter),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoutonOutil extends StatelessWidget {
  const _BoutonOutil({required this.icone, required this.info, required this.onTap});

  final IconData icone;
  final String info;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: info,
      onPressed: onTap,
      iconSize: 26,
      color: Colors.white,
      hoverColor: AppColors.orange.withValues(alpha: 0.25),
      icon: Icon(icone),
    );
  }
}
