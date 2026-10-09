import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/maps/fond_carte.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/moto_vue_dessus.dart';
import '../../../../core/widgets/onyx_vert.dart';
import '../../../courses/data/course_service.dart';
import '../../../courses/data/itineraire_service.dart';
import '../../../courses/data/position_chauffeur.dart';
import '../../data/guidage_controller.dart';

/// Écran de guidage du chauffeur dès qu'il a accepté une course : sa carte
/// montre où est son client (repère au point GPS exact du rendez-vous), où il
/// est lui-même, l'itinéraire pour le rejoindre, et dessus la distance et le
/// temps d'approche. Une fois le client à bord, le même écran guide vers la
/// destination.
///
/// Tout est calculé par [GuidageController] : l'itinéraire vient du serveur
/// (une fois, puis seulement si le chauffeur quitte sa route), le reste à
/// parcourir se déduit de sa position sur le tracé. Si le serveur ne répond pas,
/// une ligne droite en pointillés et une estimation prennent le relais.
class GuidageCourse extends StatefulWidget {
  const GuidageCourse({
    super.key,
    required this.course,
    required this.positions,
    required this.service,
    this.positionInitiale,
    this.coucheFond,
    this.controleurCarte,
    this.horloge = DateTime.now,
  });

  final CourseFirestore course;

  /// Position du chauffeur à chaque relevé GPS ; injectable pour les tests.
  final Stream<PositionChauffeurDirect> positions;

  /// Dernier relevé connu au moment d'ouvrir l'écran (le GPS n'en donne un
  /// nouveau qu'au prochain déplacement).
  final PositionChauffeurDirect? positionInitiale;
  final ServiceItineraire service;

  /// Fond de la carte ; par défaut [CoucheFondCarte]. Remplacé dans les tests.
  final Widget? coucheFond;

  /// Injectables pour les tests : contrôleur de la carte (pour lire la caméra) et horloge.
  final MapController? controleurCarte;
  final DateTime Function() horloge;

  @override
  State<GuidageCourse> createState() => _GuidageCourseState();
}

class _GuidageCourseState extends State<GuidageCourse> {
  static const _centreDakar = LatLng(14.6928, -17.4467);

  /// Rayon de la zone montrée tant que la position exacte du client n'est pas
  /// arrivée : le départ est arrondi au centre d'une case d'environ 150 m, le
  /// client est donc à 106 m au plus du centre (la demi-diagonale).
  static const _rayonZoneM = 110.0;

  late final GuidageController _guidage;
  late final MapController _carte;

  bool _carteChargee = false;
  bool _dejaCadre = false;

  /// Cadrage de départ, quand on connaît déjà la position du chauffeur : la
  /// carte s'ouvre directement dessus. Changer la caméra dès l'ouverture, par
  /// programme, laisse le fond de carte vide (aucune image n'est affichée).
  CameraFit? _cadrageInitial;

  /// Le chauffeur a déplacé la carte lui-même : on ne la recadre plus tant
  /// qu'il n'a pas touché « Recentrer ».
  bool _suiviManuel = false;

  @override
  void initState() {
    super.initState();
    _carte = widget.controleurCarte ?? MapController();
    _guidage = GuidageController(
      course: widget.course,
      positions: widget.positions,
      positionInitiale: widget.positionInitiale,
      service: widget.service,
      horloge: widget.horloge,
    )..addListener(_surChangement);
    final moi = _guidage.positionChauffeur;
    final vise = _guidage.pointCarte;
    if (moi != null && vise != null) {
      _cadrageInitial = _ajustement(moi, vise);
      _dejaCadre = true;
    }
  }

