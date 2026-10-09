import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/maps/distance_utils.dart';
import '../../../core/maps/trace_utils.dart';
import '../../courses/data/course_service.dart';
import '../../courses/data/itineraire_service.dart';
import '../../courses/data/position_chauffeur.dart';

/// Ce que le guidage peut afficher au chauffeur.
enum EtatGuidage {
  /// La course n'a pas de coordonnées (course d'avant leur enregistrement) :
  /// rien à guider, le chauffeur appelle son client.
  sansPointVise,

  /// La course ne porte que le départ arrondi du client (sa zone, ~150 m) : sa
  /// position exacte, lue à part, n'est pas encore arrivée.
  attentePointClient,

  /// Le téléphone n'a pas encore donné la position du chauffeur.
  attentePosition,

  /// Position connue, itinéraire en cours de calcul.
  calcul,

  /// Itinéraire (ou, à défaut, estimation à vol d'oiseau) disponible.
  pret,
}

/// Guide un chauffeur vers le point de rendez-vous de sa course : le client
/// tant que la course est acceptée, puis la destination une fois le client à
/// bord. Tient à jour, à chaque position du chauffeur, le tracé qui reste, la
/// distance et le temps d'approche.
///
/// Le serveur ne calcule l'itinéraire qu'à de rares occasions : à
/// l'acceptation, au changement de point visé, puis seulement si le chauffeur
/// quitte son itinéraire (écart de plus de [ecartMaxM]). Entre deux calculs, le
/// reste à parcourir est déduit de la position sur le tracé, sans appel. Si le
/// serveur ne répond pas, le guidage retombe sur une estimation à vol d'oiseau
/// (ligne droite) et réessaie de temps en temps ; il ne dégrade jamais un
/// itinéraire déjà obtenu.
class GuidageController extends ChangeNotifier {
  GuidageController({
    required CourseFirestore course,
    required Stream<PositionChauffeurDirect> positions,
    required ServiceItineraire service,
    PositionChauffeurDirect? positionInitiale,
    DateTime Function() horloge = DateTime.now,
  })  : _course = course,
        _service = service,
        _horloge = horloge,
        _position = positionInitiale {
    _abonnement = positions.listen(_surPosition, onError: (_) {});
    if (positionInitiale != null) _mettreAJourCap(null, positionInitiale);
    _demanderSiUtile();
  }

  /// Au-delà de cet écart avec le tracé, le chauffeur a quitté son itinéraire.
  static const ecartMaxM = 120.0;

  /// Délai minimal entre deux calculs quand le chauffeur a quitté son itinéraire.
  static const delaiRecalcul = Duration(seconds: 20);

  /// Délai avant de réessayer après un calcul qui n'a pas abouti.
  static const delaiNouvelEssai = Duration(seconds: 20);

  /// En dessous, le chauffeur est arrivé.
  static const distanceArriveeM = 40.0;

  /// Moto-taxi en ville, comme pour l'attente affichée au client.
  static const vitesseKmh = Approche.vitesseMoyenneKmh;

  final ServiceItineraire _service;
  final DateTime Function() _horloge;
  late final StreamSubscription<PositionChauffeurDirect> _abonnement;

  CourseFirestore _course;
  PositionChauffeurDirect? _position;
  Itineraire? _itineraire;
  ProjectionTrace? _projection;
  int _segment = 0;
  double? _cap;
  DateTime? _dernierEssai;
  DateTime? _prochainEssai;
  int _numeroDemande = 0;
  int? _demandeEnCours;
  bool _ferme = false;

  CourseFirestore get course => _course;

  /// La course est en cours : on guide vers la destination, pas vers le client.
  bool get versDestination => _course.statut == StatutCourse.enCours;

  /// Il faut rejoindre le client, mais la course ne porte que le départ arrondi
  /// de sa position : tant que sa position exacte n'est pas arrivée
  /// ([CourseFirestore.departArrondi]), on ne guide pas vers ce point
  /// approximatif.
  bool get pointApproximatif => !versDestination && _course.points != null && _course.departArrondi;

