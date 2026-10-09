import 'package:flutter/material.dart';
import '../../../../core/maps/geocoding_service.dart';
import '../../../../core/widgets/address_search_field.dart';
import '../depart_gps_controller.dart';
import 'depart_gps_etat.dart';

/// Champ du départ d'un écran de commande : adresse modifiable, pré-remplie par
/// la position GPS du client, avec dessous où en est la localisation (voir
/// [DepartGpsController]).
class ChampDepartGps extends StatelessWidget {
  const ChampDepartGps({
    super.key,
    required this.gps,
    required this.label,
    this.service,
    this.messageActif = DepartGpsEtat.messageActifPassager,
  });

  final DepartGpsController gps;
  final String label;

  /// Recherche d'adresses ; injectable pour les tests.
  final ServiceAdresses? service;

  /// Ce que le client lit quand le départ est sa position GPS.
  final String messageActif;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: gps,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AddressSearchField(
            key: ValueKey('depart-${gps.versionChamp}'),
            label: label,
            controller: gps.texte,
            service: service,
            prefixIcon: Icons.my_location,
            onSelected: gps.departChoisi,
            onEdited: gps.departModifie,
            onTap: gps.departTouche,
          ),
          DepartGpsEtat(etat: gps.etat, messageActif: messageActif, onUtiliserMaPosition: gps.chercherPosition),
        ],
      ),
    );
  }
}
