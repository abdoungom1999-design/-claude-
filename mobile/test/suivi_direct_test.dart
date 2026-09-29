import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sprint/features/admin/data/suivi_direct_service.dart';
import 'package:sprint/features/admin/presentation/sections/admin_courses_direct_section.dart';
import 'package:sprint/features/conducteur/data/position_chauffeur_service.dart';
import 'package:sprint/features/conducteur/presentation/widgets/course_active_bandeau.dart';
import 'package:sprint/features/courses/data/course_service.dart';

CourseFirestore _course(String id, String statut, {String chauffeurId = 'moussa', String type = 'PASSAGER'}) =>
    CourseFirestore(
      id: id,
      clientId: 'client',
      chauffeurId: chauffeurId,
      statut: statut,
      type: type,
      adresseDepart: 'Plateau',
      adresseArrivee: 'Almadies',
      prixFcfa: 2500,
      methodePaiement: 'WAVE',
      timestamp: DateTime(2026, 9, 26, 10),
    );

class _SuiviDirectFactice extends SuiviDirectService {
  _SuiviDirectFactice({required this.positions, required this.courses, this.erreur = false});

  final List<PositionChauffeurDirect> positions;
  final List<CourseFirestore> courses;
  final bool erreur;

  @override
  Stream<List<PositionChauffeurDirect>> streamPositions() =>
      erreur ? Stream.error(Exception('permission-denied')) : Stream.value(positions);

  @override
  Stream<List<CourseFirestore>> streamCoursesEnCours() =>
      erreur ? Stream.error(Exception('permission-denied')) : Stream.value(courses);

  @override
  Stream<Map<String, String>> streamNomsChauffeurs() =>
      Stream.value(const {'moussa': 'Moussa Diop', 'awa': 'Awa Ndiaye', 'fatou': 'Fatou Sarr'});
}

Future<void> _afficherSection(WidgetTester tester, SuiviDirectService service) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminCoursesDirectSection(service: service))));
  await tester.pump();
  await tester.pump();
}