  /// Point visé : le client, puis la destination ; `null` sans coordonnées, et
  /// tant que la position exacte du client n'est pas arrivée.
  LatLng? get cible {
    final points = _course.points;
    if (points == null) return null;
    if (versDestination) return LatLng(points.latitudeArrivee, points.longitudeArrivee);
    return pointApproximatif ? null : LatLng(points.latitudeDepart, points.longitudeDepart);
  }

  /// Centre de la zone où se trouve le client tant que sa position exacte n'est
  /// pas arrivée ; `null` sinon.
  LatLng? get zoneClient {
    final points = _course.points;
    if (points == null || !pointApproximatif) return null;
    return LatLng(points.latitudeDepart, points.longitudeDepart);
  }

  /// Ce que la carte cadre : le point visé, ou, en attendant, la zone du client.
  LatLng? get pointCarte => cible ?? zoneClient;

  PositionChauffeurDirect? get position => _position;

  LatLng? get _positionLatLng {
    final p = _position;
    return p == null ? null : LatLng(p.latitude, p.longitude);
  }

  LatLng? get positionChauffeur => _positionLatLng;

  /// Direction de la moto en degrés (0 = nord), déroulée : la rotation prend
  /// toujours le chemin le plus court.
  double? get cap => _cap;

  EtatGuidage get etat {
    if (_course.points == null) return EtatGuidage.sansPointVise;
    if (pointApproximatif) return EtatGuidage.attentePointClient;
    if (_position == null) return EtatGuidage.attentePosition;
    if (_itineraire == null) return EtatGuidage.calcul;
    return EtatGuidage.pret;
  }

  /// Le tracé affiché n'est qu'une ligne droite : le calcul d'itinéraire n'a pas répondu.
  bool get estimation => _itineraire?.estime ?? false;

  /// Tracé qui reste à parcourir, du chauffeur au point visé ; vide tant que
  /// l'itinéraire n'est pas connu.
  List<LatLng> get traceRestante {
    final itineraire = _itineraire;
    final moi = _positionLatLng;
    final point = cible;
    if (itineraire == null || moi == null || point == null) return const [];
    if (itineraire.estime) return [moi, point];
    final projection = _projection;
    if (projection == null) return [moi, ...itineraire.trace];
    // Un court segment relie le chauffeur au tracé : où le rejoindre.
    return [moi, ...TraceUtils.restant(itineraire.trace, projection)];
  }

  /// Distance qu'il reste à parcourir, en mètres ; `null` tant qu'elle n'est pas connue.
  double? get resteM {
    final itineraire = _itineraire;
    final moi = _positionLatLng;
    final point = cible;
    if (itineraire == null || moi == null || point == null) return null;
    if (itineraire.estime) {
      return DistanceUtils.distanceRouteEstimeeKm(
            latDepart: moi.latitude,
            lngDepart: moi.longitude,
            latArrivee: point.latitude,
            lngArrivee: point.longitude,
          ) *
          1000;
    }
    final projection = _projection;
    return projection == null ? itineraire.distanceM : projection.resteM + projection.ecartM;
  }

  /// Temps d'approche estimé, en minutes (au moins 1).
  int? get minutes {
    final reste = resteM;
    if (reste == null) return null;
    final minutes = (reste / 1000 / vitesseKmh * 60).ceil();
    return minutes < 1 ? 1 : minutes;
  }

  bool get arrive {
    final reste = resteM;
    return reste != null && reste < distanceArriveeM;
  }

  bool get _enDemande => _demandeEnCours != null;

  /// À appeler à chaque nouvelle version de la course (Firestore) : un changement
  /// de point visé (client à bord) relance le calcul.
  void mettreAJourCourse(CourseFirestore course) {
    if (_ferme) return;
    final avant = cible;
    final idAvant = _course.id;
    _course = course;
    if (course.id != idAvant || cible != avant) {
      _itineraire = null;
      _projection = null;
      _segment = 0;
      _prochainEssai = null;
      _dernierEssai = null;
      // Une réponse encore attendue concerne l'ancien point visé : elle sera ignorée.
      _demandeEnCours = null;
      _demanderSiUtile();
    }
    notifyListeners();
  }

