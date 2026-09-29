import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/maps/motos_proches_controller.dart';
import '../../../../core/maps/proximite_service.dart';
import '../../../../core/widgets/trip_map.dart';
import 'pastille_motos.dart';

/// Carte de l'écran « Recherche d'un chauffeur » : le point de prise en
/// charge, et en fond les motos disponibles autour (anonymes, positions
/// arrondies à ~150 m par le serveur), pour faire patienter le client.
/// Le chauffeur qui acceptera n'y apparaît pas : dès son acceptation,
/// l'écran de suivi affiche sa position exacte.
class CarteRecherche extends StatefulWidget {
  const CarteRecherche({super.key, required this.priseEnCharge, this.proximite, this.coucheFond, this.hauteur = 280});

  /// Point de prise en charge ; `null` pour une ancienne course sans
  /// coordonnées (carte centrée sur Dakar).
  final LatLng? priseEnCharge;

  /// Injectables pour les tests.
  final ProximiteService? proximite;
  final Widget? coucheFond;
  final double hauteur;

  static const centreDakar = LatLng(14.6928, -17.4467);

  @override
  State<CarteRecherche> createState() => _CarteRechercheState();
}

class _CarteRechercheState extends State<CarteRecherche> {
  late final MotosProchesController _motos = MotosProchesController(
    service: widget.proximite,
    actif: () => mounted && TickerMode.valuesOf(context).enabled,
  );

  @override
  void initState() {
    super.initState();
    _motos.chercherAutour(widget.priseEnCharge ?? CarteRecherche.centreDakar);
  }

  @override
  void dispose() {
    _motos.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _motos,
      builder: (context, _) => Stack(
        children: [
          TripMap(
            depart: widget.priseEnCharge,
            height: widget.hauteur,
            motos: _motos.motos,
            coucheFond: widget.coucheFond,
          ),
          Positioned(
            left: 10,
            top: 10,
            child: PastilleMotos(motos: _motos.proximite, chargement: _motos.chargement),
          ),
        ],
      ),
    );
  }
}
