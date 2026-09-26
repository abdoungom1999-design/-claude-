import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'adaptive_map.dart';

/// Carte affichant le trajet départ → arrivée, ou une position unique
/// (ex : conducteur). Bascule automatiquement sur un vrai widget
/// `GoogleMap` dès qu'une clé API Google Maps réelle est configurée
/// (voir [AdaptiveMap]) ; utilise sinon OpenStreetMap (`flutter_map`,
/// gratuit, sans clé), exactement comme avant — l'API publique de ce
/// widget (et donc tous ses appelants) ne change pas.
class TripMap extends StatelessWidget {
  const TripMap({super.key, this.depart, this.arrivee, this.height = 220});

  final LatLng? depart;
  final LatLng? arrivee;
  final double height;

  static const _centreDakar = LatLng(14.6928, -17.4467);

  @override
  Widget build(BuildContext context) {
    final points = [if (depart != null) depart!, if (arrivee != null) arrivee!];
    final centre = points.isEmpty
        ? _centreDakar
        : LatLng(
            points.map((p) => p.latitude).reduce((a, b) => a + b) /
                points.length,
            points.map((p) => p.longitude).reduce((a, b) => a + b) /
                points.length,
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: height,
        child: AdaptiveMap(
          centre: centre,
          zoom: points.length == 2 ? 12 : 14,
          marqueurs: [
            if (depart != null) MarqueurCarte(type: TypeMarqueur.depart, position: depart!),
            if (arrivee != null) MarqueurCarte(type: TypeMarqueur.arrivee, position: arrivee!),
          ],
          polylignePoints: depart != null && arrivee != null ? [depart!, arrivee!] : null,
        ),
      ),
    );
  }
}
