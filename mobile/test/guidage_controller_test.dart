import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sprint/core/maps/trace_utils.dart';
import 'package:sprint/features/conducteur/data/guidage_controller.dart';
import 'package:sprint/features/courses/data/course_service.dart';
import 'package:sprint/features/courses/data/itineraire_service.dart';
import 'package:sprint/features/courses/data/position_chauffeur.dart';

// Le client attend sur une rue d'ouest en est ; sa destination est loin au nord.
const _client = LatLng(14.6900, -17.4400);
const _destination = LatLng(14.7450, -17.5170);
const _depart = LatLng(14.6900, -17.4600); // ~2,1 km à l'ouest du client

const _points = PointsCourse(
  latitudeDepart: 14.6900,
  longitudeDepart: -17.4400,
  latitudeArrivee: 14.7450,
  longitudeArrivee: -17.5170,
);

CourseFirestore _course(String statut, {PointsCourse? points = _points, String type = 'PASSAGER'}) => CourseFirestore(
      id: 'c1',
      clientId: 'client',
      chauffeurId: 'moussa',
      statut: statut,
      type: type,
      adresseDepart: 'Position GPS du client',
      adresseArrivee: 'Almadies',
      prixFcfa: 3000,
      methodePaiement: 'WAVE',
      timestamp: DateTime(2026, 10, 9),
      points: points,
    );

PositionChauffeurDirect _position(LatLng p, {double? cap, double? vitesse}) => PositionChauffeurDirect(
    uid: 'moussa', latitude: p.latitude, longitude: p.longitude, majLe: null, cap: cap, vitesse: vitesse);

/// Route de test : en ligne droite du point de départ au client, par la rue.
Itineraire _route(LatLng depuis, LatLng vers) {
  final milieu = LatLng((depuis.latitude + vers.latitude) / 2, (depuis.longitude + vers.longitude) / 2);
  final trace = [depuis, milieu, vers];
  return Itineraire(trace: trace, distanceM: TraceUtils.longueurM(trace));
}

typedef _Appel = ({String courseId, LatLng depuis, LatLng vers});

/// Serveur d'itinéraires contrôlé par le test : chaque appel attend sa réponse.
class _ServiceFactice implements ServiceItineraire {
  final appels = <_Appel>[];
  final _reponses = <Completer<Itineraire>>[];

  @override
  Future<Itineraire> calculer({required String courseId, required LatLng depuis, required LatLng vers}) {
    appels.add((courseId: courseId, depuis: depuis, vers: vers));
    final reponse = Completer<Itineraire>();
    _reponses.add(reponse);
    return reponse.future;
  }

  void repondre(Itineraire itineraire, {int appel = -1}) =>
      _reponses[appel < 0 ? _reponses.length - 1 : appel].complete(itineraire);

  void echouer({int appel = -1}) =>
      _reponses[appel < 0 ? _reponses.length - 1 : appel].completeError(StateError('serveur injoignable'));
}

class _Banc {
  _Banc({CourseFirestore? course, PositionChauffeurDirect? positionInitiale}) {
    guidage = GuidageController(
      course: course ?? _course(StatutCourse.acceptee),
      positions: positions.stream,
      positionInitiale: positionInitiale,
      service: service,
      horloge: () => maintenant,
    );
  }

  final service = _ServiceFactice();
  final positions = StreamController<PositionChauffeurDirect>.broadcast();
  var maintenant = DateTime(2026, 10, 9, 12);
  late final GuidageController guidage;

  Future<void> bouger(LatLng p, {double? cap, double? vitesse}) async {
    positions.add(_position(p, cap: cap, vitesse: vitesse));
    await Future<void>.delayed(Duration.zero);
  }

  /// Laisse passer le temps (horloge du guidage) et les réponses du serveur.
  Future<void> attendre(Duration duree) async {
    maintenant = maintenant.add(duree);
    await Future<void>.delayed(Duration.zero);
  }

  var _guidageFerme = false;

  void fermerLeGuidage() {
    if (_guidageFerme) return;
    _guidageFerme = true;
    guidage.dispose();
  }

  Future<void> fermer() async {
    fermerLeGuidage();
    await positions.close();
  }
}

