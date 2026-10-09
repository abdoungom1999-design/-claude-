import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sprint/core/maps/proximite_service.dart';
import 'package:sprint/core/widgets/trip_map.dart';
import 'package:sprint/features/client/presentation/suivi_course_page.dart';
import 'package:sprint/features/client/presentation/widgets/suivi_approche.dart';
import 'package:sprint/features/courses/data/course_service.dart';
import 'package:sprint/features/courses/data/position_chauffeur.dart';
import 'package:sprint/features/messages/data/chat_service.dart';
import 'package:sprint/features/messages/data/messages_non_lus.dart';

// Ce que lit le client : sa course ne porte que le centre de la case de ~150 m où il se trouve.
const _arrondi = PointsCourse(
  latitudeDepart: 14.69273,
  longitudeDepart: -17.44582,
  latitudeArrivee: 14.7450,
  longitudeArrivee: -17.5170,
);
const _exact = DepartExact(latitude: 14.69281, longitude: -17.44673);

CourseFirestore _course(String statut) => CourseFirestore(
      id: 'c1',
      clientId: 'awa',
      chauffeurId: statut == StatutCourse.enAttente ? null : 'moussa',
      statut: statut,
      type: 'PASSAGER',
      adresseDepart: 'Position GPS du client',
      adresseArrivee: 'Almadies',
      prixFcfa: 3000,
      methodePaiement: 'WAVE',
      timestamp: DateTime(2026, 10, 9),
      points: _arrondi,
      departArrondi: true,
    );

class _Courses extends CourseService {
  final courses = StreamController<CourseFirestore?>();
  final exactes = StreamController<DepartExact?>();
  final lectures = <String>[];

  @override
  Stream<CourseFirestore?> streamCourse(String courseId) => courses.stream;

  @override
  Stream<DepartExact?> streamDepartExact(String courseId) {
    lectures.add(courseId);
    return exactes.stream;
  }

  @override
  Stream<PositionChauffeurDirect?> streamPositionChauffeur(String chauffeurId) => const Stream.empty();
}

class _Chat extends ChatService {
  @override
  Future<Map<String, dynamic>?> chargerProfil(String uid) async => {'nom': 'Moussa Diop'};

  @override
  Stream<ChatMessageFirestore?> streamDernierMessage(String chatId) => const Stream.empty();

  @override
  Stream<List<ChatMessageFirestore>> streamMessages(String chatId) => const Stream.empty();
}

class _Proximite implements ProximiteService {
  @override
  Future<Proximite> chauffeursProches(LatLng autour) async => const Proximite(motos: [], approcheMinutes: null);
}

void main() {
  late _Courses service;

  Future<void> afficher(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    service = _Courses();
    addTearDown(service.courses.close);
    addTearDown(service.exactes.close);
    await tester.pumpWidget(MaterialApp(
      home: SuiviCoursePage(
        courseId: 'c1',
        courseService: service,
        chatService: _Chat(),
        monUid: 'awa',
        messagesNonLus: MessagesNonLus(alerte: () {}),
        proximite: _Proximite(),
        coucheFond: const SizedBox.shrink(),
      ),
    ));
  }

  Future<void> envoyer(WidgetTester tester, CourseFirestore course) async {
    service.courses.add(course);
    await tester.pump();
    await tester.pump();
  }

  Future<void> recevoirExacte(WidgetTester tester) async {
    service.exactes.add(_exact);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('recherche d\'un chauffeur : la carte passe de la zone au point exact du client', (tester) async {
    await afficher(tester);
    await envoyer(tester, _course(StatutCourse.enAttente));

    expect(find.text("Recherche d'un chauffeur…"), findsOneWidget);
    expect(service.lectures, ['c1']);
    expect(tester.widget<TripMap>(find.byType(TripMap)).depart,
        const LatLng(14.69273, -17.44582), reason: 'en attendant la position exacte');

    await recevoirExacte(tester);

    expect(tester.widget<TripMap>(find.byType(TripMap)).depart, const LatLng(14.69281, -17.44673));
    expect(service.lectures, ['c1'], reason: 'une seule lecture');
  });

  testWidgets('chauffeur en route : le suivi vise la position exacte du client', (tester) async {
    await afficher(tester);
    await envoyer(tester, _course(StatutCourse.acceptee));

    expect(tester.widget<SuiviApproche>(find.byType(SuiviApproche)).course.points!.latitudeDepart, 14.69273);

    await recevoirExacte(tester);

    final points = tester.widget<SuiviApproche>(find.byType(SuiviApproche)).course.points!;
    expect(points.latitudeDepart, 14.69281);
    expect(points.longitudeDepart, -17.44673);
    expect(points.latitudeArrivee, 14.7450, reason: 'la destination ne change pas');
  });

  testWidgets('pas de position exacte (lecture impossible) : l\'écran reste utilisable avec la zone', (tester) async {
    await afficher(tester);
    await envoyer(tester, _course(StatutCourse.acceptee));

    service.exactes.addError(StateError('permission-denied'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(SuiviApproche), findsOneWidget);
    expect(find.text('Votre course'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
