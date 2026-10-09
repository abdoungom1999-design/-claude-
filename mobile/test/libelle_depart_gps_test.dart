import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/features/activite/presentation/detail_course_page.dart';
import 'package:sprint/features/courses/data/course_service.dart';
import 'package:sprint/features/courses/data/depart_gps.dart';
import 'package:sprint/features/support/data/support_service.dart';
import 'package:sprint/features/support/presentation/signalement_page.dart';

CourseFirestore _course({String depart = DepartGps.libelleCourse}) => CourseFirestore(
      id: 'c1',
      clientId: 'awa',
      chauffeurId: 'moussa',
      statut: StatutCourse.terminee,
      type: 'PASSAGER',
      adresseDepart: depart,
      adresseArrivee: 'Almadies, Dakar',
      prixFcfa: 3500,
      methodePaiement: 'WAVE',
      timestamp: DateTime(2026, 10, 9, 18, 30),
      commandeId: 'k1',
    );

class _SupportFactice extends SupportService {
  @override
  Stream<TicketSupport?> streamTicket(String courseId) => Stream.value(null);

  @override
  Stream<List<MessageTicket>> streamMessages(String courseId) => Stream.value(const []);
}

void main() {
  group('libellé du départ pris sur le GPS', () {
    test('le client lit « Ma position actuelle », le chauffeur et l\'Admin « Position GPS du client »', () {
      final course = _course();
      expect(course.adresseDepart, 'Position GPS du client');
      expect(course.adresseDepartPourLeClient, 'Ma position actuelle');
    });

    test('une adresse écrite reste telle quelle, y compris pour le client', () {
      final course = _course(depart: 'Plateau, Dakar');
      expect(course.adresseDepart, 'Plateau, Dakar');
      expect(course.adresseDepartPourLeClient, 'Plateau, Dakar');
      expect(DepartGps.pourLeClient(''), '');
    });

    testWidgets('détail de la course (historique du client) : « Ma position actuelle »', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: DetailCoursePage(course: _course(), clientId: 'awa', supportService: _SupportFactice()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Ma position actuelle'), findsOneWidget);
      expect(find.text('Almadies, Dakar'), findsOneWidget);
      expect(find.text('Position GPS du client'), findsNothing);
    });

    testWidgets('signalement d\'un problème (client) : « Ma position actuelle → arrivée »', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SignalementPage(course: _course(), clientId: 'awa', service: _SupportFactice()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Ma position actuelle → Almadies, Dakar'), findsOneWidget);
      expect(find.textContaining('Position GPS du client'), findsNothing);
    });

    testWidgets('détail de la course avec une adresse écrite : inchangé', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: DetailCoursePage(
            course: _course(depart: 'Plateau, Dakar'), clientId: 'awa', supportService: _SupportFactice()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Plateau, Dakar'), findsOneWidget);
      expect(find.text('Ma position actuelle'), findsNothing);
    });
  });
}