void main() {
  late _Banc banc;

  tearDown(() => banc.fermer());

  test('sans position : en attente ; dès la première position, l\'itinéraire est demandé au serveur', () async {
    banc = _Banc();
    expect(banc.guidage.etat, EtatGuidage.attentePosition);
    expect(banc.guidage.cible, _client);
    expect(banc.guidage.versDestination, isFalse);
    expect(banc.service.appels, isEmpty);

    await banc.bouger(_depart);

    expect(banc.guidage.etat, EtatGuidage.calcul);
    expect(banc.service.appels, hasLength(1));
    expect(banc.service.appels.single.courseId, 'c1');
    expect(banc.service.appels.single.depuis, _depart);
    expect(banc.service.appels.single.vers, _client);
    expect(banc.guidage.resteM, isNull);
    expect(banc.guidage.minutes, isNull);
    expect(banc.guidage.traceRestante, isEmpty);

    banc.service.repondre(_route(_depart, _client));
    await Future<void>.delayed(Duration.zero);

    expect(banc.guidage.etat, EtatGuidage.pret);
    expect(banc.guidage.estimation, isFalse);
    expect(banc.guidage.resteM, closeTo(2150, 40));
    // 2,15 km à 22 km/h : 5,9 min -> 6 min.
    expect(banc.guidage.minutes, 6);
    expect(banc.guidage.arrive, isFalse);
    expect(banc.guidage.traceRestante.first, _depart);
    expect(banc.guidage.traceRestante.last, _client);
  });

  test('position déjà connue à l\'ouverture : l\'itinéraire est demandé tout de suite', () async {
    banc = _Banc(positionInitiale: _position(_depart));
    expect(banc.service.appels, hasLength(1));
    expect(banc.guidage.etat, EtatGuidage.calcul);
  });

  test('le chauffeur avance sur son itinéraire : le reste diminue, sans nouvel appel au serveur', () async {
    banc = _Banc();
    await banc.bouger(_depart);
    banc.service.repondre(_route(_depart, _client));
    await Future<void>.delayed(Duration.zero);
    final auDepart = banc.guidage.resteM!;

    await banc.bouger(const LatLng(14.6900, -17.4500)); // à mi-chemin, sur la route
    await banc.attendre(const Duration(minutes: 1));
    await banc.bouger(const LatLng(14.6900, -17.4450));

    expect(banc.service.appels, hasLength(1));
    expect(banc.guidage.resteM, lessThan(auDepart / 2));
    expect(banc.guidage.resteM, closeTo(540, 25));
    expect(banc.guidage.minutes, 2);
    // Le tracé affiché part du chauffeur : la partie déjà parcourue a disparu.
    final trace = banc.guidage.traceRestante;
    expect(trace.first, const LatLng(14.6900, -17.4450));
    expect(TraceUtils.longueurM(trace), closeTo(540, 25));
  });

  test('arrivée à moins de 40 m du client', () async {
    banc = _Banc();
    await banc.bouger(_depart);
    banc.service.repondre(_route(_depart, _client));
    await Future<void>.delayed(Duration.zero);

    await banc.bouger(const LatLng(14.6900, -17.4403)); // ~32 m
    expect(banc.guidage.arrive, isTrue);
    expect(banc.guidage.minutes, 1);
  });

  group('sortie de l\'itinéraire', () {
    Future<void> versLeClient() async {
      banc = _Banc();
      await banc.bouger(_depart);
      banc.service.repondre(_route(_depart, _client));
      await Future<void>.delayed(Duration.zero);
    }

    test('plus de 120 m hors route : nouvel itinéraire, mais pas avant 20 s', () async {
      await versLeClient();
      const horsRoute = LatLng(14.6925, -17.4500); // ~280 m au nord de la rue

      await banc.attendre(const Duration(seconds: 5));
      await banc.bouger(horsRoute);
      expect(banc.service.appels, hasLength(1), reason: 'trop tôt : le dernier calcul date de 5 s');

      await banc.attendre(const Duration(seconds: 20));
      await banc.bouger(const LatLng(14.6926, -17.4498));
      expect(banc.service.appels, hasLength(2));
      expect(banc.service.appels.last.depuis, const LatLng(14.6926, -17.4498));

      // Une seule demande à la fois, même si le chauffeur continue de rouler.
      await banc.attendre(const Duration(seconds: 30));
      await banc.bouger(const LatLng(14.6927, -17.4496));
      expect(banc.service.appels, hasLength(2));
    });

    test('un petit écart (rue voisine, GPS imprécis) ne relance rien', () async {
      await versLeClient();
      await banc.attendre(const Duration(minutes: 5));
      await banc.bouger(const LatLng(14.6906, -17.4500)); // ~67 m
      expect(banc.service.appels, hasLength(1));
    });

    test('le nouvel itinéraire remplace l\'ancien', () async {
      await versLeClient();
      await banc.attendre(const Duration(seconds: 30));
      const horsRoute = LatLng(14.6925, -17.4500);
      await banc.bouger(horsRoute);
      expect(banc.service.appels, hasLength(2));

      final nouvelle = _route(horsRoute, _client);
      banc.service.repondre(nouvelle);
      await Future<void>.delayed(Duration.zero);

      expect(banc.guidage.traceRestante.first, horsRoute);
      expect(banc.guidage.resteM, closeTo(nouvelle.distanceM, 5));
    });
  });

  group('serveur d\'itinéraires indisponible', () {
    test('première demande échouée : estimation à vol d\'oiseau, puis nouvel essai après 20 s', () async {
      banc = _Banc();
      await banc.bouger(_depart);
      banc.service.echouer();
      await Future<void>.delayed(Duration.zero);

      expect(banc.guidage.etat, EtatGuidage.pret);
      expect(banc.guidage.estimation, isTrue);
      expect(banc.guidage.traceRestante, [_depart, _client]);
      // ~2,1 km x 1,1 : jamais moins que la ligne droite.
      expect(banc.guidage.resteM, closeTo(2370, 50));

      await banc.attendre(const Duration(seconds: 10));
      await banc.bouger(const LatLng(14.6900, -17.4580));
      expect(banc.service.appels, hasLength(1), reason: 'pas avant 20 s');
      // L'estimation suit le chauffeur.
      expect(banc.guidage.traceRestante.first, const LatLng(14.6900, -17.4580));
      expect(banc.guidage.resteM, lessThan(2370));

      await banc.attendre(const Duration(seconds: 15));
      await banc.bouger(const LatLng(14.6900, -17.4560));
      expect(banc.service.appels, hasLength(2));
      banc.service.repondre(_route(const LatLng(14.6900, -17.4560), _client));
      await Future<void>.delayed(Duration.zero);

      expect(banc.guidage.estimation, isFalse, reason: 'le vrai itinéraire remplace l\'estimation');
      expect(banc.guidage.traceRestante, hasLength(greaterThan(2)));
    });

    test('un itinéraire déjà obtenu n\'est jamais remplacé par une estimation', () async {
      banc = _Banc();
      await banc.bouger(_depart);
      banc.service.repondre(_route(_depart, _client));
      await Future<void>.delayed(Duration.zero);

      await banc.attendre(const Duration(seconds: 30));
      await banc.bouger(const LatLng(14.6925, -17.4500)); // hors route : nouvel appel
      expect(banc.service.appels, hasLength(2));
      banc.service.echouer();
      await Future<void>.delayed(Duration.zero);

      expect(banc.guidage.estimation, isFalse);
      expect(banc.guidage.traceRestante.length, greaterThan(2));

      // Nouvel essai seulement 20 s plus tard.
      await banc.attendre(const Duration(seconds: 10));
      await banc.bouger(const LatLng(14.6926, -17.4498));
      expect(banc.service.appels, hasLength(2));
      await banc.attendre(const Duration(seconds: 15));
      await banc.bouger(const LatLng(14.6927, -17.4496));
      expect(banc.service.appels, hasLength(3));
    });
  });

  group('changement de point visé', () {
    test('client à bord : le guidage vise la destination et recalcule', () async {
      banc = _Banc();
      await banc.bouger(_client);
      banc.service.repondre(_route(_client, _client), appel: 0);
      await Future<void>.delayed(Duration.zero);

      banc.guidage.mettreAJourCourse(_course(StatutCourse.enCours));

      expect(banc.guidage.versDestination, isTrue);
      expect(banc.guidage.cible, _destination);
      expect(banc.guidage.etat, EtatGuidage.calcul);
      expect(banc.service.appels, hasLength(2));
      expect(banc.service.appels.last.vers, _destination);

      banc.service.repondre(_route(_client, _destination));
      await Future<void>.delayed(Duration.zero);
      expect(banc.guidage.etat, EtatGuidage.pret);
      expect(banc.guidage.resteM, closeTo(TraceUtils.distanceM(_client, _destination), 200));
    });

    test('la réponse attendue pour l\'ancien point visé est ignorée', () async {
      banc = _Banc();
      await banc.bouger(_client);
      expect(banc.service.appels, hasLength(1)); // vers le client, pas encore de réponse

      banc.guidage.mettreAJourCourse(_course(StatutCourse.enCours));
      expect(banc.service.appels, hasLength(2));

      // L'ancienne réponse (vers le client) arrive après le changement.
      banc.service.repondre(_route(_client, _client), appel: 0);
      await Future<void>.delayed(Duration.zero);
      expect(banc.guidage.etat, EtatGuidage.calcul, reason: 'rien ne doit s\'afficher pour l\'ancien point');

      banc.service.repondre(_route(_client, _destination), appel: 1);
      await Future<void>.delayed(Duration.zero);
      expect(banc.guidage.etat, EtatGuidage.pret);
      expect(banc.guidage.traceRestante.last, _destination);
    });

    test('une nouvelle version de la même course ne relance rien', () async {
      banc = _Banc();
      await banc.bouger(_depart);
      banc.service.repondre(_route(_depart, _client));
      await Future<void>.delayed(Duration.zero);

      banc.guidage.mettreAJourCourse(_course(StatutCourse.acceptee));
      banc.guidage.mettreAJourCourse(_course(StatutCourse.acceptee));

      expect(banc.service.appels, hasLength(1));
      expect(banc.guidage.etat, EtatGuidage.pret);
    });
  });

  test('course sans coordonnées : rien à guider, aucun appel au serveur', () async {
    banc = _Banc(course: _course(StatutCourse.acceptee, points: null));
    await banc.bouger(_depart);

    expect(banc.guidage.etat, EtatGuidage.sansPointVise);
    expect(banc.guidage.cible, isNull);
    expect(banc.guidage.resteM, isNull);
    expect(banc.service.appels, isEmpty);
  });

  group('direction de la moto', () {
    test('en roulant : le cap du GPS', () async {
      banc = _Banc();
      await banc.bouger(_depart, cap: 90, vitesse: 6);
      expect(banc.guidage.cap, 90);
    });

    test('à l\'arrêt, sans cap : orientée vers le client', () async {
      banc = _Banc();
      await banc.bouger(_depart, cap: 0, vitesse: 0);
      expect(banc.guidage.cap, closeTo(90, 1)); // le client est à l'est
    });

    test('déplacement sans cap GPS : le sens du déplacement', () async {
      banc = _Banc();
      await banc.bouger(_depart);
      await banc.bouger(const LatLng(14.6910, -17.4600)); // ~110 m vers le nord
      expect(banc.guidage.cap, closeTo(0, 2));
    });

    test('position connue à l\'ouverture : orientée dès le départ, sans attendre un déplacement', () async {
      banc = _Banc(positionInitiale: _position(_depart, cap: 200, vitesse: 5));
      expect(banc.guidage.cap, 200);
    });

    test('position connue à l\'ouverture, à l\'arrêt : orientée vers le client', () async {
      banc = _Banc(positionInitiale: _position(_depart));
      expect(banc.guidage.cap, closeTo(90, 1));
    });

    test('rotation par le plus court chemin (350° -> 10° = +20°)', () async {
      banc = _Banc();
      await banc.bouger(_depart, cap: 350, vitesse: 6);
      await banc.bouger(_depart, cap: 10, vitesse: 6);
      expect(banc.guidage.cap, closeTo(370, 1e-9));
    });
  });

  test('guidage fermé : plus de réponse ni de position prises en compte', () async {
    banc = _Banc();
    await banc.bouger(_depart);
    banc.fermerLeGuidage();

    banc.service.repondre(_route(_depart, _client)); // ne doit rien lever
    await Future<void>.delayed(Duration.zero);
    banc.positions.add(_position(_client)); // idem
    await Future<void>.delayed(Duration.zero);
    expect(banc.service.appels, hasLength(1));
  });
}
