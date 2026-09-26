import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../../../../core/demo/demo_data.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/adaptive_map.dart';
import '../../../../firebase_options.dart';
import '../widgets/bouton_en_ligne_circulaire.dart';

/// Onglet Accueil du nouvel espace Conducteur : carte plein écran (voir
/// [AdaptiveMap] — OpenStreetMap tant qu'aucune clé Google Maps réelle
/// n'est configurée, voir GOOGLE_MAPS_SETUP.md) surmontée d'un voile
/// sombre pour la lisibilité, de cartes flottantes en verre dépoli
/// (glassmorphism) meublant l'espace autour du bouton "GO", et du
/// statut En ligne/Hors ligne. C'est ce bouton qui déclenche l'écoute
/// de [CourseService] côté [ConducteurShellPage] — cette refonte
/// visuelle ne touche à aucune logique de matchmaking.
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
          _FondCarteConducteur(enLigne: widget.enLigne),
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

/// Fond plein écran du tableau de bord Conducteur : la vraie carte
/// (voir [AdaptiveMap]), un voile sombre par-dessus pour garder le HUD
/// en verre dépoli lisible quelle que soit la carte affichée en
/// dessous (tuiles OSM claires aujourd'hui, Google Maps demain), et un
/// repère central pulsant (anneaux radar quand en ligne).
class _FondCarteConducteur extends StatefulWidget {
  const _FondCarteConducteur({required this.enLigne});

  final bool enLigne;

  static const _centreDakar = ll.LatLng(14.6928, -17.4467);

  @override
  State<_FondCarteConducteur> createState() => _FondCarteConducteurState();
}

class _FondCarteConducteurState extends State<_FondCarteConducteur>
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
    return Stack(
      fit: StackFit.expand,
      children: [
        const AdaptiveMap(
          centre: _FondCarteConducteur._centreDakar,
          zoom: 14,
          interactif: false,
        ),
        // Voile sombre : simple dégradé (plus foncé en haut/bas, plus
        // clair au centre) pour garantir la lisibilité du HUD blanc
        // quelle que soit la carte réelle affichée dessous.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0x8C000000),
                Color(0x26000000),
                Color(0x73000000),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.45, 1.0],
            ),
          ),
        ),
        if (widget.enLigne)
          Center(
            child: AnimatedBuilder(
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
          ),
        Center(
          child: Container(
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
        ),
      ],
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
