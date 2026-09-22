import 'dart:async';

import 'package:flutter/material.dart';
import '../../../../core/demo/demo_data.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/premium_dialog.dart';

/// Affiche la bottom sheet "Nouvelle course" (compte à rebours de 15s) :
/// disparaît d'elle-même (refus silencieux) si le chauffeur n'accepte
/// pas à temps.
Future<void> afficherNouvelleCourseSheet(BuildContext context) {
  final course = DemoData.genererNouvelleCourseConducteur();
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _NouvelleCourseSheet(course: course),
  );
}

class _NouvelleCourseSheet extends StatefulWidget {
  const _NouvelleCourseSheet({required this.course});

  final NouvelleCourseSimulee course;

  @override
  State<_NouvelleCourseSheet> createState() => _NouvelleCourseSheetState();
}

class _NouvelleCourseSheetState extends State<_NouvelleCourseSheet>
    with SingleTickerProviderStateMixin {
  static const int _dureeTotaleSecondes = 15;
  int _secondesRestantes = _dureeTotaleSecondes;
  Timer? _minuteur;

  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _minuteur = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondesRestantes <= 1) {
        _minuteur?.cancel();
        if (mounted) Navigator.of(context).maybePop();
        return;
      }
      setState(() => _secondesRestantes--);
    });
  }

  @override
  void dispose() {
    _minuteur?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _accepter(BuildContext contextParent) {
    _minuteur?.cancel();
    Navigator.of(context).pop();
    PremiumDialog.afficher(
      contextParent,
      icon: Icons.check_circle_outline_rounded,
      titre: 'Course acceptée !',
      message: 'Rendez-vous à ${widget.course.adresseDepart} pour récupérer '
          'votre client.',
      succes: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final contextParent = context;
    final estColis = widget.course.type == 'Colis';

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.greyBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.orangeLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  estColis ? Icons.inventory_2_outlined : Icons.two_wheeler_rounded,
                  color: AppColors.orange,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                estColis ? 'Nouvelle livraison !' : 'Nouvelle course !',
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.course.prixFcfa} FCFA',
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Prix estimé de la course',
                      style: TextStyle(fontSize: 12.5, color: AppColors.grey),
                    ),
                  ],
                ),
              ),
              _CompteARebours(
                secondesRestantes: _secondesRestantes,
                dureeTotale: _dureeTotaleSecondes,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.greyLight,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LigneInfo(
                  icon: Icons.near_me_outlined,
                  texte: 'À ${widget.course.approcheMin} min de vous',
                ),
                const SizedBox(height: 10),
                _LigneInfo(
                  icon: Icons.location_on_outlined,
                  texte: widget.course.adresseDepart,
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    side: const BorderSide(color: AppColors.greyBorder),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Refuser',
                    style: TextStyle(
                      color: AppColors.grey,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 2,
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    final eclat = 0.25 + _pulseController.value * 0.35;
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.orange.withValues(alpha: eclat),
                            blurRadius: 22,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: child,
                    );
                  },
                  child: ElevatedButton(
                    onPressed: () => _accepter(contextParent),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.orange,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'ACCEPTER',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompteARebours extends StatelessWidget {
  const _CompteARebours({
    required this.secondesRestantes,
    required this.dureeTotale,
  });

  final int secondesRestantes;
  final int dureeTotale;

  @override
  Widget build(BuildContext context) {
    final progression = secondesRestantes / dureeTotale;

    return SizedBox(
      width: 58,
      height: 58,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 58,
            height: 58,
            child: CircularProgressIndicator(
              value: progression,
              strokeWidth: 5,
              backgroundColor: AppColors.greyLight,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.orange),
            ),
          ),
          Text(
            '$secondesRestantes',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _LigneInfo extends StatelessWidget {
  const _LigneInfo({required this.icon, required this.texte});

  final IconData icon;
  final String texte;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.grey),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            texte,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
