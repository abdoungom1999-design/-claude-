import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../firebase_options.dart';
import '../widgets/bouton_en_ligne_circulaire.dart';

/// Onglet Accueil du nouvel espace Conducteur : fond "carte" premium et
/// épuré (en attendant le vrai Google Maps — voir GOOGLE_MAPS_SETUP.md),
/// statut En ligne/Hors ligne (gros bouton rond flottant "GO" + radar) et
/// barre de gains du jour superposée. C'est ce bouton qui déclenche
/// l'écoute de [CourseService] côté [ConducteurShellPage] — cette
/// refonte visuelle ne touche à aucune logique de matchmaking.
class ConducteurAccueilTab extends StatelessWidget {
  const ConducteurAccueilTab({
    super.key,
    required this.enLigne,
    required this.onBasculerStatut,
    required this.gainsJourFcfa,
    required this.onSimulerCourse,
  });

  final bool enLigne;
  final ValueChanged<bool> onBasculerStatut;
  final int gainsJourFcfa;
  final VoidCallback onSimulerCourse;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          _FondCartePremium(enLigne: enLigne),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _BarreGainsJour(gainsFcfa: gainsJourFcfa),
            ),
          ),
          if (enLigne && !DefaultFirebaseOptions.estConfigure)
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 84, right: 20),
                  child: _PucePastille(onTap: onSimulerCourse),
                ),
              ),
            ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: BoutonEnLigneCirculaire(
                  enLigne: enLigne,
                  onTap: () => onBasculerStatut(!enLigne),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fond de carte "placeholder" premium : dégradé doux + grille de points
/// discrète (façon carte stylisée) et un repère central pulsant à
/// l'emplacement du conducteur, sans dépendre d'un vrai fond de carte
/// tant que Google Maps n'est pas branché.
class _FondCartePremium extends StatefulWidget {
  const _FondCartePremium({required this.enLigne});

  final bool enLigne;

  @override
  State<_FondCartePremium> createState() => _FondCartePremiumState();
}

class _FondCartePremiumState extends State<_FondCartePremium>
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
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF7F7F7), Color(0xFFEFEFEF)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _GrillePointsPainter()),
          ),
          if (widget.enLigne)
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    _AnneauRadar(progression: _controller.value),
                    _AnneauRadar(progression: (_controller.value + 0.5) % 1.0),
                  ],
                );
              },
            ),
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: widget.enLigne ? AppColors.orange : AppColors.noirProfond,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: (widget.enLigne ? AppColors.orange : Colors.black)
                      .withValues(alpha: 0.35),
                  blurRadius: 14,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnneauRadar extends StatelessWidget {
  const _AnneauRadar({required this.progression});

  final double progression;

  @override
  Widget build(BuildContext context) {
    final taille = 22 + progression * 220;
    final opacite = (1 - progression).clamp(0.0, 1.0) * 0.35;

    return Container(
      width: taille,
      height: taille,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.orange.withValues(alpha: opacite), width: 1.5),
      ),
    );
  }
}

/// Grille de points discrète évoquant une carte sans en être une —
/// dessinée une seule fois (pas d'animation), volontairement épurée.
class _GrillePointsPainter extends CustomPainter {
  static const _espacement = 28.0;

  @override
  void paint(Canvas canvas, Size size) {
    final peinture = Paint()..color = AppColors.greyBorder.withValues(alpha: 0.7);
    for (double y = _espacement / 2; y < size.height; y += _espacement) {
      for (double x = _espacement / 2; x < size.width; x += _espacement) {
        canvas.drawCircle(Offset(x, y), 1.4, peinture);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BarreGainsJour extends StatelessWidget {
  const _BarreGainsJour({required this.gainsFcfa});

  final int gainsFcfa;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.orangeLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.payments_outlined, color: AppColors.orange, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Aujourd'hui",
                style: TextStyle(fontSize: 11.5, color: AppColors.grey),
              ),
              Text(
                '$gainsFcfa FCFA',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Puce discrète permettant de déclencher manuellement l'animation
/// "Nouvelle course", pour ne pas dépendre uniquement du minuteur
/// automatique lors d'une démonstration (mode démo uniquement).
class _PucePastille extends StatelessWidget {
  const _PucePastille({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.radar_rounded, size: 14, color: AppColors.orange),
              SizedBox(width: 6),
              Text(
                'Simuler une course',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
