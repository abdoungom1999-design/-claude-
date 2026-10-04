import '../maps/fond_carte.dart';
import '../maps/proximite_service.dart';
import 'moto_vue_dessus.dart';
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
    this.motos = const [],
    this.tailleMotos = 34,
    this.controleur,
    this.coucheFond,
  });

  final ll.LatLng centre;
  final double zoom;
  final List<MarqueurCarte> marqueurs;
  final List<ll.LatLng>? polylignePoints;

  /// Motos disponibles alentour (anonymes), dessinées sous les repères.
  /// Uniquement sur la carte OpenStreetMap / Google « Sprint clair »
  /// (`flutter_map`) ; le composant Google Maps officiel, non utilisé
  /// aujourd'hui (voir GOOGLE_MAPS_SETUP.md), ne les affiche pas.
  final List<MotoProche> motos;

  /// Hauteur des icônes de moto (plus petites quand la carte est très
  /// dézoomée, pour ne pas masquer les repères du trajet).
  final double tailleMotos;

  /// Pour recentrer la carte après sa création (`initialCenter` n'est
  /// appliqué qu'au départ). Ignoré par le composant Google Maps.
  final osm.MapController? controleur;

  /// Fond de carte ; par défaut [CoucheFondCarte]. Les tests le
  /// remplacent (pas de réseau).
  final Widget? coucheFond;

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
                  color: AppColors.bleu,
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
      mapController: controleur,
      options: osm.MapOptions(
        initialCenter: centre,
        initialZoom: zoom,
        // Pas de rotation : les motos sont orientées selon le nord.
        interactionOptions: osm.InteractionOptions(
          flags: interactif ? osm.InteractiveFlag.all & ~osm.InteractiveFlag.rotate : osm.InteractiveFlag.none,
        ),
      ),
      children: [
        coucheFond ?? const CoucheFondCarte(),
        if (polylignePoints != null)
          osm.PolylineLayer(
            polylines: [
              osm.Polyline(
                points: polylignePoints!,
                color: AppColors.bleu,
                strokeWidth: 3,
              ),
            ],
          ),
        if (motos.isNotEmpty)
          osm.MarkerLayer(
            markers: [
              for (final m in motos)
                osm.Marker(
                  point: m.position,
                  width: tailleMotos + 6,
                  height: tailleMotos + 6,
                  child: Center(child: MotoVueDessus(cap: m.cap, taille: tailleMotos)),
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
                      ? const Icon(Icons.location_on, color: AppColors.bleu, size: 36)
                      : const Icon(Icons.trip_origin, color: AppColors.text, size: 26),
                ),
              )
              .toList(),
        ),
        const MentionsFondCarte(),
      ],
    );
  }
}
