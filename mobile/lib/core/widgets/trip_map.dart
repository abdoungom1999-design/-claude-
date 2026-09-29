import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as osm;
import 'package:latlong2/latlong.dart';
import '../maps/proximite_service.dart';
import 'adaptive_map.dart';

/// Carte affichant le trajet départ → arrivée, ou une position unique
/// (ex : conducteur), et si besoin les motos disponibles alentour.
/// Bascule automatiquement sur un vrai widget `GoogleMap` dès qu'une clé
/// API Google Maps réelle est configurée (voir [AdaptiveMap]) ; utilise
/// sinon OpenStreetMap (`flutter_map`, gratuit, sans clé).
///
/// La carte se recadre d'elle-même quand le départ ou l'arrivée change :
/// le trajet complet tient à l'écran, ou la carte se centre sur le seul
/// point choisi.
class TripMap extends StatefulWidget {
  const TripMap({
    super.key,
    this.depart,
    this.arrivee,
    this.height = 220,
    this.motos = const [],
    this.centre,
    this.coucheFond,
  });

  final LatLng? depart;
  final LatLng? arrivee;
  final double height;

  /// Motos disponibles alentour (positions déjà anonymisées).
  final List<MotoProche> motos;

  /// Centre de la carte tant qu'aucun départ ni arrivée n'est choisi
  /// (ex. position du client) ; Dakar par défaut.
  final LatLng? centre;

  /// Fond de carte ; par défaut celui de l'app. Remplacé dans les tests.
  final Widget? coucheFond;

  static const _centreDakar = LatLng(14.6928, -17.4467);

  @override
  State<TripMap> createState() => _TripMapState();
}

class _TripMapState extends State<TripMap> {
  final _controleur = osm.MapController();

  List<LatLng> get _points => [
        if (widget.depart != null) widget.depart!,
        if (widget.arrivee != null) widget.arrivee!,
      ];

  @override
  void didUpdateWidget(covariant TripMap ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.depart != widget.depart || ancien.arrivee != widget.arrivee || ancien.centre != widget.centre) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _recadrer());
    }
  }

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  void _recadrer() {
    if (!mounted) return;
    final points = _points;
    try {
      if (points.length >= 2) {
        _controleur.fitCamera(
          osm.CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(56), maxZoom: 16),
        );
      } else if (points.length == 1) {
        _controleur.move(points.first, 14);
      } else if (widget.centre != null) {
        _controleur.move(widget.centre!, 14);
      }
    } catch (_) {
      // Carte pas encore affichée : elle démarre déjà bien centrée.
    }
  }

  @override
  Widget build(BuildContext context) {
    final points = _points;
    final centre = points.isEmpty
        ? widget.centre ?? TripMap._centreDakar
        : LatLng(
            points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length,
            points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length,
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: widget.height,
        child: AdaptiveMap(
          centre: centre,
          zoom: points.length == 2 ? 12 : 14,
          controleur: _controleur,
          coucheFond: widget.coucheFond,
          motos: widget.motos,
          // Trajet complet = carte dézoomée : icônes plus petites.
          tailleMotos: points.length >= 2 ? 24 : 34,
          marqueurs: [
            if (widget.depart != null) MarqueurCarte(type: TypeMarqueur.depart, position: widget.depart!),
            if (widget.arrivee != null) MarqueurCarte(type: TypeMarqueur.arrivee, position: widget.arrivee!),
          ],
          polylignePoints: widget.depart != null && widget.arrivee != null ? [widget.depart!, widget.arrivee!] : null,
        ),
      ),
    );
  }
}
