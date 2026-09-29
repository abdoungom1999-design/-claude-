import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/maps/distance_utils.dart';
import '../../../../core/maps/fond_carte.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/moto_vue_dessus.dart';
import '../../../courses/data/course_service.dart';
import '../../../courses/data/position_chauffeur.dart';

/// Carte de suivi côté client une fois la course acceptée : l'icône du
/// chauffeur se déplace en temps réel (position publiée par son
/// téléphone, voir `PositionChauffeurService`), avec un encart "Arrivée
/// dans ~X min" vers le point de prise en charge, puis vers la
/// destination une fois le client à bord.
///
/// La position est EXACTE (jamais arrondie) : le chauffeur d'une course
/// n'est plus une moto anonyme, son client le voit avancer en direct. Son
/// téléphone publie toutes les ~2 s pendant la course ; entre deux
/// positions, la moto glisse de l'ancienne à la nouvelle au lieu de sauter,
/// orientée dans le sens de la marche. La caméra ne bouge que quand il le
/// faut (chauffeur qui sort du cadre, ou qui s'approche : on zoome).
class SuiviApproche extends StatefulWidget {
  const SuiviApproche({
    super.key,
    required this.course,
    required this.positions,
    this.coucheFond,
    this.controleurCarte,
    this.horloge = DateTime.now,
  });

  final CourseFirestore course;

  /// Position du chauffeur attribué ; injectable pour les tests.
  final Stream<PositionChauffeurDirect?> positions;

  /// Fond de la carte ; par défaut [CoucheFondCarte]. Remplacé dans les tests.
  final Widget? coucheFond;

  /// Injectables pour les tests : contrôleur de la carte (pour lire la
  /// caméra) et horloge.
  final MapController? controleurCarte;
  final DateTime Function() horloge;

  @override
  State<SuiviApproche> createState() => _SuiviApprocheState();
}

class _SuiviApprocheState extends State<SuiviApproche> with SingleTickerProviderStateMixin {
  static const _centreDakar = LatLng(14.6928, -17.4467);

  late final MapController _carte = widget.controleurCarte ?? MapController();
  late final AnimationController _glissement =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..addListener(_redessiner);
  StreamSubscription<PositionChauffeurDirect?>? _abonnement;
  Timer? _horloge;

  /// Un chauffeur dont on n'a rien reçu depuis ce délai n'est plus "en direct".
  static const _delaiDirect = Duration(seconds: 15);

  PositionChauffeurDirect? _position;
  LatLng? _depuis;
  LatLng? _vers;
  DateTime? _recueLe;

