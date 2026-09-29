import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sprint/core/maps/proximite_service.dart';
import 'package:sprint/core/widgets/moto_vue_dessus.dart';
import 'package:sprint/features/client/presentation/suivi_course_page.dart';
import 'package:sprint/features/client/presentation/widgets/carte_chauffeur.dart';
import 'package:sprint/features/courses/data/course_service.dart';
import 'package:sprint/features/courses/data/position_chauffeur.dart';
import 'package:sprint/features/messages/data/chat_service.dart';

const _points = PointsCourse(
  latitudeDepart: 14.6680,
  longitudeDepart: -17.4380,
  latitudeArrivee: 14.7450,
  longitudeArrivee: -17.5170,
);

CourseFirestore _course(String statut, {PointsCourse? points = _points, String? chauffeurId}) => CourseFirestore(
      id: 'c1',
      clientId: 'awa',
      chauffeurId: chauffeurId,
      statut: statut,
      type: 'PASSAGER',
      adresseDepart: 'Plateau',
      adresseArrivee: 'Almadies',
      prixFcfa: 3000,
      methodePaiement: 'WAVE',
      timestamp: DateTime(2026, 9, 29),
      points: points,
    );

class _Courses extends CourseService {
  _Courses(this.flux);

  final Stream<CourseFirestore?> flux;
  final annulations = <String>[];

  @override
  Stream<CourseFirestore?> streamCourse(String courseId) => flux;

  @override
  Stream<PositionChauffeurDirect?> streamPositionChauffeur(String chauffeurId) => const Stream.empty();

  @override
  Future<void> annulerCourse(String courseId) async => annulations.add(courseId);
}

class _Chat extends ChatService {
  @override
  Future<Map<String, dynamic>?> chargerProfil(String uid) async => {
        'nom': 'Moussa Diop',
        'vehiculeId': 'Honda CB125 (2021)',
        'plaqueImmatriculation': 'DK-4821-AB',
      };

  @override
  Stream<ChatMessageFirestore?> streamDernierMessage(String chatId) => const Stream.empty();
}

class _Proximite implements ProximiteService {
  final appels = <LatLng>[];

  @override
  Future<Proximite> chauffeursProches(LatLng autour) async {
    appels.add(autour);
    return Proximite(
      motos: [
        for (var i = 0; i < 3; i++)
          MotoProche(position: LatLng(autour.latitude + 0.002 * i, autour.longitude + 0.001), cap: 45.0 * i),
      ],
      approcheMinutes: 4,
    );
  }
}

void main() {
  Future<(_Courses, _Proximite)> afficher(WidgetTester tester, Stream<CourseFirestore?> flux) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final courses = _Courses(flux);
    final proximite = _Proximite();
    await tester.pumpWidget(MaterialApp(
      home: SuiviCoursePage(
        courseId: 'c1',
        courseService: courses,
        chatService: _Chat(),
        monUid: 'awa',
        proximite: proximite,
        coucheFond: const SizedBox.shrink(),
      ),
    ));
    await tester.pump();
    await tester.pump();
    return (courses, proximite);
  }

  testWidgets('recherche d\'un chauffeur : les motos disponibles restent visibles sur la carte', (tester) async {
    final (_, proximite) = await afficher(tester, Stream.value(_course(StatutCourse.enAttente)));

    expect(find.text("Recherche d'un chauffeur…"), findsOneWidget);
    expect(find.byType(MotoVueDessus), findsNWidgets(3));
    expect(find.text('3 motos disponibles · ~4 min'), findsOneWidget);
    // Cherchées autour du point de prise en charge.
    expect(proximite.appels.single, const LatLng(14.6680, -17.4380));
    // Le client peut toujours annuler.
    expect(find.text('Annuler la demande'), findsOneWidget);
  });

  testWidgets('ancienne course sans coordonnées : la carte s\'affiche quand même, autour de Dakar', (tester) async {
    final (_, proximite) = await afficher(tester, Stream.value(_course(StatutCourse.enAttente, points: null)));
    expect(find.byType(MotoVueDessus), findsNWidgets(3));
    expect(proximite.appels.single, const LatLng(14.6928, -17.4467));
  });

  testWidgets('annuler la demande depuis cet écran', (tester) async {
    final (courses, _) = await afficher(tester, Stream.value(_course(StatutCourse.enAttente)));
    await tester.ensureVisible(find.text('Annuler la demande'));
    await tester.tap(find.text('Annuler la demande'));
    await tester.pump();
    expect(courses.annulations, ['c1']);
  });

  testWidgets('dès l\'acceptation, la carte des motos laisse place à l\'identité du chauffeur', (tester) async {
    final flux = StreamController<CourseFirestore?>();
    addTearDown(flux.close);
    await afficher(tester, flux.stream);

    flux.add(_course(StatutCourse.enAttente));
    await tester.pump();
    expect(find.text("Recherche d'un chauffeur…"), findsOneWidget);
    expect(find.byType(CarteChauffeur), findsNothing);

    flux.add(_course(StatutCourse.acceptee, chauffeurId: 'moussa'));
    await tester.pump();
    await tester.pump();
    expect(find.text("Recherche d'un chauffeur…"), findsNothing);
    expect(find.byType(CarteChauffeur), findsOneWidget);
    expect(find.text('Moussa Diop'), findsOneWidget);
    // Plus de motos anonymes : on suit désormais SON chauffeur, en position exacte.
    expect(find.text('3 motos disponibles · ~4 min'), findsNothing);
  });
}