  @override
  void didUpdateWidget(covariant GuidageCourse ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.course == widget.course) return;
    final versDestinationAvant = _guidage.versDestination;
    _guidage.mettreAJourCourse(widget.course);
    // Client à bord : la carte se recadre sur la destination.
    if (_guidage.versDestination != versDestinationAvant) {
      _suiviManuel = false;
      _dejaCadre = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _cadrer(force: true));
    }
  }

  @override
  void dispose() {
    _guidage
      ..removeListener(_surChangement)
      ..dispose();
    super.dispose();
  }

  void _surChangement() {
    if (!mounted) return;
    setState(() {});
    _suivreCamera();
  }

  CameraFit _ajustement(LatLng moi, LatLng cible) => CameraFit.coordinates(
        coordinates: [moi, cible],
        // Haut : la carte d'information ; bas : le bandeau de la course, déjà hors de la carte.
        padding: const EdgeInsets.fromLTRB(48, 210, 48, 64),
        maxZoom: 17,
      );

  /// À chaque position : premier cadrage, puis on ne touche à la caméra que si
  /// le chauffeur (ou le point visé) sort de la zone confortable de l'écran ou
  /// si l'écart a tant changé qu'un autre zoom s'impose. Jamais de recadrage à
  /// chaque point : la carte resterait secouée en permanence.
  void _suivreCamera() {
    if (!_carteChargee || _suiviManuel) return;
    final moi = _guidage.positionChauffeur;
    if (moi == null) return;
    if (!_dejaCadre) {
      _cadrer();
      return;
    }
    final cible = _guidage.pointCarte;
    final camera = _carte.camera;
    final visible = camera.visibleBounds;
    final hauteur = visible.north - visible.south;
    final largeur = visible.east - visible.west;
    bool confortable(LatLng p) =>
        p.latitude > visible.south + hauteur * 0.08 &&
        p.latitude < visible.north - hauteur * 0.32 &&
        p.longitude > visible.west + largeur * 0.06 &&
        p.longitude < visible.east - largeur * 0.06;
    if (!confortable(moi) || (cible != null && !confortable(cible))) {
      _cadrer();
      return;
    }
    if (cible == null) return;
    final ideal = _ajustement(moi, cible).fit(camera).zoom;
    if ((ideal - camera.zoom).abs() >= 1) _cadrer();
  }

  /// Cadre le chauffeur et le point visé, sauf si le chauffeur a déplacé la carte.
  void _cadrer({bool force = false}) {
    if (!_carteChargee || (_suiviManuel && !force)) return;
    final moi = _guidage.positionChauffeur;
    final cible = _guidage.pointCarte;
    // Sans position du chauffeur, la carte est déjà ouverte sur le point visé.
    if (moi == null) return;
    _dejaCadre = true;
    if (cible == null) {
      _carte.move(moi, 16);
    } else {
      _carte.fitCamera(_ajustement(moi, cible));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cible = _guidage.cible;
    final zone = _guidage.zoneClient;
    final moi = _guidage.positionChauffeur;
    final trace = _guidage.traceRestante;

    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          mapController: _carte,
          options: MapOptions(
            initialCenter: _guidage.pointCarte ?? moi ?? _centreDakar,
            initialZoom: 16,
            initialCameraFit: _cadrageInitial,
            // Fond sombre pendant le chargement des images (sinon le gris clair par défaut de flutter_map).
            backgroundColor: AppColors.fondHaut,
            // Pas de rotation : la moto est orientée selon le nord.
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            onMapReady: () {
              _carteChargee = true;
              // Déjà cadrée à l'ouverture si on connaissait la position du chauffeur.
              if (_cadrageInitial == null) _cadrer();
            },
            onPositionChanged: (_, geste) {
              if (geste && !_suiviManuel) setState(() => _suiviManuel = true);
            },
          ),
          children: [
            widget.coucheFond ?? const CoucheFondCarte(),
            if (trace.length >= 2)
              PolylineLayer(
                polylines: [
                  // Trait vert cerné d'Onyx, lisible sur une carte claire comme sombre ;
                  // en pointillés quand ce n'est qu'une estimation en ligne droite.
                  Polyline(
                    points: trace,
                    color: AppColors.vert,
                    strokeWidth: 5,
                    borderColor: AppColors.onyx,
                    borderStrokeWidth: 2,
                    pattern: _guidage.estimation
                        ? StrokePattern.dashed(segments: const [12, 10])
                        : const StrokePattern.solid(),
                  ),
                ],
              ),
            // Position exacte du client pas encore arrivée : seule sa zone est connue.
            if (zone != null)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: zone,
                    radius: _rayonZoneM,
                    useRadiusInMeter: true,
                    color: AppColors.vert.withValues(alpha: 0.18),
                    borderColor: AppColors.vert,
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                if (cible != null)
                  Marker(
                    point: cible,
                    width: 52,
                    height: 52,
                    // Pointe du repère sur le point exact.
                    alignment: Alignment.topCenter,
                    child:
                        _RepereRendezVous(key: const Key('repere-rendez-vous'), destination: _guidage.versDestination),
                  ),
                if (moi != null)
                  Marker(
                    point: moi,
                    width: 48,
                    height: 48,
                    child: _MarqueurMoto(key: const Key('marqueur-moto-chauffeur'), cap: _guidage.cap),
                  ),
              ],
            ),
            const MentionsFondCarte(),
          ],
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _CarteGuidage(guidage: _guidage),
            ),
          ),
        ),
        if (_suiviManuel && moi != null)
          SafeArea(
            child: Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 16, 16),
                child: FloatingActionButton.small(
                  heroTag: null,
                  tooltip: 'Recentrer',
                  backgroundColor: AppColors.fond.withValues(alpha: 0.92),
                  foregroundColor: AppColors.vert,
                  onPressed: () {
                    setState(() => _suiviManuel = false);
                    _cadrer(force: true);
                  },
                  child: const Icon(Icons.my_location_rounded),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Carte d'information en haut de l'écran : où l'on va, et la distance et le
/// temps d'approche (ou ce qui manque pour les donner).
class _CarteGuidage extends StatelessWidget {
  const _CarteGuidage({required this.guidage});

  final GuidageController guidage;

  /// "850 m", "1,8 km".
  static String _distance(double metres) => metres < 1000
      ? '${(metres / 10).round() * 10} m'
      : '${(metres / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';

  String get _titre {
    final colis = guidage.course.type == 'COLIS';
    if (guidage.versDestination) return colis ? 'Vers le lieu de livraison' : 'Vers la destination';
    return colis ? 'Récupérez le colis' : 'Rejoignez votre client';
  }

  String get _adresse => guidage.versDestination ? guidage.course.adresseArrivee : guidage.course.adresseDepart;

  @override
  Widget build(BuildContext context) {
    final etat = guidage.etat;
    final reste = guidage.resteM;
    final minutes = guidage.minutes;
    final arrive = guidage.arrive;

    final (Widget icone, String metrique, String detail) = switch (etat) {
      EtatGuidage.sansPointVise => (
          const Icon(Icons.location_off_outlined, color: AppColors.texteDiscret, size: 22),
          'Point de rendez-vous inconnu',
          'Appelez ou écrivez au client pour le retrouver.',
        ),
      EtatGuidage.attentePointClient => (
          const _Attente(),
          'Position exacte du client…',
          'Zone approximative sur la carte.',
        ),
      EtatGuidage.attentePosition => (const _Attente(), 'Localisation de votre position…', _adresse),
      EtatGuidage.calcul => (const _Attente(), "Calcul de l'itinéraire…", _adresse),
      EtatGuidage.pret when arrive => (
          const Icon(Icons.check_circle_rounded, color: AppColors.vert, size: 24),
          guidage.versDestination ? 'Vous êtes arrivé' : 'Vous êtes au rendez-vous',
          guidage.versDestination ? 'Vous êtes à destination.' : 'Votre client est tout près.',
        ),
      EtatGuidage.pret => (
          Icon(
            guidage.versDestination ? Icons.flag_rounded : Icons.person_pin_circle_rounded,
            color: AppColors.vert,
            size: 24,
          ),
          '${guidage.estimation ? '≈ ' : ''}${_distance(reste!)} · ~$minutes min',
          _adresse,
        ),
    };

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: CarteVerre(
        sombre: true,
        rayon: 24,
        padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
        child: Semantics(
          container: true,
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: AppColors.vertTeinte, borderRadius: BorderRadius.circular(14)),
                alignment: Alignment.center,
                child: icone,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _titre,
                      style: const TextStyle(color: AppColors.vert, fontSize: 12.5, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      metrique,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.texte,
                        fontSize: etat == EtatGuidage.pret && !arrive ? 21 : 15,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: AppColors.texteDiscret, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    if (guidage.estimation && etat == EtatGuidage.pret && !arrive) ...[
                      const SizedBox(height: 2),
                      const Text(
                        'Estimation à vol d\'oiseau : itinéraire indisponible.',
                        style: TextStyle(color: AppColors.texteDiscret, fontSize: 11.5),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Attente extends StatelessWidget {
  const _Attente();

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.vert),
      );
}

/// Repère du rendez-vous : le client (puis la destination), cerné d'Onyx pour
/// rester lisible sur n'importe quel fond de carte. Sa pointe est sur le point exact.
class _RepereRendezVous extends StatelessWidget {
  const _RepereRendezVous({super.key, required this.destination});

  final bool destination;

  @override
  Widget build(BuildContext context) {
    final icone = destination ? Icons.flag_circle_rounded : Icons.person_pin_circle_rounded;
    return Semantics(
      label: destination ? 'Destination' : 'Position du client',
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Icon(icone, color: AppColors.onyx, size: 52),
          Icon(icone, color: AppColors.vert, size: 44),
        ],
      ),
    );
  }
}

/// La moto du chauffeur, vue de dessus, tournée dans le sens de la marche
/// (rotation adoucie entre deux caps), sur un halo blanc cerné de vert.
class _MarqueurMoto extends StatelessWidget {
  const _MarqueurMoto({super.key, required this.cap});

  final double? cap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.vert, width: 3),
        boxShadow: [
          BoxShadow(color: AppColors.vert.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 3))
        ],
      ),
      alignment: Alignment.center,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: cap ?? 0),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOut,
        builder: (context, angle, _) => MotoVueDessus(cap: angle, taille: 30, libelle: 'Votre position'),
      ),
    );
  }
}
