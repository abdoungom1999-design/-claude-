import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme/app_colors.dart';

/// Carte OpenStreetMap (via flutter_map, sans clé API) affichant le
/// trajet départ → arrivée, ou une position unique (ex : conducteur).
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
        child: FlutterMap(
          options: MapOptions(
            initialCenter: centre,
            initialZoom: points.length == 2 ? 12 : 14,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'sn.groupesantine.sprint',
            ),
            if (depart != null && arrivee != null)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [depart!, arrivee!],
                    color: AppColors.orange,
                    strokeWidth: 3,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                if (depart != null)
                  Marker(
                    point: depart!,
                    width: 36,
                    height: 36,
                    child: const Icon(
                      Icons.trip_origin,
                      color: AppColors.text,
                      size: 26,
                    ),
                  ),
                if (arrivee != null)
                  Marker(
                    point: arrivee!,
                    width: 36,
                    height: 36,
                    child: const Icon(
                      Icons.location_on,
                      color: AppColors.orange,
                      size: 36,
                    ),
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
      ),
    );
  }
}
