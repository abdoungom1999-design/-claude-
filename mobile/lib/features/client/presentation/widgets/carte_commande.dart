import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/location/localiser.dart';
import '../../../../core/maps/motos_proches_controller.dart';
import '../../../../core/maps/proximite_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/trip_map.dart';
import '../../../courses/data/estimation_course_controller.dart';

/// Carte des écrans de commande (course moto et colis) : le trajet choisi,
/// et en fond les motos disponibles autour du client, comme sur l'accueil.
///
/// Les motos sont cherchées autour du départ choisi, sinon autour du
/// client s'il est déjà localisé (jamais de demande d'autorisation ici),
/// sinon autour du centre de Dakar. Mêmes règles d'anonymat que l'accueil :
/// positions arrondies à ~150 m par le serveur, aucune identité.
class CarteCommande extends StatefulWidget {
  const CarteCommande({
    super.key,
    required this.estimation,
    this.proximite,
    this.localiser,
    this.coucheFond,
  });

  final EstimationCourseController estimation;

  /// Injectables pour les tests.
  final ProximiteService? proximite;
  final Localiser? localiser;
  final Widget? coucheFond;

  static const centreDakar = LatLng(14.6928, -17.4467);

  @override
  State<CarteCommande> createState() => _CarteCommandeState();
}

class _CarteCommandeState extends State<CarteCommande> {
  late final MotosProchesController _motos = MotosProchesController(
    service: widget.proximite,
    actif: () => mounted && TickerMode.valuesOf(context).enabled,
  );

  LatLng? _moi;

  LatLng? get _depart {
    final d = widget.estimation.depart;
    return d == null ? null : LatLng(d.latitude, d.longitude);
  }

  LatLng? get _arrivee {
    final a = widget.estimation.arrivee;
    return a == null ? null : LatLng(a.latitude, a.longitude);
  }

  @override
  void initState() {
    super.initState();
    widget.estimation.addListener(_surTrajet);
    _motos.chercherAutour(_pointDeRecherche);
    _localiserSansDemander();
  }

  @override
  void didUpdateWidget(covariant CarteCommande ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.estimation != widget.estimation) {
      ancien.estimation.removeListener(_surTrajet);
      widget.estimation.addListener(_surTrajet);
      _surTrajet();
    }
  }

  @override
  void dispose() {
    widget.estimation.removeListener(_surTrajet);
    _motos.dispose();
    super.dispose();
  }

  LatLng get _pointDeRecherche => _depart ?? _moi ?? CarteCommande.centreDakar;

  Future<void> _localiserSansDemander() async {
    final position = await (widget.localiser ?? localiserAppareil)(demander: false);
    if (!mounted || position == null) return;
    setState(() => _moi = position);
    _surTrajet();
  }

  /// Le prix qui se calcule fait aussi réagir l'estimation : on ne
  /// rappelle le serveur que si le point de recherche a vraiment changé.
  void _surTrajet() {
    final point = _pointDeRecherche;
    if (point != _motos.centre) _motos.chercherAutour(point);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.estimation, _motos]),
      builder: (context, _) => Stack(
        children: [
          TripMap(
            depart: _depart,
            arrivee: _arrivee,
            centre: _moi,
            motos: _motos.motos,
            coucheFond: widget.coucheFond,
          ),
          Positioned(
            left: 10,
            top: 10,
            child: _PastilleMotos(motos: _motos.proximite, chargement: _motos.chargement),
          ),
        ],
      ),
    );
  }
}

class _PastilleMotos extends StatelessWidget {
  const _PastilleMotos({required this.motos, required this.chargement});

  final Proximite motos;
  final bool chargement;

  String get _texte {
    if (chargement) return 'Recherche des motos…';
    final n = motos.motos.length;
    if (n == 0) return 'Aucune moto à proximité pour le moment';
    final approche = motos.approcheMinutes == null ? '' : ' · ~${motos.approcheMinutes} min';
    return '${n == 1 ? '1 moto disponible' : '$n motos disponibles'}$approche';
  }

  @override
  Widget build(BuildContext context) {
    final aucune = !chargement && motos.motos.isEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 12, offset: Offset(0, 3))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: chargement || aucune ? AppColors.grey : AppColors.vert,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(_texte, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