  /// Cap de la moto en degrés, "déroulé" (peut dépasser 360) pour que la
  /// rotation prenne toujours le chemin le plus court.
  double? _cap;
  bool _dejaCadre = false;
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
    _horloge = Timer.periodic(const Duration(seconds: 5), (_) => _redessiner());
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
    // Linéaire : la moto roule à vitesse constante entre deux points.
    final t = _glissement.value;
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
    final maintenant = widget.horloge();
    setState(() {
      _premiereReception = true;
      _erreur = false;
      _position = position;
      if (position == null) return;
      final nouveau = LatLng(position.latitude, position.longitude);
      final ancien = _vers;
      _mettreAJourCap(ancien, nouveau, position);
      _depuis = _pointAffiche ?? nouveau;
      _vers = nouveau;
      // Le glissement dure autant que l'intervalle réel entre deux
      // positions : la moto arrive au nouveau point à l'instant où le
      // suivant est attendu, sans temps mort ni saccade.
      final recu = _recueLe;
      _glissement.duration = recu == null
          ? const Duration(milliseconds: 1200)
          : Duration(milliseconds: maintenant.difference(recu).inMilliseconds.clamp(800, 3000));
      _recueLe = maintenant;
    });
    if (position != null) {
      _glissement.forward(from: 0);
      _suivreCamera();
    }
  }

  /// Cap = sens du déplacement réel dès ~4 m parcourus (le GPS est
  /// imprécis en dessous) ; sinon le cap du GPS si le chauffeur roule ;
  /// sinon on garde le dernier (à l'arrêt, la moto ne pivote pas).
  void _mettreAJourCap(LatLng? ancien, LatLng nouveau, PositionChauffeurDirect position) {
    double? cible;
    if (ancien != null && _metresEntre(ancien, nouveau) >= 4) {
      cible = capEntre(ancien.latitude, ancien.longitude, nouveau.latitude, nouveau.longitude);
    } else if (_cap == null && position.cap != null && (position.vitesse ?? 0) > 1.5) {
      cible = position.cap;
    }
    if (cible == null) return;
    final courant = _cap;
    _cap = courant == null ? cible : courant + ((cible - courant + 540) % 360 - 180);
  }

  static double _metresEntre(LatLng a, LatLng b) => DistanceUtils.distanceKm(
        latDepart: a.latitude,
        lngDepart: a.longitude,
        latArrivee: b.latitude,
        lngArrivee: b.longitude,
      ) *
      1000;

  bool get _enDirect {
    final recu = _recueLe;
    final maintenant = widget.horloge();
    return recu != null &&
        maintenant.difference(recu) < _delaiDirect &&
        EtatSignal.pour(_position?.majLe, maintenant) == EtatSignal.actif;
  }

  CameraFit _ajustement(LatLng vers, LatLng cible) => CameraFit.coordinates(
        coordinates: [vers, cible],
        padding: const EdgeInsets.fromLTRB(50, 110, 50, 50),
        maxZoom: 16.5,
      );

  /// À chaque position : premier cadrage, puis on ne touche à la caméra que
  /// si le chauffeur (ou la cible) sort de la zone confortable de l'écran, ou
  /// si l'écart a tant changé qu'un autre zoom s'impose (il approche : on
  /// zoome). Jamais de recadrage à chaque point : la carte resterait
  /// secouée en permanence.
  void _suivreCamera() {
    if (!_carteChargee || _suiviManuel) return;
    final vers = _vers;
    if (vers == null) return;
    if (!_dejaCadre) {
      _cadrer();
      return;
    }
    final cible = _cible;
    final camera = _carte.camera;
    final visible = camera.visibleBounds;
    final hauteur = visible.north - visible.south;
    final largeur = visible.east - visible.west;
    // Un peu plus large que les marges du cadrage (bandeau d'info en haut
    // : 110 px sur 320) pour qu'un point cadré par [_cadrer] soit toujours
    // "confortable".
    bool confortable(LatLng p) =>
        p.latitude > visible.south + hauteur * 0.08 &&
        p.latitude < visible.north - hauteur * 0.30 &&
        p.longitude > visible.west + largeur * 0.06 &&
        p.longitude < visible.east - largeur * 0.06;
    if (!confortable(vers) || (cible != null && !confortable(cible))) {
      _cadrer();
      return;
    }
    if (cible == null) return;
    final ideal = _ajustement(vers, cible).fit(camera).zoom;
    if ((ideal - camera.zoom).abs() >= 1) _cadrer();
  }

  /// Cadre chauffeur + cible, sauf si le client a déplacé la carte.
  void _cadrer({bool force = false}) {
    if (!_carteChargee || (_suiviManuel && !force)) return;
    final vers = _vers;
    if (vers == null) return;
    _dejaCadre = true;
    final cible = _cible;
    if (cible == null) {
      _carte.move(vers, 15.5);
      return;
    }
    _carte.fitCamera(_ajustement(vers, cible));
  }

  @override
  Widget build(BuildContext context) {
    final maintenant = widget.horloge();
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
                widget.coucheFond ?? const CoucheFondCarte(),
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
                          key: const Key('marqueur-chauffeur'),
                          cap: _cap,
                          signalPerdu: EtatSignal.pour(_position?.majLe, maintenant) != EtatSignal.actif,
                        ),
                      ),
                  ],
                ),
                const MentionsFondCarte(),
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
            if (point != null)
              Positioned(
                left: 12,
                bottom: 28,
                child: BadgeDirect(enDirect: _enDirect),
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

/// La moto du chauffeur, vue de dessus, tournée dans le sens de la marche
/// (rotation adoucie entre deux caps), sur un halo blanc pour rester lisible
/// sur tous les fonds de carte. Grise quand le signal est perdu.
class _MarqueurChauffeur extends StatelessWidget {
  const _MarqueurChauffeur({super.key, required this.cap, required this.signalPerdu});

  final double? cap;
  final bool signalPerdu;

  @override
  Widget build(BuildContext context) {
    final couleur = signalPerdu ? AppColors.grey : AppColors.orange;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: couleur, width: 3),
        boxShadow: [BoxShadow(color: couleur.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 3))],
      ),
      alignment: Alignment.center,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: cap ?? 0),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOut,
        builder: (context, angle, _) => MotoVueDessus(
          cap: angle,
          taille: 30,
          couleur: couleur,
          libelle: 'Votre chauffeur',
        ),
      ),
    );
  }
}

/// "En direct" quand la position arrive en continu ; "Signal faible" si les
/// dernières nouvelles datent : le client sait s'il peut se fier à ce
/// qu'il voit.
class BadgeDirect extends StatefulWidget {
  const BadgeDirect({super.key, required this.enDirect});

  final bool enDirect;

  @override
  State<BadgeDirect> createState() => _BadgeDirectState();
}

class _BadgeDirectState extends State<BadgeDirect> with SingleTickerProviderStateMixin {
  late final AnimationController _pouls = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    if (widget.enDirect) _pouls.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant BadgeDirect ancien) {
    super.didUpdateWidget(ancien);
    if (widget.enDirect && !_pouls.isAnimating) {
      _pouls.repeat(reverse: true);
    } else if (!widget.enDirect && _pouls.isAnimating) {
      _pouls.stop();
    }
  }

  @override
  void dispose() {
    _pouls.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final couleur = widget.enDirect ? AppColors.vert : AppColors.grey;
    return Semantics(
      label: widget.enDirect ? 'Position en direct' : 'Signal faible',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FadeTransition(
              opacity: widget.enDirect ? Tween<double>(begin: 0.35, end: 1).animate(_pouls) : const AlwaysStoppedAnimation(1),
              child: Container(width: 9, height: 9, decoration: BoxDecoration(color: couleur, shape: BoxShape.circle)),
            ),
            const SizedBox(width: 7),
            Text(
              widget.enDirect ? 'En direct' : 'Signal faible',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: couleur),
            ),
          ],
        ),
      ),
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