void main() {
  group("Rythme d'envoi de la position", () {
    final t0 = DateTime(2026, 9, 26, 10);

    test('premier envoi immédiat, puis au plus un toutes les 5 s', () {
      final limiteur = LimiteurEnvoiPosition();
      expect(limiteur.peutEnvoyer(t0), isTrue);
      limiteur.enregistrerEnvoi(t0);
      expect(limiteur.peutEnvoyer(t0.add(const Duration(seconds: 4))), isFalse);
      expect(limiteur.peutEnvoyer(t0.add(const Duration(seconds: 5))), isTrue);
    });

    test('battement de coeur toutes les 30 s même immobile', () {
      final limiteur = LimiteurEnvoiPosition()..enregistrerEnvoi(t0);
      expect(limiteur.battementDu(t0.add(const Duration(seconds: 29))), isFalse);
      expect(limiteur.battementDu(t0.add(const Duration(seconds: 30))), isTrue);
    });
  });

  group('Suivi GPS du chauffeur en ligne', () {
    test('APK Android : service de premier plan, le GPS continue écran verrouillé', () {
      final reglages = PositionChauffeurService.reglagesSuivi(android: true);
      expect(reglages, isA<AndroidSettings>());
      final notification = (reglages as AndroidSettings).foregroundNotificationConfig;
      expect(notification, isNotNull);
      expect(notification!.notificationTitle, 'Sprint : vous êtes en ligne');
      expect(notification.enableWakeLock, isTrue);
      expect(reglages.distanceFilter, 10);
    });

    test('web : réglages simples (le navigateur ne permet pas mieux)', () {
      final reglages = PositionChauffeurService.reglagesSuivi(android: false);
      expect(reglages, isNot(isA<AndroidSettings>()));
      expect(reglages.accuracy, LocationAccuracy.high);
      expect(reglages.distanceFilter, 10);
    });
  });

  group('Fraîcheur du signal', () {
    final maintenant = DateTime(2026, 9, 26, 10);

    test('actif < 2 min, perdu < 30 min, expiré au-delà', () {
      expect(EtatSignal.pour(maintenant.subtract(const Duration(seconds: 90)), maintenant), EtatSignal.actif);
      expect(EtatSignal.pour(maintenant.subtract(const Duration(minutes: 2)), maintenant), EtatSignal.perdu);
      expect(EtatSignal.pour(maintenant.subtract(const Duration(minutes: 30)), maintenant), EtatSignal.expire);
      expect(EtatSignal.pour(null, maintenant), EtatSignal.actif);
    });

    test('libellés "il y a"', () {
      expect(ilYA(maintenant.subtract(const Duration(seconds: 2)), maintenant), "à l'instant");
      expect(ilYA(maintenant.subtract(const Duration(seconds: 45)), maintenant), 'il y a 45 s');
      expect(ilYA(maintenant.subtract(const Duration(minutes: 3)), maintenant), 'il y a 3 min');
    });
  });

  group('Admin : Courses en direct', () {
    testWidgets('affiche les vraies courses et les chauffeurs selon leur signal', (tester) async {
      final maintenant = DateTime.now();
      await _afficherSection(
        tester,
        _SuiviDirectFactice(
          positions: [
            PositionChauffeurDirect(uid: 'moussa', latitude: 14.69, longitude: -17.44, majLe: maintenant),
            PositionChauffeurDirect(
              uid: 'awa',
              latitude: 14.70,
              longitude: -17.47,
              majLe: maintenant.subtract(const Duration(minutes: 5)),
            ),
            // Plus de 30 min sans signal : retiré de la carte.
            PositionChauffeurDirect(
              uid: 'fatou',
              latitude: 14.72,
              longitude: -17.48,
              majLe: maintenant.subtract(const Duration(hours: 1)),
            ),
          ],
          courses: [
            _course('abcdef123', StatutCourse.enCours),
            _course('zyx987654', StatutCourse.acceptee, chauffeurId: 'sansPosition'),
          ],
        ),
      );

      expect(find.text('2 courses en cours'), findsOneWidget);
      expect(find.text('Course ABCDEF'), findsOneWidget);
      expect(find.text('Chauffeur : Moussa Diop'), findsOneWidget);
      expect(find.text('Plateau → Almadies'), findsNWidgets(2));
      expect(find.text('En course'), findsOneWidget);
      expect(find.text('Vers le client'), findsOneWidget);
      expect(find.text('Aucune position reçue'), findsOneWidget);
      expect(find.text('En course : 1'), findsOneWidget);
      expect(find.text('Disponibles : 0'), findsOneWidget);
      expect(find.text('Signal perdu : 1'), findsOneWidget);
      // Marqueurs : Moussa (en course) et Awa (signal perdu) ; Fatou masquée.
      expect(find.byIcon(Icons.two_wheeler_rounded), findsOneWidget);
      expect(find.byIcon(Icons.signal_wifi_off_rounded), findsOneWidget);
    });

    testWidgets('aucune donnée : états vides explicites', (tester) async {
      await _afficherSection(tester, _SuiviDirectFactice(positions: const [], courses: const []));
      expect(find.text('0 course en cours'), findsOneWidget);
      expect(find.text('Aucune course en cours.'), findsOneWidget);
      expect(find.text('Aucun chauffeur en ligne pour le moment'), findsOneWidget);
    });

    testWidgets('lecture refusée : message explicite au lieu de données factices', (tester) async {
      await _afficherSection(tester, _SuiviDirectFactice(positions: const [], courses: const [], erreur: true));
      expect(find.textContaining('Lecture impossible'), findsOneWidget);
    });
  });

  group('Chauffeur : bandeau de course en cours', () {
    Future<List<String>> appuyer(WidgetTester tester, CourseFirestore course, String bouton) async {
      final appels = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          bottomNavigationBar: CourseActiveBandeau(
            course: course,
            enCours: false,
            onAvancer: () => appels.add(bouton),
            onAppeler: () => appels.add('appel'),
            onMessage: () => appels.add('message'),
            onNaviguer: () => appels.add('naviguer'),
            onAnnuler: () => appels.add('annuler'),
          ),
        ),
      ));
      await tester.tap(find.text(bouton));
      return appels;
    }

    testWidgets('course acceptée : "Client à bord"', (tester) async {
      expect(await appuyer(tester, _course('c', StatutCourse.acceptee), 'Client à bord'), ['Client à bord']);
      expect(find.text('Rejoignez votre client'), findsOneWidget);
    });

    testWidgets('client à bord : "Terminer la course"', (tester) async {
      expect(await appuyer(tester, _course('c', StatutCourse.enCours), 'Terminer la course'), ['Terminer la course']);
      expect(find.text('Vers Almadies'), findsOneWidget);
    });

    testWidgets('colis : "Colis récupéré"', (tester) async {
      final course = _course('c', StatutCourse.acceptee, type: 'COLIS');
      expect(await appuyer(tester, course, 'Colis récupéré'), ['Colis récupéré']);
    });
  });
}
