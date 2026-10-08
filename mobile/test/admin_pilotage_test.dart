import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/utils/format_fcfa.dart';
import 'package:sprint/features/admin/data/pilotage_service.dart';
import 'package:sprint/features/admin/presentation/sections/admin_clients_section.dart';
import 'package:sprint/features/admin/presentation/sections/admin_overview_section.dart';
import 'package:sprint/features/admin/presentation/sections/admin_parametres_section.dart';
import 'package:sprint/features/courses/data/course_service.dart';
import 'package:sprint/features/finances/data/comptabilite.dart';

// Dimanche 27/09/2026, 15 h à Dakar (UTC).
final _maintenant = DateTime.utc(2026, 9, 27, 15);

LigneCourse _terminee(String client, String chauffeur, int prix, DateTime date) => LigneCourse(
      courseId: '$client-$prix',
      chauffeurId: chauffeur,
      clientId: client,
      prixFcfa: prix,
      commissionFcfa: Commission.de(prix),
      methodePaiement: 'WAVE',
      date: date,
    );

UtilisateurAdmin _compte(String id, String role, String nom, DateTime? creeLe, {String? kyc, String email = ''}) =>
    UtilisateurAdmin(
      id: id,
      role: role,
      nom: nom,
      telephone: '77 000 00 ${id.length}',
      email: email,
      creeLe: creeLe,
      statutValidation: kyc,
    );

CourseFirestore _course(String id, String client, String? chauffeur, String statut, int prix, DateTime quand) =>
    CourseFirestore(
      id: id,
      clientId: client,
      chauffeurId: chauffeur,
      statut: statut,
      type: 'PASSAGER',
      adresseDepart: 'Plateau',
      adresseArrivee: 'Almadies',
      prixFcfa: prix,
      methodePaiement: 'WAVE',
      timestamp: quand,
    );

class _PilotageFactice extends PilotageService {
  @override
  Stream<List<LigneCourse>> streamCoursesTerminees() => Stream.value([
        _terminee('c1', 'moussa', 3000, DateTime.utc(2026, 9, 27, 9)), // aujourd'hui
        _terminee('c2', 'moussa', 2000, DateTime.utc(2026, 9, 27, 11)), // aujourd'hui
        _terminee('c1', 'awa', 4000, DateTime.utc(2026, 9, 22, 10)), // mardi
        _terminee('c1', 'moussa', 10000, DateTime.utc(2026, 9, 18, 10)), // il y a 9 jours
      ]);

  @override
  Stream<List<CourseFirestore>> streamDernieresCourses({int limite = 10}) => Stream.value([
        _course('k1', 'c3', null, StatutCourse.enAttente, 1500, DateTime.utc(2026, 9, 27, 14, 50)),
        _course('k2', 'c2', 'moussa', StatutCourse.terminee, 2000, DateTime.utc(2026, 9, 27, 10, 40)),
      ]);

  @override
  Stream<List<PositionChauffeurDirect>> streamPositions() => Stream.value([
        PositionChauffeurDirect(
            uid: 'moussa', latitude: 14.7, longitude: -17.4, majLe: _maintenant.subtract(const Duration(minutes: 1))),
        PositionChauffeurDirect(
            uid: 'awa', latitude: 14.7, longitude: -17.4, majLe: _maintenant.subtract(const Duration(minutes: 5))),
        PositionChauffeurDirect(
            uid: 'ibra', latitude: 14.7, longitude: -17.4, majLe: _maintenant.subtract(const Duration(hours: 2))),
      ]);

  @override
  Stream<List<UtilisateurAdmin>> streamUtilisateurs(String role) => Stream.value(switch (role) {
        'client' => [
            _compte('c1', 'client', 'Fatou Sow', DateTime.utc(2026, 9, 10), email: 'fatou@exemple.sn'),
            _compte('c2', 'client', 'Awa Diallo', DateTime.utc(2026, 9, 27, 8)),
            _compte('c3', 'client', 'Modou Fall', null),
          ],
        _ => [
            _compte('moussa', 'conducteur', 'Moussa Diop', DateTime.utc(2026, 9, 27, 7), kyc: 'valide'),
            _compte('awa', 'conducteur', 'Awa Ndiaye', DateTime.utc(2026, 9, 1), kyc: 'valide'),
            _compte('ibra', 'conducteur', 'Ibrahima Ba', DateTime.utc(2026, 9, 27, 12), kyc: 'en_attente'),
          ],
      });
}

