import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import '../../../../core/demo/demo_data.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../firebase_options.dart';
import '../widgets/bouton_en_ligne_circulaire.dart';

/// Onglet Accueil du nouvel espace Conducteur : Dashboard premium "dark
/// mode" façon cockpit nocturne (en attendant le vrai Google Maps —
/// voir GOOGLE_MAPS_SETUP.md), cartes flottantes en verre dépoli
/// (glassmorphism) meublant l'espace autour du bouton "GO", et statut
/// En ligne/Hors ligne. C'est ce bouton qui déclenche l'écoute de
/// [CourseService] côté [ConducteurShellPage] — cette refonte visuelle
/// ne touche à aucune logique de matchmaking.
class ConducteurAccueilTab extends StatefulWidget {
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
  State<ConducteurAccueilTab> createState() => _ConducteurAccueilTabState();
}

class _ConducteurAccueilTabState extends State<ConducteurAccueilTab> {
  Timer? _minuteurAffichage;
  DateTime? _debutEnLigne;

  @override
  void initState() {
    super.initState();
    if (widget.enLigne) _debutEnLigne = DateTime.now();
    // Rafraîchit juste l'affichage du compteur "Temps en ligne" ;
    // aucune incidence sur le radar de courses (géré côté
    // ConducteurShellPage, indépendant de ce minuteur d'affichage).
    _minuteurAffichage = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant ConducteurAccueilTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.enLigne && widget.enLigne) {
      setState(() => _debutEnLigne = DateTime.now());
    } else if (oldWidget.enLigne && !widget.enLigne) {
      setState(() => _debutEnLigne = null);
    }
  }

  @override
  void dispose() {
    _minuteurAffichage?.cancel();
    super.dispose();
  }

  String get _dureeEnLigneTexte {
    final debut = _debutEnLigne;
    if (debut == null) return '—';
    final duree = DateTime.now().difference(debut);
    final heures = duree.inHours;
    final minutes = duree.inMinutes % 60;
    return heures > 0 ? '${heures}h${minutes.toString().padLeft(2, '0')}' : '${minutes}min';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.noirProfond,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _FondNocturnePremium(enLigne: widget.enLigne),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CarteObjectifJour(gainsFcfa: widget.gainsJourFcfa),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _CarteStatVerre(
                          icon: Icons.verified_rounded,
                          valeur:
                              '${(DemoData.tauxAcceptationConducteur * 100).round()}%',
                          label: "Taux d'acceptation",
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _CarteStatVerre(
                          icon: Icons.access_time_filled_rounded,
                          valeur: _dureeEnLigneTexte,
                          label: 'Temps en ligne',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (widget.enLigne && !DefaultFirebaseOptions.estConfigure)
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 168, right: 20),
                  child: _PucePastille(onTap: widget.onSimulerCourse),
                ),
              ),
            ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: BoutonEnLigneCirculaire(
                  enLigne: widget.enLigne,
                  onTap: () => widget.onBasculerStatut(!widget.enLigne),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fond "cockpit nocturne" : dégradé noir profond, halos de lumière
/// façon ville la nuit floutée (sans dépendre d'une image réseau —
/// indisponible depuis ce bac à sable, voir la note de WelcomePage),
/// grille de points façon carte nocturne, et un repère central pulsant.
class _FondNocturnePremium extends StatefulWidget {
  const _FondNocturnePremium({required this.enLigne});

  final bool enLigne;

  @override
  State<_FondNocturnePremium> createState() => _FondNocturnePremiumState();
}

class _FondNocturnePremiumState extends State<_FondNocturnePremium>
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
          colors: [Color(0xFF05060A), Color(0xFF12141C), Color(0xFF1A1D28)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Halos de lumière "ville la nuit" (bokeh), en dégradés radiaux
          // plutôt qu'une vraie image floutée.
          const Positioned(
            top: -80,
            left: -60,
            child: _HaloLumiere(couleur: AppColors.orange, taille: 320, opacite: 0.16),
          ),
          const Positioned(
            bottom: -100,
            right: -80,
            child: _HaloLumiere(couleur: Color(0xFF3B5BFF), taille: 380, opacite: 0.14),
          ),
          const Positioned(
            top: 180,
            right: -60,
            child: _HaloLumiere(couleur: Color(0xFFB388FF), taille: 220, opacite: 0.10),
          ),
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
              color: widget.enLigne ? AppColors.orange : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: (widget.enLigne ? AppColors.orange : Colors.white)
                      .withValues(alpha: 0.4),
                  blurRadius: 16,
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

class _HaloLumiere extends StatelessWidget {
  const _HaloLumiere({required this.couleur, required this.taille, required this.opacite});

  final Color couleur;
  final double taille;
  final double opacite;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: taille,
      height: taille,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [couleur.withValues(alpha: opacite), couleur.withValues(alpha: 0)],
        ),
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

/// Grille de points discrète évoquant une carte nocturne sans en être
/// une — dessinée une seule fois (pas d'animation), volontairement
/// épurée.
class _GrillePointsPainter extends CustomPainter {
  static const _espacement = 28.0;

  @override
  void paint(Canvas canvas, Size size) {
    final peinture = Paint()..color = Colors.white.withValues(alpha: 0.05);
    for (double y = _espacement / 2; y < size.height; y += _espacement) {
      for (double x = _espacement / 2; x < size.width; x += _espacement) {
        canvas.drawCircle(Offset(x, y), 1.3, peinture);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Carte en verre dépoli générique (glassmorphism) : fond translucide
/// flouté + fine bordure lumineuse, pour flotter avec élégance sur le
/// fond nocturne sans jamais devenir un bloc opaque.
class _CarteVerre extends StatelessWidget {
  const _CarteVerre({required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _CarteObjectifJour extends StatelessWidget {
  const _CarteObjectifJour({required this.gainsFcfa});

  final int gainsFcfa;

  @override
  Widget build(BuildContext context) {
    const objectif = DemoData.objectifJournalierFcfa;
    final progression = (gainsFcfa / objectif).clamp(0.0, 1.0);

    return _CarteVerre(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.orange.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.flag_rounded, color: AppColors.orange, size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Objectif du jour',
                      style: TextStyle(fontSize: 11.5, color: Colors.white70),
                    ),
                    Text(
                      '$gainsFcfa / $objectif FCFA',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progression,
                    minHeight: 7,
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.orange),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CarteStatVerre extends StatelessWidget {
  const _CarteStatVerre({required this.icon, required this.valeur, required this.label});

  final IconData icon;
  final String valeur;
  final String label;

  @override
  Widget build(BuildContext context) {
    return _CarteVerre(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.orange, size: 18),
          const SizedBox(height: 8),
          Text(
            valeur,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 10.5, color: Colors.white60),
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
    return _CarteVerre(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.radar_rounded, size: 14, color: AppColors.orange),
            SizedBox(width: 6),
            Text(
              'Simuler une course',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
