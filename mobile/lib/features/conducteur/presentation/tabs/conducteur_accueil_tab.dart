import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/theme/app_colors.dart';
import '../widgets/bouton_en_ligne_circulaire.dart';

/// Onglet Accueil du nouvel espace Conducteur : carte plein écran, statut
/// En ligne/Hors ligne (gros bouton rond flottant + radar) et barre de
/// gains du jour superposée. La position affichée suit le conducteur en
/// mode démo dès qu'une vraie position GPS est disponible ; sinon,
/// centrée sur Dakar.
class ConducteurAccueilTab extends StatelessWidget {
  const ConducteurAccueilTab({
    super.key,
    required this.enLigne,
    required this.onBasculerStatut,
    required this.gainsJourFcfa,
    required this.position,
    required this.onSimulerCourse,
  });

  final bool enLigne;
  final ValueChanged<bool> onBasculerStatut;
  final int gainsJourFcfa;
  final LatLng? position;
  final VoidCallback onSimulerCourse;

  static const _centreDakar = LatLng(14.6928, -17.4467);

  @override
  Widget build(BuildContext context) {
    final centre = position ?? _centreDakar;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          FlutterMap(
            options: MapOptions(initialCenter: centre, initialZoom: 15),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'sn.groupesantine.sprint',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: centre,
                    width: 54,
                    height: 54,
                    child: _MarqueurMoi(enLigne: enLigne),
                  ),
                ],
              ),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('© OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _BarreGainsJour(gainsFcfa: gainsJourFcfa),
            ),
          ),
          if (enLigne)
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

class _MarqueurMoi extends StatelessWidget {
  const _MarqueurMoi({required this.enLigne});

  final bool enLigne;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: enLigne ? AppColors.orange : AppColors.noirProfond,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: (enLigne ? AppColors.orange : Colors.black).withValues(alpha: 0.4),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.two_wheeler_rounded, color: Colors.white, size: 24),
    );
  }
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
/// automatique lors d'une démonstration.
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
