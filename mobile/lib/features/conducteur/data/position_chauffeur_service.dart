import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/location/maintien_ecran.dart';
import '../../courses/data/position_chauffeur.dart';

/// Rythme d'envoi de la position : au plus un envoi toutes les
/// [intervalleMin] quand le chauffeur roule, et au moins un toutes les
/// [battementCoeur] même immobile, pour que l'Admin distingue un
/// chauffeur à l'arrêt d'un chauffeur dont le signal est perdu.
///
/// Pendant une course, le client suit son chauffeur en direct : le rythme
/// passe à [enCourse] (2 s, et un envoi même à l'arrêt toutes les 5 s pour
/// que le client voie le signal vivant).
class LimiteurEnvoiPosition {
  LimiteurEnvoiPosition({
    this.intervalleMin = const Duration(seconds: 5),
    this.battementCoeur = const Duration(seconds: 30),
  });

  /// Rythme du suivi en direct, pendant une course.
  LimiteurEnvoiPosition.enCourse()
      : intervalleMin = const Duration(seconds: 2),
        battementCoeur = const Duration(seconds: 5);

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
/// Version web : le navigateur suspend la géolocalisation quand l'écran
/// est verrouillé ou l'onglet en arrière-plan ; l'écran est donc maintenu
/// allumé ([MaintienEcran]). APK Android : le suivi passe par un service
/// de premier plan (notification permanente "vous êtes en ligne") et
/// continue écran verrouillé, tant que le chauffeur est en ligne.
class PositionChauffeurService {
  static const collection = 'positions_chauffeurs';

  var _limiteur = LimiteurEnvoiPosition();
  final _maintienEcran = MaintienEcran();
  StreamSubscription<Position>? _flux;
  Timer? _minuteurBattement;
  Position? _derniere;
  DateTime? _dernierRelevele;
  String? _uid;
  final _positions = StreamController<PositionChauffeurDirect>.broadcast();

  /// Chaque relevé GPS du chauffeur, pour son propre écran (guidage vers le
  /// client) : tous les relevés, pas seulement ceux qui partent dans Firestore.
  Stream<PositionChauffeurDirect> get positions => _positions.stream;

  /// Dernier relevé GPS ; `null` tant que le suivi est coupé ou n'a rien reçu.
  PositionChauffeurDirect? get dernierePosition {
    final position = _derniere;
    final uid = _uid;
    final releveLe = _dernierRelevele;
    return position == null || uid == null || releveLe == null ? null : _direct(uid, position, releveLe);
  }

  static PositionChauffeurDirect _direct(String uid, Position position, DateTime releveLe) => PositionChauffeurDirect(
        uid: uid,
        latitude: position.latitude,
        longitude: position.longitude,
        majLe: releveLe,
        cap: _nombre(position.heading),
        vitesse: _nombre(position.speed),
      );

  /// Course en cours du chauffeur : publiée avec sa position pour que
  /// SON client puisse le suivre (voir `firestore.rules`).
  String? _courseId;

  /// À appeler à chaque changement de course active (`null` quand il
  /// n'en a plus). Republie aussitôt la position pour ouvrir ou fermer
  /// le suivi côté client sans attendre le prochain déplacement.
  ///
  /// Pendant une course, le GPS est relu et publié au rythme du suivi en
  /// direct (voir [LimiteurEnvoiPosition.enCourse]) ; hors course, retour
  /// au rythme économe en batterie.
  void definirCourse(String? courseId) {
    if (courseId == _courseId) return;
    final avait = _courseId != null;
    _courseId = courseId;
    if (_uid != null && avait != (courseId != null)) _lancerFlux();
    final position = _derniere;
    if (position != null) _envoyer(position, DateTime.now());
  }

  bool get _enCourse => _courseId != null;

  void _lancerFlux() {
    _flux?.cancel();
    _limiteur = _enCourse ? LimiteurEnvoiPosition.enCourse() : LimiteurEnvoiPosition();
    _flux = Geolocator.getPositionStream(locationSettings: reglagesSuivi(android: _android, enCourse: _enCourse))
        .listen(_surPosition, onError: (_) {});
  }

  Future<void> demarrer() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _annulerSuivi();
    _uid = uid;

    _lancerFlux();
    _minuteurBattement = Timer.periodic(const Duration(seconds: 2), (_) => _surBattement());
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
    _dernierRelevele = null;
  }

  void _surPosition(Position position) {
    final uid = _uid;
    if (uid == null) return;
    final maintenant = DateTime.now();
    _derniere = position;
    _dernierRelevele = maintenant;
    _positions.add(_direct(uid, position, maintenant));
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

  static bool get _android => !kIsWeb && Platform.isAndroid;

  /// Réglages du suivi GPS. Sur Android, service de premier plan : sans
  /// lui, le système coupe le GPS de l'app dès que l'écran se verrouille.
  @visibleForTesting
  static LocationSettings reglagesSuivi({required bool android, bool enCourse = false}) {
    // Pendant une course : un point tous les ~3 m (la moto avance
    // "mètre par mètre" sous les yeux du client) ; sinon 10 m.
    final filtre = enCourse ? 3 : 10;
    final precision = enCourse ? LocationAccuracy.best : LocationAccuracy.high;
    if (!android) return LocationSettings(accuracy: precision, distanceFilter: filtre);
    return AndroidSettings(
      accuracy: precision,
      distanceFilter: filtre,
      intervalDuration: Duration(seconds: enCourse ? 2 : 5),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Sprint : vous êtes en ligne',
        notificationText: 'Votre position est partagée pour recevoir des courses. Passez hors ligne pour l\'arrêter.',
        notificationChannelName: 'Chauffeur en ligne',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );
  }

  /// Certains navigateurs renvoient NaN pour le cap ou la vitesse.
  static double _nombre(double valeur) => valeur.isFinite ? valeur : 0;
}
