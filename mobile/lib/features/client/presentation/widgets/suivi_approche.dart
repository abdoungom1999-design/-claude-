import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../courses/data/course_service.dart';
import '../../../courses/data/position_chauffeur.dart';

/// Carte de suivi côté client une fois la course acceptée : l'icône du
/// chauffeur se déplace en temps réel (position publiée par son
/// téléphone, voir `PositionChauffeurService`), avec un encart "Arrivée
/// dans ~X min" vers le point de prise en charge, puis vers la
/// destination une fois le client à bord.
///
/// Entre deux positions (toutes les 5 s environ quand il roule), l'icône
/// glisse de l'ancienne à la nouvelle au lieu de sauter.
class SuiviApproche extends StatefulWidget {
  const SuiviApproche({super.key, required this.course, required this.positions});

  final CourseFirestore course;

  /// Position du chauffeur attribué ; injectable pour les tests.
  final Stream<PositionChauffeurDirect?> positions;

  @override
  State<SuiviApproche> createState() => _SuiviApprocheState();
}

class _SuiviApprocheState extends State<SuiviApproche> with SingleTickerProviderStateMixin {
  static const _centreDakar = LatLng(14.6928, -17.4467);

  final _carte = MapController();
  late final AnimationController _glissement =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..addListener(_redessiner);
  StreamSubscription<PositionChauffeurDirect?>? _abonnement;
  Timer? _horloge;

  PositionChauffeurDirect? _position;
  LatLng? _depuis;
  LatLng? _vers;
  bool _premiereReception = false;
  bool _erreur = false;
  bool _suiviManuel = false;
  bool _carteChargee = false;

  @override
  void initState() {
    super.initState();
    _abonnement = widget.positions.listen(
      _surPosition,
      onError: (_) {
        if (mounted) setState(() => _erreur = true);
      },
    );
    // Rafraîchit "signal perdu" même si plus rien n'arrive.
    _horloge = Timer.periodic(const Duration(seconds: 15), (_) => _redessiner());
  }

