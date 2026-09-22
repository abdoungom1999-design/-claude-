import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// Énorme bouton rond flottant pour basculer En ligne / Hors ligne,
/// pensé pour une lecture rapide au volant : noir/gris hors ligne,
/// orange et radar clignotant (recherche de clients) en ligne.
class BoutonEnLigneCirculaire extends StatefulWidget {
  const BoutonEnLigneCirculaire({
    super.key,
    required this.enLigne,
    required this.onTap,
  });

  final bool enLigne;
  final VoidCallback onTap;

  @override
  State<BoutonEnLigneCirculaire> createState() =>
      _BoutonEnLigneCirculaireState();
}

class _BoutonEnLigneCirculaireState extends State<BoutonEnLigneCirculaire>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      height: 190,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.enLigne)
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    _CercleRadar(progression: _controller.value),
                    _CercleRadar(
                      progression: (_controller.value + 0.5) % 1.0,
                    ),
                  ],
                );
              },
            ),
          GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 118,
              height: 118,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: widget.enLigne
                      ? const [AppColors.orange, AppColors.orangeDark]
                      : const [AppColors.noirProfondClair, AppColors.noirProfond],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: Colors.white, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: (widget.enLigne ? AppColors.orange : Colors.black)
                        .withValues(alpha: 0.4),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    widget.enLigne
                        ? Icons.bolt_rounded
                        : Icons.power_settings_new_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.enLigne ? 'EN LIGNE' : 'HORS LIGNE',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CercleRadar extends StatelessWidget {
  const _CercleRadar({required this.progression});

  final double progression;

  @override
  Widget build(BuildContext context) {
    final taille = 118 + progression * 72;
    final opacite = (1 - progression).clamp(0.0, 1.0) * 0.5;

    return Container(
      width: taille,
      height: taille,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.orange.withValues(alpha: opacite),
          width: 2,
        ),
      ),
    );
  }
}
