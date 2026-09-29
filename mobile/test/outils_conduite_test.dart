import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/maps/navigation_gps.dart';
import 'package:sprint/features/client/presentation/suivi_course_page.dart';
import 'package:sprint/features/conducteur/presentation/widgets/actions_course_active.dart';
import 'package:sprint/features/conducteur/presentation/widgets/course_active_bandeau.dart';
import 'package:sprint/features/courses/data/course_service.dart';
import 'package:sprint/features/messages/data/chat_service.dart';

CourseFirestore _course(String statut, {String? annuleePar, String? motif, String? commandeId}) => CourseFirestore(
      id: 'c1',
      clientId: 'awa',
      chauffeurId: 'moussa',
      statut: statut,
      type: 'PASSAGER',
      adresseDepart: 'Plateau',
      adresseArrivee: 'Almadies',
      prixFcfa: 3000,
      methodePaiement: 'WAVE',
      timestamp: DateTime(2026, 9, 27),
      annuleePar: annuleePar,
      motifAnnulation: motif,
      commandeId: commandeId,
    );

class _CoursesFactices extends CourseService {
  _CoursesFactices(this.course);

  final CourseFirestore course;

  @override
  Stream<CourseFirestore?> streamCourse(String courseId) => Stream.value(course);
}

void main() {
  group('Navigation GPS', () {
    test('Google Maps : itinéraire vers les coordonnées exactes', () {
      final lien = NavigationGps.lien(AppNavigation.googleMaps, latitude: 14.668, longitude: -17.438);
      expect(lien.host, 'www.google.com');
      expect(lien.path, '/maps/dir/');
      expect(lien.queryParameters, {'api': '1', 'destination': '14.668,-17.438', 'travelmode': 'driving'});
    });

    test('Waze : navigation directe vers les coordonnées', () {
      final lien = NavigationGps.lien(AppNavigation.waze, latitude: 14.745, longitude: -17.517);
      expect(lien.toString(), 'https://waze.com/ul?ll=14.745%2C-17.517&navigate=yes');
    });

    test('course sans coordonnées : recherche par adresse', () {
      expect(
        NavigationGps.lien(AppNavigation.waze, adresse: 'Pointe des Almadies').queryParameters,
        {'q': 'Pointe des Almadies', 'navigate': 'yes'},
      );
      expect(
        NavigationGps.lien(AppNavigation.googleMaps, adresse: 'Plateau, Dakar').queryParameters['destination'],
        'Plateau, Dakar',
      );
    });
  });

  group('Bandeau de course : outils de conduite', () {
    testWidgets('"Naviguer" et "Annuler la course" ; annulation bloquée pendant une mise à jour', (tester) async {
      final appels = <String>[];
      Widget bandeau({required bool enCours}) => MaterialApp(
            home: Scaffold(
              bottomNavigationBar: CourseActiveBandeau(
                course: _course(StatutCourse.acceptee),
                enCours: enCours,
                onAvancer: () {},
                onAppeler: () {},
                onMessage: () {},
                onNaviguer: () => appels.add('naviguer'),
                onAnnuler: () => appels.add('annuler'),
              ),
            ),
          );
      await tester.pumpWidget(bandeau(enCours: false));
      await tester.tap(find.text('Naviguer'));
      await tester.tap(find.text('Annuler la course'));
      expect(appels, ['naviguer', 'annuler']);

      await tester.pumpWidget(bandeau(enCours: true));
      await tester.tap(find.text('Annuler la course'));
      expect(appels, ['naviguer', 'annuler']);
    });

    testWidgets('annulation : motif obligatoire, "Continuer la course" renonce', (tester) async {
      String? resultat = 'rien';
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => resultat = await demanderMotifAnnulation(context),
            child: const Text('Ouvrir'),
          ),
        ),
      ));

      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      final confirmer = find.widgetWithText(FilledButton, 'Annuler la course');
      expect(tester.widget<FilledButton>(confirmer).onPressed, isNull);

      await tester.tap(find.text('Client introuvable'));
      await tester.pump();
      await tester.tap(confirmer);
      await tester.pumpAndSettle();
      expect(resultat, MotifAnnulation.clientIntrouvable);

      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuer la course'));
      await tester.pumpAndSettle();
      expect(resultat, isNull);
    });

    testWidgets('choix de l\'application de guidage', (tester) async {
      AppNavigation? choix;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => choix = await choisirAppNavigation(context, destination: 'Plateau'),
            child: const Text('Ouvrir'),
          ),
        ),
      ));
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      expect(find.text('Google Maps'), findsOneWidget);
      await tester.tap(find.text('Waze'));
      await tester.pumpAndSettle();
      expect(choix, AppNavigation.waze);
    });
  });

  group('Client : course annulée par le chauffeur', () {
    testWidgets('le motif est expliqué au client', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SuiviCoursePage(
          courseId: 'c1',
          courseService: _CoursesFactices(
            _course(StatutCourse.annulee, annuleePar: 'chauffeur', motif: MotifAnnulation.panne),
          ),
          chatService: ChatService(),
          monUid: 'awa',
        ),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.text('Course annulée'), findsOneWidget);
      expect(find.textContaining('problème avec son véhicule'), findsOneWidget);
      expect(find.textContaining('commander une nouvelle course'), findsOneWidget);
    });

    testWidgets('annulation par le client lui-même : pas de message sur le chauffeur', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SuiviCoursePage(
          courseId: 'c1',
          courseService: _CoursesFactices(_course(StatutCourse.annulee)),
          chatService: ChatService(),
          monUid: 'awa',
        ),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.text('Course annulée'), findsOneWidget);
      expect(find.textContaining('Votre chauffeur'), findsNothing);
    });

    testWidgets('aucun chauffeur à temps : annulée par le serveur, client remboursé', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SuiviCoursePage(
          courseId: 'c1',
          courseService: _CoursesFactices(_course(
            StatutCourse.annulee,
            annuleePar: 'systeme',
            motif: MotifAnnulation.aucunChauffeur,
            commandeId: 'k1',
          )),
          chatService: ChatService(),
          monUid: 'awa',
        ),
      ));
      await tester.pump();
      await tester.pump();
      expect(
        find.text("Aucun chauffeur n'était disponible pour le moment. Votre paiement vous est remboursé. "
            'Vous pouvez commander une nouvelle course.'),
        findsOneWidget,
      );
    });
  });
}