  @override
  void didUpdateWidget(covariant SuiviApproche oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Client à bord : la cible devient la destination, on recadre.
    if (oldWidget.course.statut != widget.course.statut) {
      _suiviManuel = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _cadrer(force: true));
    }
  }

  @override
  void dispose() {
    _abonnement?.cancel();
    _horloge?.cancel();
    _glissement.dispose();
    super.dispose();
  }

  void _redessiner() {
    if (mounted) setState(() {});
  }

  LatLng? get _pointAffiche {
    final depuis = _depuis;
    final vers = _vers;
    if (vers == null) return null;
    if (depuis == null) return vers;
    final t = Curves.easeInOut.transform(_glissement.value);
    return LatLng(
      depuis.latitude + (vers.latitude - depuis.latitude) * t,
      depuis.longitude + (vers.longitude - depuis.longitude) * t,
    );
  }

  /// Point visé par le chauffeur : le client (approche), puis la
  /// destination (client à bord).
  LatLng? get _cible {
    final points = widget.course.points;
    if (points == null) return null;
    return widget.course.statut == StatutCourse.enCours
        ? LatLng(points.latitudeArrivee, points.longitudeArrivee)
        : LatLng(points.latitudeDepart, points.longitudeDepart);
  }

  void _surPosition(PositionChauffeurDirect? position) {
    if (!mounted) return;
    setState(() {
      _premiereReception = true;
      _erreur = false;
      _position = position;
      if (position == null) return;
      final nouveau = LatLng(position.latitude, position.longitude);
      _depuis = _pointAffiche ?? nouveau;
      _vers = nouveau;
    });
    if (position != null) {
      _glissement.forward(from: 0);
      _cadrer();
    }
  }

  /// Cadre chauffeur + cible, sauf si le client a déplacé la carte.
  void _cadrer({bool force = false}) {
    if (!_carteChargee || (_suiviManuel && !force)) return;
    final vers = _vers;
    if (vers == null) return;
    final cible = _cible;
    if (cible == null) {
      _carte.move(vers, 15.5);
      return;
    }
    _carte.fitCamera(
      CameraFit.coordinates(
        coordinates: [vers, cible],
        padding: const EdgeInsets.fromLTRB(50, 110, 50, 50),
        maxZoom: 16.5,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maintenant = DateTime.now();
    final point = _pointAffiche;
    final cible = _cible;
    final clientABord = widget.course.statut == StatutCourse.enCours;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 320,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _carte,
              options: MapOptions(
                initialCenter: cible ?? _centreDakar,
                initialZoom: 14,
                onMapReady: () {
                  _carteChargee = true;
                  _cadrer();
                },
                onPositionChanged: (_, geste) {
                  if (geste && !_suiviManuel) setState(() => _suiviManuel = true);
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'sn.groupesantine.sprint',
                ),
                MarkerLayer(
                  markers: [
                    if (cible != null)
                      Marker(
                        point: cible,
                        width: 40,
                        height: 40,
                        // Pointe du repère sur le point exact.
                        alignment: Alignment.topCenter,
                        child: _MarqueurCible(destination: clientABord),
                      ),
                    if (point != null)
                      Marker(
                        point: point,
                        width: 48,
                        height: 48,
                        child: _MarqueurChauffeur(
                          signalPerdu: EtatSignal.pour(_position?.majLe, maintenant) != EtatSignal.actif,
                        ),
                      ),
                  ],
                ),
                const RichAttributionWidget(
                  attributions: [TextSourceAttribution('© OpenStreetMap contributors')],
                ),
              ],
            ),
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: EncartApproche(
                statutCourse: widget.course.statut,
                position: _position,
                cible: cible,
                enAttente: !_premiereReception,
                erreur: _erreur,
                maintenant: maintenant,
              ),
            ),
            if (_suiviManuel && point != null)
              Positioned(
                right: 12,
                bottom: 28,
                child: FloatingActionButton.small(
                  heroTag: null,
                  tooltip: 'Recentrer',
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.orange,
                  onPressed: () {
                    setState(() => _suiviManuel = false);
                    _cadrer(force: true);
                  },
                  child: const Icon(Icons.my_location_rounded),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Encart du temps d'attente estimé, posé en haut de la carte.
class EncartApproche extends StatelessWidget {
  const EncartApproche({
    super.key,
    required this.statutCourse,
    required this.position,
    required this.cible,
    required this.enAttente,
    required this.erreur,
    required this.maintenant,
  });

  final String statutCourse;
  final PositionChauffeurDirect? position;
  final LatLng? cible;
  final bool enAttente;
  final bool erreur;
  final DateTime maintenant;

  @override
  Widget build(BuildContext context) {
    final clientABord = statutCourse == StatutCourse.enCours;
    final (IconData icone, Color couleur, String titre, String? detail) = _contenu(clientABord);

    return Material(
      color: Colors.white,
      elevation: 4,
      shadowColor: AppColors.shadow,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: couleur.withValues(alpha: 0.12), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: enAttente && !erreur
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: couleur),
                    )
                  : Icon(icone, color: couleur, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(titre, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  if (detail != null) ...[
                    const SizedBox(height: 2),
                    Text(detail, style: const TextStyle(fontSize: 12, color: AppColors.grey)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  (IconData, Color, String, String?) _contenu(bool clientABord) {
    if (erreur) {
      return (Icons.location_off_outlined, AppColors.grey, 'Suivi indisponible', 'Votre chauffeur reste joignable par appel ou message.');
    }
    final position = this.position;
    if (enAttente || position == null) {
      return (
        Icons.two_wheeler_rounded,
        AppColors.orange,
        'Localisation du chauffeur…',
        'Sa position apparaîtra dès qu\'il partage son GPS.',
      );
    }
    if (EtatSignal.pour(position.majLe, maintenant) != EtatSignal.actif) {
      return (
        Icons.signal_wifi_off_rounded,
        AppColors.grey,
        'Position non mise à jour',
        'Dernière position reçue ${ilYA(position.majLe, maintenant)}.',
      );
    }
    final cible = this.cible;
    if (cible == null) {
      return (Icons.two_wheeler_rounded, AppColors.orange, clientABord ? 'Course en cours' : 'Votre chauffeur est en route', null);
    }
    final approche = Approche.estimer(
      latChauffeur: position.latitude,
      lngChauffeur: position.longitude,
      latCible: cible.latitude,
      lngCible: cible.longitude,
    );
    final distance = approche.distanceKm < 1
        ? '${(approche.distanceKm * 1000).round()} m'
        : '${approche.distanceKm.toStringAsFixed(1).replaceAll('.', ',')} km';
    if (approche.arrive) {
      return clientABord
          ? (Icons.flag_rounded, AppColors.vert, 'Vous êtes arrivé', null)
          : (Icons.check_circle_rounded, AppColors.vert, 'Votre chauffeur est arrivé', 'Il vous attend au point de départ.');
    }
    return (
      Icons.schedule_rounded,
      AppColors.orange,
      clientABord ? 'Arrivée dans ~${approche.minutes} min' : 'Votre chauffeur arrive dans ~${approche.minutes} min',
      clientABord ? 'Encore $distance jusqu\'à destination' : 'À $distance de vous',
    );
  }
}

class _MarqueurChauffeur extends StatelessWidget {
  const _MarqueurChauffeur({required this.signalPerdu});

  final bool signalPerdu;

  @override
  Widget build(BuildContext context) {
    final couleur = signalPerdu ? AppColors.grey : AppColors.orange;
    return Container(
      decoration: BoxDecoration(
        color: couleur,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [BoxShadow(color: couleur.withValues(alpha: 0.45), blurRadius: 12, offset: const Offset(0, 3))],
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.two_wheeler_rounded, color: Colors.white, size: 22),
    );
  }
}

class _MarqueurCible extends StatelessWidget {
  const _MarqueurCible({required this.destination});

  final bool destination;

  @override
  Widget build(BuildContext context) {
    return Icon(
      destination ? Icons.location_on_rounded : Icons.person_pin_circle_rounded,
      color: destination ? AppColors.orangeDark : AppColors.vert,
      size: 40,
    );
  }
}
