import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as osm;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart' as ll;
import '../config/google_maps_config.dart';
import '../theme/app_colors.dart';

/// Type de repère affichable par [AdaptiveMap] : détermine l'icône (côté
/// OpenStreetMap) ou la teinte du pin (côté Google Maps, qui ne permet
/// pas d'icônes widget arbitraires comme `flutter_map`).
enum TypeMarqueur { depart, arrivee }

class MarqueurCarte {
  const MarqueurCarte({required this.type, required this.position});

  final TypeMarqueur type;
  final ll.LatLng position;
}

/// Carte qui bascule automatiquement sur le vrai widget `GoogleMap` dès
/// qu'une vraie clé API est configurée ([GoogleMapsConfig.estConfigure]),
/// et affiche sinon la carte OpenStreetMap (`flutter_map`, gratuite,
/// sans clé) déjà utilisée dans toute l'app.
///
/// Objectif : préparer techniquement l'intégration Google Maps sans
/// jamais risquer de casser l'expérience actuelle. Monter un vrai
/// widget `GoogleMap` avec une clé API invalide/placeholder peut, côté
/// Web, déclencher une alerte JavaScript bloquante ("This page can't
/// load Google Maps correctly") visible par de vrais visiteurs du site
/// — inacceptable tant qu'aucune clé réelle n'existe. En centralisant
/// le choix ici, le jour où [GoogleMapsConfig.apiKey] est renseignée,
/// TOUS les écrans qui utilisent [AdaptiveMap] (via [TripMap] ou
/// directement) basculent sur la vraie carte sans aucune autre
/// modification de code.
class AdaptiveMap extends StatelessWidget {
  const AdaptiveMap({
    super.key,
    required this.centre,
    this.zoom = 14,
    this.marqueurs = const [],
    this.polylignePoints,
    this.interactif = true,
  });

  final ll.LatLng centre;
  final double zoom;
  final List<MarqueurCarte> marqueurs;
  final List<ll.LatLng>? polylignePoints;

  /// Désactive le pan/zoom/rotation quand la carte n'est qu'un fond
  /// visuel (ex. arrière-plan plein écran derrière un HUD flottant),
  /// pour éviter tout conflit de gestes avec les éléments posés dessus.
  final bool interactif;

  @override
  Widget build(BuildContext context) {
    if (GoogleMapsConfig.estConfigure) {
      return gmaps.GoogleMap(
        initialCameraPosition: gmaps.CameraPosition(
          target: gmaps.LatLng(centre.latitude, centre.longitude),
          zoom: zoom,
        ),
        markers: marqueurs
            .map(
              (m) => gmaps.Marker(
                markerId: gmaps.MarkerId('${m.type}-${m.position.latitude}-${m.position.longitude}'),
                position: gmaps.LatLng(m.position.latitude, m.position.longitude),
                icon: gmaps.BitmapDescriptor.defaultMarkerWithHue(
                  m.type == TypeMarqueur.arrivee
                      ? gmaps.BitmapDescriptor.hueOrange
                      : gmaps.BitmapDescriptor.hueAzure,
                ),
              ),
            )
            .toSet(),
        polylines: polylignePoints == null
            ? const {}
            : {
                gmaps.Polyline(
                  polylineId: const gmaps.PolylineId('trajet'),
                  points: polylignePoints!
                      .map((p) => gmaps.LatLng(p.latitude, p.longitude))
                      .toList(),
                  color: AppColors.orange,
                  width: 3,
                ),
              },
        zoomGesturesEnabled: interactif,
        scrollGesturesEnabled: interactif,
        rotateGesturesEnabled: interactif,
        tiltGesturesEnabled: interactif,
        zoomControlsEnabled: false,
        myLocationButtonEnabled: false,
      );
    }

    return osm.FlutterMap(
      options: osm.MapOptions(
        initialCenter: centre,
        initialZoom: zoom,
        interactionOptions: osm.InteractionOptions(
          flags: interactif ? osm.InteractiveFlag.all : osm.InteractiveFlag.none,
        ),
      ),
      children: [
        osm.TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'sn.groupesantine.sprint',
        ),
        if (polylignePoints != null)
          osm.PolylineLayer(
            polylines: [
              osm.Polyline(
                points: polylignePoints!,
                color: AppColors.orange,
                strokeWidth: 3,
              ),
            ],
          ),
        osm.MarkerLayer(
          markers: marqueurs
              .map(
                (m) => osm.Marker(
                  point: m.position,
                  width: 36,
                  height: 36,
                  child: m.type == TypeMarqueur.arrivee
                      ? const Icon(Icons.location_on, color: AppColors.orange, size: 36)
                      : const Icon(Icons.trip_origin, color: AppColors.text, size: 26),
                ),
              )
              .toList(),
        ),
        const osm.RichAttributionWidget(
          attributions: [osm.TextSourceAttribution('© OpenStreetMap contributors')],
        ),
      ],
    );
  }
}