  void _surPosition(PositionChauffeurDirect nouvelle) {
    if (_ferme) return;
    _mettreAJourCap(_position, nouvelle);
    _position = nouvelle;
    _projeter();
    _demanderSiUtile();
    notifyListeners();
  }

  /// Direction : celle du GPS quand le chauffeur roule, sinon celle de son
  /// déplacement (dès ~4 m), sinon vers le point visé pour l'orientation de départ.
  void _mettreAJourCap(PositionChauffeurDirect? ancienne, PositionChauffeurDirect nouvelle) {
    double? voulu;
    if (nouvelle.cap != null && (nouvelle.vitesse ?? 0) > 1.5) {
      voulu = nouvelle.cap;
    } else if (ancienne != null &&
        TraceUtils.distanceM(
                LatLng(ancienne.latitude, ancienne.longitude), LatLng(nouvelle.latitude, nouvelle.longitude)) >=
            4) {
      voulu = capEntre(ancienne.latitude, ancienne.longitude, nouvelle.latitude, nouvelle.longitude);
    } else if (_cap == null) {
      final point = pointCarte;
      if (point != null) voulu = capEntre(nouvelle.latitude, nouvelle.longitude, point.latitude, point.longitude);
    }
    if (voulu == null) return;
    final courant = _cap;
    _cap = courant == null ? voulu : courant + ((voulu - courant + 540) % 360 - 180);
  }

  void _projeter() {
    final itineraire = _itineraire;
    final moi = _positionLatLng;
    if (itineraire == null || itineraire.estime || moi == null) {
      _projection = null;
      return;
    }
    final projection = TraceUtils.projeter(itineraire.trace, moi, depuisSegment: _segment);
    _projection = projection;
    if (projection != null) _segment = projection.segment;
  }

  /// Demande un itinéraire au serveur quand c'est utile : au premier calcul,
  /// pour remplacer une simple estimation, ou quand le chauffeur a quitté son
  /// itinéraire. Jamais deux demandes à la fois, jamais plus vite que les délais.
  void _demanderSiUtile() {
    if (_ferme || _enDemande) return;
    final moi = _positionLatLng;
    final point = cible;
    if (moi == null || point == null) return;
    final maintenant = _horloge();
    final prochain = _prochainEssai;
    if (prochain != null && maintenant.isBefore(prochain)) return;

    final itineraire = _itineraire;
    final dernier = _dernierEssai;
    final aQuitteSonItineraire =
        (_projection?.ecartM ?? 0) > ecartMaxM && (dernier == null || maintenant.difference(dernier) >= delaiRecalcul);
    if (itineraire == null || itineraire.estime || aQuitteSonItineraire) {
      unawaited(_demander(moi, point, maintenant));
    }
  }

  Future<void> _demander(LatLng depuis, LatLng vers, DateTime maintenant) async {
    final numero = ++_numeroDemande;
    _demandeEnCours = numero;
    _dernierEssai = maintenant;
    Itineraire? resultat;
    try {
      resultat = await _service.calculer(courseId: _course.id, depuis: depuis, vers: vers);
    } on Object catch (e) {
      debugPrint('Itinéraire indisponible : $e');
    }
    // Point visé changé entre-temps, ou écran fermé : cette réponse ne sert plus.
    if (_ferme || numero != _demandeEnCours) return;
    _demandeEnCours = null;
    if (resultat != null) {
      _itineraire = resultat;
      _segment = 0;
      _prochainEssai = null;
      _projeter();
    } else {
      _prochainEssai = _horloge().add(delaiNouvelEssai);
      // Jamais de retour en arrière : un vrai itinéraire déjà obtenu est conservé.
      _itineraire ??= Itineraire.estimation(depuis, vers);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _ferme = true;
    _abonnement.cancel();
    super.dispose();
  }
}
