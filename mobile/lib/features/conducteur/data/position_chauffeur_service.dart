import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/location/maintien_ecran.dart';

/// Rythme d'envoi de la position : au plus un envoi toutes les
/// [intervalleMin] quand le chauffeur roule, et au moins un toutes les
/// [battementCoeur] même immobile, pour que l'Admin distingue un
/// chauffeur à l'arrêt d'un chauffeur dont le signal est perdu.
class LimiteurEnvoiPosition {
  LimiteurEnvoiPosition({
    this.intervalleMin = const Duration(seconds: 5),
    this.battementCoeur = const Duration(seconds: 30),
  });

  final Duration intervalleMin;
  final Duration battementCoeur;
  DateTime? _dernierEnvoi;

  bool peutEnvoyer(DateTime maintenant) => _ecoule(maintenant, intervalleMin);

  bool battementDu(DateTime maintenant) => _ecoule(maintenant, battementCoeur);

  void enregistrerEnvoi(DateTime maintenant) => _dernierEnvoi = maintenant;

  void reinitialiser() => _dernierEnvoi = null;

  bool _ecoule(DateTime maintenant, Duration delai) =>
      _dernierEnvoi == null || maintenant.difference(_dernierEnvoi!) >= delai;
}

/// Publie en temps réel la position GPS du chauffeur en ligne dans
/// `positions_chauffeurs/{uid}` (lue par la carte "Courses en direct" de
/// l'Admin, et par personne d'autre : voir `firestore.rules`).
///
/// Suit le GPS en continu ([Geolocator.getPositionStream]) plutôt que de
/// l'interroger à intervalle fixe, avec un envoi limité par
/// [LimiteurEnvoiPosition]. Le document est supprimé au passage hors
/// ligne : aucun historique de trajets n'est conservé.
///
/// Limite de la version web : le navigateur suspend la géolocalisation
/// quand l'écran est verrouillé ou l'onglet en arrière-plan. L'écran est
/// donc maintenu allumé ([MaintienEcran]) ; un vrai suivi en arrière-plan
/// exigera l'application Android native.
class PositionChauffeurService {
  static const collection = 'positions_chauffeurs';

  final _limiteur = LimiteurEnvoiPosition();
  final _maintienEcran = MaintienEcran();
  StreamSubscription<Position>? _flux;
  Timer? _minuteurBattement;
  Position? _derniere;
  String? _uid;

  /// Course en cours du chauffeur : publiée avec sa position pour que
  /// SON client puisse le suivre (voir `firestore.rules`).
  String? _courseId;

  /// À appeler à chaque changement de course active (`null` quand il
  /// n'en a plus). Republie aussitôt la position pour ouvrir ou fermer
  /// le suivi côté client sans attendre le prochain déplacement.
  void definirCourse(String? courseId) {
    if (courseId == _courseId) return;
    _courseId = courseId;
    final position = _derniere;
    if (position != null) _envoyer(position, DateTime.now());
  }

  Future<void> demarrer() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _annulerSuivi();
    _uid = uid;
    _limiteur.reinitialiser();

    _flux = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
    ).listen(_surPosition, onError: (_) {});
    _minuteurBattement = Timer.periodic(const Duration(seconds: 10), (_) => _surBattement());
    unawaited(_maintienEcran.activer());

    // Premier point tout de suite, sans attendre un déplacement de 10 m.
    try {
      _surPosition(await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ));
    } catch (_) {
      // GPS momentanément indisponible : le flux prendra le relais.
    }
  }

  /// Coupe le suivi et efface la position publiée. À attendre avant
  /// une déconnexion : après, les règles refuseraient la suppression.
  Future<void> arreter() async {
    final uid = _uid;
    _annulerSuivi();
    _uid = null;
    await _maintienEcran.desactiver();
    if (uid == null) return;
    try {
      // Délai borné : hors connexion, Firestore attendrait le réseau
      // indéfiniment et bloquerait la déconnexion du chauffeur.
      await FirebaseFirestore.instance
          .collection(collection)
          .doc(uid)
          .delete()
          .timeout(const Duration(seconds: 5));
    } on FirebaseException {
      // Refusé ou hors connexion : la carte Admin marquera ce signal
      // comme perdu au bout de 2 minutes.
    } on TimeoutException {
      // Idem.
    }
  }

  void _annulerSuivi() {
    _flux?.cancel();
    _flux = null;
    _minuteurBattement?.cancel();
    _minuteurBattement = null;
    _derniere = null;
  }

  void _surPosition(Position position) {
    if (_uid == null) return;
    _derniere = position;
    final maintenant = DateTime.now();
    if (_limiteur.peutEnvoyer(maintenant)) _envoyer(position, maintenant);
  }

  void _surBattement() {
    final position = _derniere;
    final maintenant = DateTime.now();
    if (position != null && _limiteur.battementDu(maintenant)) _envoyer(position, maintenant);
  }

  Future<void> _envoyer(Position position, DateTime maintenant) async {
    final uid = _uid;
    if (uid == null) return;
    _limiteur.enregistrerEnvoi(maintenant);
    try {
      await FirebaseFirestore.instance.collection(collection).doc(uid).set({
        'latitude': position.latitude,
        'longitude': position.longitude,
        'precision': _nombre(position.accuracy),
        'cap': _nombre(position.heading),
        'vitesse': _nombre(position.speed),
        'majLe': FieldValue.serverTimestamp(),
        if (_courseId != null) 'courseId': _courseId,
      });
    } on FirebaseException {
      // Réseau coupé : le prochain envoi réessaiera.
    }
  }

  /// Certains navigateurs renvoient NaN pour le cap ou la vitesse.
  static double _nombre(double valeur) => valeur.isFinite ? valeur : 0;
}
