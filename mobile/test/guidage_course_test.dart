import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sprint/core/widgets/moto_vue_dessus.dart';
import 'package:sprint/features/conducteur/presentation/tabs/conducteur_accueil_tab.dart';
import 'package:sprint/features/conducteur/presentation/widgets/guidage_course.dart';
import 'package:sprint/features/courses/data/course_service.dart';
import 'package:sprint/features/courses/data/itineraire_service.dart';
import 'package:sprint/features/courses/data/position_chauffeur.dart';

// Le client attend à la Médina ; le chauffeur arrive de l'ouest ; la destination est aux Almadies.
const _client = LatLng(14.6900, -17.4400);
const _destination = LatLng(14.7450, -17.5170);
const _loin = LatLng(14.6900, -17.4580); // ~1,9 km à l'ouest du client

const _points = PointsCourse(
  latitudeDepart: 14.6900,
  longitudeDepart: -17.4400,
  latitudeArrivee: 14.7450,
  longitudeArrivee: -17.5170,
);

// Ce que lit un chauffeur tant que la position exacte du client n'est pas arrivée : le centre de sa case de ~150 m.
const _zone = LatLng(14.6905, -17.4410);
const _pointsArrondis = PointsCourse(
  latitudeDepart: 14.6905,
  longitudeDepart: -17.4410,
  latitudeArrivee: 14.7450,
  longitudeArrivee: -17.5170,
);

CourseFirestore _course(
  String statut, {
  PointsCourse? points = _points,
  String type = 'PASSAGER',
  bool departArrondi = false,
}) =>
    CourseFirestore(
      id: 'c1',
      clientId: 'client',
      chauffeurId: 'moussa',
      statut: statut,
      type: type,
      adresseDepart: 'Position GPS du client',
      adresseArrivee: 'Almadies, Dakar',
      prixFcfa: 3000,
      methodePaiement: 'WAVE',
      timestamp: DateTime(2026, 10, 9),
      points: points,
      departArrondi: departArrondi,
    );

PositionChauffeurDirect _position(LatLng p) =>
    PositionChauffeurDirect(uid: 'moussa', latitude: p.latitude, longitude: p.longitude, majLe: null);

class _Service implements ServiceItineraire {
  final appels = <({LatLng depuis, LatLng vers})>[];
  final reponses = <Completer<Itineraire>>[];

  @override
  Future<Itineraire> calculer({required String courseId, required LatLng depuis, required LatLng vers}) {
    appels.add((depuis: depuis, vers: vers));
    final reponse = Completer<Itineraire>();
    reponses.add(reponse);
    return reponse.future;
  }

  /// Route en deux tronçons, du départ au point visé.
  void repondre({int appel = -1}) {
    final i = appel < 0 ? reponses.length - 1 : appel;
    final a = appels[i];
    final milieu = LatLng((a.depuis.latitude + a.vers.latitude) / 2, (a.depuis.longitude + a.vers.longitude) / 2);
    reponses[i].complete(Itineraire(trace: [a.depuis, milieu, a.vers], distanceM: 1934));
  }

  void echouer({int appel = -1}) =>
      reponses[appel < 0 ? reponses.length - 1 : appel].completeError(StateError('serveur injoignable'));
}

class _Banc {
  final flux = StreamController<PositionChauffeurDirect>.broadcast();
  final service = _Service();
  final carte = MapController();
  var heure = DateTime(2026, 10, 9, 12);

  Future<void> bouger(WidgetTester tester, LatLng p) async {
    flux.add(_position(p));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
  }
}

const _repere = Key('repere-rendez-vous');
const _moto = Key('marqueur-moto-chauffeur');