Future<void> _afficher(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(1400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: page))));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Dashboard : tuiles, courbe et dernières courses tirées des données réelles', (tester) async {
    await _afficher(tester, AdminOverviewSection(service: _PilotageFactice(), maintenant: _maintenant));

    // CA du jour : 3 000 + 2 000.
    expect(find.text(formaterFcfa(5000)), findsOneWidget);
    expect(find.text('Commission Sprint : ${formaterFcfa(750)}'), findsOneWidget);
    // Courses terminées aujourd'hui / cette semaine (depuis lundi 21).
    expect(find.text('2'), findsWidgets);
    expect(find.text('3 cette semaine'), findsOneWidget);
    // Chauffeurs en ligne : signal < 2 min seulement.
    expect(find.text('1 signal perdu · 2 validés'), findsOneWidget);
    // Nouveaux inscrits aujourd'hui : Awa Diallo, Moussa, Ibrahima.
    expect(find.text('1 client · 2 chauffeurs'), findsOneWidget);
    // Courbe : 7 derniers jours (la course du 18 en est exclue).
    expect(find.text('3 courses au total, par jour.'), findsOneWidget);
    // Dernières courses, avec les vrais noms.
    expect(find.text('Modou Fall'), findsOneWidget);
    expect(find.text('—'), findsOneWidget); // pas encore de chauffeur
    expect(find.text('Moussa Diop'), findsOneWidget);
    expect(find.text('En attente'), findsOneWidget);
    expect(find.text('Terminée'), findsOneWidget);
    expect(find.text('27/09 14:50'), findsOneWidget);
    // Plus aucun chiffre de la maquette.
    expect(find.textContaining('1 284 500'), findsNothing);
    expect(find.text('342'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Clients : vrais inscrits, courses, dépenses et recherche', (tester) async {
    await _afficher(tester, AdminClientsSection(service: _PilotageFactice()));

    expect(find.text('3 inscrits'), findsOneWidget);
    expect(find.text('Fatou Sow'), findsOneWidget);
    expect(find.text('fatou@exemple.sn'), findsOneWidget);
    expect(find.text(formaterFcfa(17000)), findsOneWidget); // Fatou : 3 courses
    expect(find.text(formaterFcfa(2000)), findsOneWidget); // Awa Diallo : 1 course
    expect(find.text('10/09/2026'), findsOneWidget);
    // Les plus récents d'abord, comptes sans date à la fin.
    final y = [
      for (final nom in ['Awa Diallo', 'Fatou Sow', 'Modou Fall']) tester.getTopLeft(find.text(nom)).dy
    ];
    expect(y[0] < y[1] && y[1] < y[2], isTrue);

    await tester.enterText(find.byType(TextField), 'fatou');
    await tester.pump();
    expect(find.text('Fatou Sow'), findsOneWidget);
    expect(find.text('Awa Diallo'), findsNothing);

    await tester.enterText(find.byType(TextField), 'inconnu');
    await tester.pump();
    expect(find.text('Aucun client ne correspond à la recherche.'), findsOneWidget);
  });

  testWidgets('Paramètres : règles réellement appliquées, exemples calculés', (tester) async {
    await _afficher(tester, const AdminParametresSection(demo: false));
    expect(find.text('Règles en vigueur'), findsOneWidget);
    expect(find.text('Wave, solde Sprint (Orange Money bientôt)'), findsOneWidget);
    expect(find.text('15 % du prix'), findsOneWidget);
    // 300 + 5 x 200 = 1 300 ; x 1,2 en pointe = 1 560 -> 1 600 ; 300 + 15 x 200 = 3 300.
    expect(
      find.text('Exemples calculés : 5 km à midi = ${formaterFcfa(1300)} · 5 km à 8 h = '
          '${formaterFcfa(1600)} · 15 km à midi = ${formaterFcfa(3300)}.'),
      findsOneWidget,
    );
    expect(find.text('Mode maintenance'), findsNothing);
  });
}