void main() {
  late _Banc banc;

  Future<void> afficher(WidgetTester tester, CourseFirestore course, {PositionChauffeurDirect? initiale}) async {
    banc = _Banc();
    addTearDown(banc.flux.close);
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GuidageCourse(
          course: course,
          positions: banc.flux.stream,
          positionInitiale: initiale,
          service: banc.service,
          coucheFond: const SizedBox.shrink(),
          controleurCarte: banc.carte,
          horloge: () => banc.heure,
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('course acceptée : le repère du client est sur la carte dès l\'ouverture, en attente de la position',
      (tester) async {
    await afficher(tester, _course(StatutCourse.acceptee));

    expect(find.text('Rejoignez votre client'), findsOneWidget);
    expect(find.text('Localisation de votre position…'), findsOneWidget);
    expect(find.text('Position GPS du client'), findsOneWidget);
    expect(find.byKey(_repere), findsOneWidget);
    expect(find.byIcon(Icons.person_pin_circle_rounded), findsWidgets);
    expect(find.byKey(_moto), findsNothing, reason: 'pas encore de position du chauffeur');
    // Aucun appel au serveur sans position.
    expect(banc.service.appels, isEmpty);
  });

  testWidgets('le repère est posé au point GPS exact du client', (tester) async {
    await afficher(tester, _course(StatutCourse.acceptee));
    await banc.bouger(tester, _loin);

    // La pointe du repère (bas, au centre) est au point du client : on la compare à la
    // position à l'écran de ce point.
    final camera = banc.carte.camera;
    final ecran = camera.latLngToScreenPoint(_client);
    final repere = tester.getBottomLeft(find.byKey(_repere)) + Offset(tester.getSize(find.byKey(_repere)).width / 2, 0);
    final carte = tester.getTopLeft(find.byType(FlutterMap));
    expect(repere.dx - carte.dx, closeTo(ecran.x, 1.5));
    expect(repere.dy - carte.dy, closeTo(ecran.y, 1.5));
  });

  testWidgets('position du chauffeur, calcul, puis itinéraire avec distance et temps d\'approche', (tester) async {
    await afficher(tester, _course(StatutCourse.acceptee));
    await banc.bouger(tester, _loin);

    expect(find.text("Calcul de l'itinéraire…"), findsOneWidget);
    expect(find.byKey(_moto), findsOneWidget);
    expect(find.byType(MotoVueDessus), findsOneWidget);
    expect(banc.service.appels.single.depuis, _loin);
    expect(banc.service.appels.single.vers, _client);

    banc.service.repondre();
    await tester.pump();

    // 1 934 m : "1,9 km" ; 1,934 km à 22 km/h = 5,3 min -> 6 min.
    expect(find.text('1,9 km · ~6 min'), findsOneWidget);
    expect(find.text("Calcul de l'itinéraire…"), findsNothing);
    expect(find.text('Position GPS du client'), findsOneWidget);
    expect(find.textContaining('Estimation à vol d\'oiseau'), findsNothing);
    expect(find.byType(PolylineLayer), findsOneWidget);
  });

  testWidgets('le chauffeur ET le client sont visibles sur la carte', (tester) async {
    await afficher(tester, _course(StatutCourse.acceptee));
    await banc.bouger(tester, _loin);
    banc.service.repondre();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final visible = banc.carte.camera.visibleBounds;
    expect(visible.contains(_client), isTrue);
    expect(visible.contains(_loin), isTrue);
  });

  testWidgets('position déjà connue à l\'ouverture : la carte s\'ouvre cadrée sur le chauffeur et le client',
      (tester) async {
    await afficher(tester, _course(StatutCourse.acceptee), initiale: _position(_loin));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final visible = banc.carte.camera.visibleBounds;
    expect(visible.contains(_client), isTrue);
    expect(visible.contains(_loin), isTrue);
    expect(find.byKey(_moto), findsOneWidget);
    expect(find.byKey(_repere), findsOneWidget);
    expect(banc.service.appels.single.depuis, _loin);
  });

  testWidgets('serveur d\'itinéraires indisponible : estimation à vol d\'oiseau, annoncée comme telle', (tester) async {
    await afficher(tester, _course(StatutCourse.acceptee));
    await banc.bouger(tester, _loin);
    banc.service.echouer();
    await tester.pump();
    await tester.pump();

    // Ligne droite x 1,1 : ~2,1 km.
    expect(find.textContaining('≈ 2,1 km'), findsOneWidget);
    expect(find.textContaining('Estimation à vol d\'oiseau'), findsOneWidget);
    expect(find.byType(PolylineLayer), findsOneWidget);
  });

  testWidgets('arrivé au rendez-vous (moins de 40 m)', (tester) async {
    await afficher(tester, _course(StatutCourse.acceptee));
    await banc.bouger(tester, _loin);
    banc.service.repondre();
    await tester.pump();

    await banc.bouger(tester, const LatLng(14.6900, -17.4403));
    expect(find.text('Vous êtes au rendez-vous'), findsOneWidget);
    expect(find.text('Votre client est tout près.'), findsOneWidget);
  });

  testWidgets('client à bord : le repère et le guidage passent à la destination', (tester) async {
    await afficher(tester, _course(StatutCourse.acceptee), initiale: _position(_client));
    expect(banc.service.appels.single.vers, _client, reason: 'la position connue à l\'ouverture lance le calcul');
    banc.service.repondre();
    await tester.pump();
    expect(find.text('Rejoignez votre client'), findsOneWidget);

    // Nouvelle version de la course (Firestore) : le client est à bord.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GuidageCourse(
          course: _course(StatutCourse.enCours),
          positions: banc.flux.stream,
          service: banc.service,
          coucheFond: const SizedBox.shrink(),
          controleurCarte: banc.carte,
          horloge: () => banc.heure,
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('Vers la destination'), findsOneWidget);
    expect(find.text('Rejoignez votre client'), findsNothing);
    expect(find.text('Almadies, Dakar'), findsOneWidget);
    expect(find.byIcon(Icons.flag_circle_rounded), findsWidgets);
    expect(banc.service.appels, hasLength(2));
    expect(banc.service.appels.last.vers, _destination);
  });

  testWidgets('colis : les mêmes étapes avec les mots du colis', (tester) async {
    await afficher(tester, _course(StatutCourse.acceptee, type: 'COLIS'));
    expect(find.text('Récupérez le colis'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GuidageCourse(
          course: _course(StatutCourse.enCours, type: 'COLIS'),
          positions: banc.flux.stream,
          service: banc.service,
          coucheFond: const SizedBox.shrink(),
          controleurCarte: banc.carte,
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Vers le lieu de livraison'), findsOneWidget);
  });

  group('position exacte du client pas encore arrivée', () {
    final arrondie = _course(StatutCourse.acceptee, points: _pointsArrondis, departArrondi: true);

    testWidgets('sa zone approximative est montrée, sans repère exact ni itinéraire', (tester) async {
      await afficher(tester, arrondie, initiale: _position(_loin));

      expect(find.text('Position exacte du client…'), findsOneWidget);
      expect(find.text('En attendant, sa zone approximative est sur la carte.'), findsOneWidget);
      expect(find.byType(CircleLayer), findsOneWidget);
      expect(find.byKey(_repere), findsNothing, reason: 'pas de repère au point exact avant de le connaître');
      expect(find.byKey(_moto), findsOneWidget);
      expect(find.byType(PolylineLayer), findsNothing);
      expect(banc.service.appels, isEmpty, reason: 'aucun itinéraire vers une position approximative');

      // La carte cadre le chauffeur et la zone.
      await tester.pump(const Duration(milliseconds: 100));
      final visible = banc.carte.camera.visibleBounds;
      expect(visible.contains(_zone), isTrue);
      expect(visible.contains(_loin), isTrue);

      // Le cercle est centré sur la zone et couvre sa case de 150 m (demi-diagonale ~106 m).
      final cercle = tester.widget<CircleLayer>(find.byType(CircleLayer)).circles.single;
      expect(cercle.point, _zone);
      expect(cercle.useRadiusInMeter, isTrue);
      expect(cercle.radius, greaterThanOrEqualTo(106));
    });

    testWidgets('la position exacte arrive : le repère et l\'itinéraire remplacent la zone', (tester) async {
      await afficher(tester, arrondie, initiale: _position(_loin));
      expect(find.byKey(_repere), findsNothing);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: GuidageCourse(
            course: _course(StatutCourse.acceptee),
            positions: banc.flux.stream,
            service: banc.service,
            coucheFond: const SizedBox.shrink(),
            controleurCarte: banc.carte,
            horloge: () => banc.heure,
          ),
        ),
      ));
      await tester.pump();

      expect(find.byType(CircleLayer), findsNothing);
      expect(find.byKey(_repere), findsOneWidget);
      expect(find.text('Position exacte du client…'), findsNothing);
      expect(find.text("Calcul de l'itinéraire…"), findsOneWidget);
      expect(banc.service.appels.single.vers, _client);

      banc.service.repondre();
      await tester.pump();
      expect(find.text('1,9 km · ~6 min'), findsOneWidget);
    });

    testWidgets('sans position du chauffeur : la carte s\'ouvre sur la zone, pas sur Dakar', (tester) async {
      await afficher(tester, arrondie);

      expect(find.text('Position exacte du client…'), findsOneWidget);
      expect(banc.carte.camera.center.latitude, closeTo(_zone.latitude, 1e-6));
      expect(banc.carte.camera.center.longitude, closeTo(_zone.longitude, 1e-6));
    });

    testWidgets('client à bord : plus de zone, la destination est guidée normalement', (tester) async {
      await afficher(
        tester,
        _course(StatutCourse.enCours, points: _pointsArrondis, departArrondi: true),
        initiale: _position(_client),
      );

      expect(find.text('Vers la destination'), findsOneWidget);
      expect(find.byType(CircleLayer), findsNothing);
      expect(find.text('Position exacte du client…'), findsNothing);
      expect(banc.service.appels.single.vers, _destination);
    });
  });

  testWidgets('course sans coordonnées : pas de repère inventé, le chauffeur est invité à appeler', (tester) async {
    await afficher(tester, _course(StatutCourse.acceptee, points: null));
    await banc.bouger(tester, _loin);

    expect(find.text('Point de rendez-vous inconnu'), findsOneWidget);
    expect(find.text('Appelez ou écrivez au client pour le retrouver.'), findsOneWidget);
    expect(find.byKey(_repere), findsNothing);
    expect(banc.service.appels, isEmpty);
  });

  testWidgets('si le chauffeur déplace la carte, on ne la lui reprend pas ; « Recentrer » la ramène', (tester) async {
    await afficher(tester, _course(StatutCourse.acceptee));
    await banc.bouger(tester, _loin);
    banc.service.repondre();
    await tester.pump();
    expect(find.byTooltip('Recentrer'), findsNothing);

    await tester.drag(find.byType(FlutterMap), const Offset(80, 40));
    await tester.pump();
    final centre = banc.carte.camera.center;
    expect(find.byTooltip('Recentrer'), findsOneWidget);

    await banc.bouger(tester, const LatLng(14.6900, -17.4550));
    expect(banc.carte.camera.center, centre, reason: 'la carte reste où le chauffeur l\'a mise');

    await tester.tap(find.byTooltip('Recentrer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byTooltip('Recentrer'), findsNothing);
    final visible = banc.carte.camera.visibleBounds;
    expect(visible.contains(_client), isTrue);
    expect(visible.contains(const LatLng(14.6900, -17.4550)), isTrue);
  });

  testWidgets('sur l\'accueil du chauffeur, le guidage prend la place de la carte d\'attente et du bouton GO',
      (tester) async {
    // Taille d'écran de test par défaut : la police de test, très large, ferait
    // déborder les cartes de l'accueil à 390 px (sans rapport avec le guidage).
    banc = _Banc();
    addTearDown(banc.flux.close);

    Widget accueil({Widget? guidage}) => MaterialApp(
          home: ConducteurAccueilTab(
            enLigne: true,
            onBasculerStatut: (_) {},
            gainsJourFcfa: 0,
            onSimulerCourse: () {},
            guidage: guidage,
          ),
        );

    await tester.pumpWidget(accueil());
    await tester.pump();
    expect(find.text('Objectif du jour'), findsOneWidget);
    expect(find.text('Rejoignez votre client'), findsNothing);

    await tester.pumpWidget(accueil(
      guidage: GuidageCourse(
        course: _course(StatutCourse.acceptee),
        positions: banc.flux.stream,
        service: banc.service,
        coucheFond: const SizedBox.shrink(),
      ),
    ));
    await tester.pump();
    expect(find.text('Rejoignez votre client'), findsOneWidget);
    expect(find.text('Objectif du jour'), findsNothing);
    expect(find.text("Taux d'acceptation"), findsNothing);
  });
}
