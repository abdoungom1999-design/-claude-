import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/models/statut_compte.dart';
import 'package:sprint/core/utils/format_fcfa.dart';
import 'package:sprint/features/activite/presentation/activite_tab_page.dart';
import 'package:sprint/features/activite/presentation/detail_course_page.dart';
import 'package:sprint/features/admin/data/admin_kyc_service.dart';
import 'package:sprint/features/admin/presentation/admin_ticket_page.dart';
import 'package:sprint/features/admin/presentation/sections/admin_support_section.dart';
import 'package:sprint/features/courses/data/course_service.dart';
import 'package:sprint/features/support/data/support_service.dart';
import 'package:sprint/features/support/presentation/signalement_page.dart';

CourseFirestore _course(String id, String statut, {String type = 'PASSAGER', String? commandeId = 'k1', DateTime? rembourseeLe}) =>
    CourseFirestore(
      id: id,
      clientId: 'awa',
      chauffeurId: 'moussa',
      statut: statut,
      type: type,
      adresseDepart: 'Plateau',
      adresseArrivee: 'Almadies',
      prixFcfa: 2300,
      methodePaiement: 'WAVE',
      timestamp: DateTime(2026, 9, 28, 18, 30),
      commandeId: commandeId,
      rembourseeLe: rembourseeLe,
    );

TicketSupport _ticket({String statut = StatutTicket.ouvert, bool nonLuAdmin = true, bool nonLuClient = false, String courseId = 'c1'}) =>
    TicketSupport(
      courseId: courseId,
      clientId: 'awa',
      chauffeurId: 'moussa',
      categorie: CategorieTicket.chauffeur,
      statut: statut,
      creeLe: DateTime(2026, 9, 28, 19),
      majLe: DateTime.now(),
      dernierMessage: 'Le chauffeur était impoli',
      nonLuAdmin: nonLuAdmin,
      nonLuClient: nonLuClient,
    );

final _messages = [
  MessageTicket(id: 'm1', auteurId: 'awa', auteurRole: AuteurMessage.client, texte: 'Le chauffeur était impoli', creeLe: DateTime(2026, 9, 28, 19)),
  MessageTicket(id: 'm2', auteurId: 'chef', auteurRole: AuteurMessage.admin, texte: 'Nous regardons.', creeLe: DateTime(2026, 9, 28, 19, 5)),
  MessageTicket(
    id: 'm3',
    auteurId: 'systeme',
    auteurRole: AuteurMessage.systeme,
    texte: 'Votre course a été remboursée intégralement (2300 FCFA).',
    creeLe: DateTime(2026, 9, 28, 19, 6),
  ),
];

/// Support factice : enregistre les appels, sans Firebase.
class _SupportFactice extends SupportService {
  _SupportFactice({this.ticket, this.tickets = const []});

  final TicketSupport? ticket;
  final List<TicketSupport> tickets;
  final appels = <String>[];
  (String, String, String)? ticketOuvert;

  @override
  Stream<TicketSupport?> streamTicket(String courseId) => Stream.value(ticket);

  @override
  Stream<List<MessageTicket>> streamMessages(String courseId) => Stream.value(_messages);

  @override
  Stream<List<TicketSupport>> streamTickets() => Stream.value(tickets);

  @override
  Future<void> ouvrirTicket({
    required CourseFirestore course,
    required String clientId,
    required String categorie,
    required String texte,
  }) async =>
      ticketOuvert = (course.id, categorie, texte);

  @override
  Future<void> envoyerMessageClient(String courseId, String clientId, String texte) async =>
      appels.add('client:$courseId:$texte');

  @override
  Future<void> marquerLuParClient(String courseId) async => appels.add('lu-client:$courseId');

  @override
  Future<void> envoyerMessageAdmin(String courseId, String adminId, String texte) async =>
      appels.add('admin:$courseId:$adminId:$texte');

  @override
  Future<void> marquerLuParAdmin(String courseId) async => appels.add('lu-admin:$courseId');

  @override
  Future<void> definirStatut(String courseId, String statut) async => appels.add('statut:$statut');

  @override
  Future<RemboursementEffectue> rembourser(String courseId, String motif) async {
    appels.add('rembourser:$courseId:$motif');
    return const RemboursementEffectue(rembourse: true, montantFcfa: 2300, partChauffeurRetireeFcfa: 1955);
  }
}

class _CoursesFactices extends CourseService {
  _CoursesFactices({this.courses = const [], this.course});

  final List<CourseFirestore> courses;
  final CourseFirestore? course;

  @override
  Stream<List<CourseFirestore>> streamCoursesClient(String clientId) => Stream.value(courses);

  @override
  Stream<CourseFirestore?> streamCourse(String courseId) => Stream.value(course);

  @override
  Stream<CommandePaiement?> streamCommande(String commandeId) =>
      Stream.value(const CommandePaiement(statut: 'payee', courseId: 'c1'));
}

class _KycFactice extends AdminKycService {
  final sanctions = <(String, String, String?)>[];

  @override
  Stream<ConducteurKycAdmin?> streamConducteur(String uid) => Stream.value(ConducteurKycAdmin(
        id: uid,
        nom: 'Moussa Diop',
        telephone: '+221770000001',
        vehiculeId: 'Yamaha',
        plaqueImmatriculation: 'DK-1',
        statutValidation: 'valide',
        statutCompte: StatutCompte.actif,
        documents: const {},
      ));

  @override
  Future<SanctionAppliquee> definirStatutCompte(String uid, String statut, {String? motif}) async {
    sanctions.add((uid, statut, motif));
    return const SanctionAppliquee(coursesAnnulees: 1, remboursements: 1);
  }
}

void main() {
  group('Client : Activité réelle et signalement', () {
    testWidgets('Activité : course en cours à suivre, historique réel, détail avec "Signaler un problème"', (tester) async {
      final courses = _CoursesFactices(courses: [_course('c0', StatutCourse.acceptee), _course('c1', StatutCourse.terminee)]);
      await tester.pumpWidget(MaterialApp(
        home: ActiviteTabPage(courseService: courses, clientId: 'awa', supportService: _SupportFactice()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Chauffeur en route'), findsOneWidget);
      expect(find.text('Suivre ma course'), findsOneWidget);
      expect(find.textContaining('Terminée'), findsOneWidget);

      await tester.tap(find.textContaining('Terminée'));
      await tester.pumpAndSettle();
      expect(find.byType(DetailCoursePage), findsOneWidget);
    });

    testWidgets('Détail : "Signaler un problème" sans ticket, "Nouvelle réponse du support" avec réponse non lue', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: DetailCoursePage(course: _course('c1', StatutCourse.terminee), clientId: 'awa', supportService: _SupportFactice()),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Signaler un problème'), findsOneWidget);

      await tester.pumpWidget(MaterialApp(
        home: DetailCoursePage(
          key: const ValueKey('avec-ticket'),
          course: _course('c1', StatutCourse.terminee),
          clientId: 'awa',
          supportService: _SupportFactice(ticket: _ticket(nonLuClient: true)),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Nouvelle réponse du support'), findsOneWidget);
    });

    testWidgets('Signalement : motif et description obligatoires, puis ticket ouvert avec le premier message', (tester) async {
      final support = _SupportFactice();
      await tester.pumpWidget(MaterialApp(
        home: SignalementPage(course: _course('c1', StatutCourse.terminee), clientId: 'awa', service: support),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Envoyer au support'));
      await tester.pump();
      expect(find.text('Choisissez le type de problème.'), findsOneWidget);

      await tester.tap(find.text('Objet perdu'));
      await tester.pump();
      await tester.tap(find.text('Envoyer au support'));
      await tester.pump();
      expect(find.text('Décrivez le problème en quelques mots.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), "J'ai oublié mon sac dans le coffre");
      await tester.tap(find.text('Envoyer au support'));
      await tester.pumpAndSettle();
      expect(support.ticketOuvert, ('c1', CategorieTicket.objetPerdu, "J'ai oublié mon sac dans le coffre"));
    });

    testWidgets('Signalement ouvert : conversation, réponse lue, message du client envoyé', (tester) async {
      final support = _SupportFactice(ticket: _ticket(nonLuClient: true));
      await tester.pumpWidget(MaterialApp(
        home: SignalementPage(course: _course('c1', StatutCourse.terminee), clientId: 'awa', service: support),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Problème avec le chauffeur · En cours de traitement'), findsOneWidget);
      expect(find.text('Nous regardons.'), findsOneWidget);
      expect(find.text('Support Sprint'), findsOneWidget);
      expect(find.text('Votre course a été remboursée intégralement (2300 FCFA).'), findsOneWidget);
      expect(support.appels, contains('lu-client:c1'));

      await tester.enterText(find.byType(TextField), 'Merci !');
      await tester.tap(find.byTooltip('Envoyer'));
      await tester.pumpAndSettle();
      expect(support.appels, contains('client:c1:Merci !'));
    });
  });

  group('Admin : file et traitement des tickets', () {
    Future<void> afficher(WidgetTester tester, Widget page) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: page));
      await tester.pumpAndSettle();
    }

    testWidgets('File : à traiter / résolus, non lus signalés, ouverture du ticket', (tester) async {
      final ouverts = <String>[];
      await afficher(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: AdminSupportSection(
              demo: false,
              service: _SupportFactice(tickets: [
                _ticket(courseId: 'c1'),
                _ticket(courseId: 'c2', statut: StatutTicket.resolu, nonLuAdmin: false),
              ]),
              ouvrirTicket: (_, courseId) => ouverts.add(courseId),
            ),
          ),
        ),
      );
      expect(find.text('1 à traiter · 1 non lu(s)'), findsOneWidget);
      expect(find.text('Nouveau'), findsOneWidget);
      expect(find.text('Résolu'), findsNothing);

      await tester.tap(find.text('Résolus'));
      await tester.pumpAndSettle();
      expect(find.text('Nouveau'), findsNothing);
      expect(find.text('Résolu'), findsOneWidget);

      await tester.tap(find.text('Le chauffeur était impoli'));
      expect(ouverts, ['c2']);
    });

    testWidgets('Ticket : fiche de la course, lu à l\'ouverture, réponse, remboursement avec motif, suspension, clôture', (tester) async {
      final support = _SupportFactice(ticket: _ticket());
      final kyc = _KycFactice();
      await afficher(
        tester,
        AdminTicketPage(
          courseId: 'c1',
          adminId: 'chef',
          supportService: support,
          courseService: _CoursesFactices(course: _course('c1', StatutCourse.terminee)),
          kycService: kyc,
          chargerProfil: (uid) async => {'nom': 'Awa Diallo', 'telephone': '+221770000009'},
        ),
      );

      expect(find.text('Plateau'), findsOneWidget);
      expect(find.text('Awa Diallo'), findsOneWidget);
      expect(find.text('Payée'), findsOneWidget);
      expect(support.appels, contains('lu-admin:c1'));

      await tester.enterText(find.byType(TextField), 'Nous avons remboursé votre course.');
      await tester.tap(find.byTooltip('Envoyer'));
      await tester.pumpAndSettle();
      expect(support.appels, contains('admin:c1:chef:Nous avons remboursé votre course.'));

      await tester.tap(find.textContaining('Rembourser'));
      await tester.pumpAndSettle();
      // Course terminée : 85 % de 2 300 (commission 345) ne seront pas payés au chauffeur.
      expect(find.textContaining('sa part (${formaterFcfa(1955)}) est retirée'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Rembourser'));
      await tester.pumpAndSettle();
      expect(find.text('Indiquez le motif.'), findsOneWidget);
      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'Chauffeur impoli');
      await tester.tap(find.widgetWithText(FilledButton, 'Rembourser'));
      await tester.pumpAndSettle();
      expect(support.appels, contains('rembourser:c1:Chauffeur impoli'));
      expect(find.textContaining('Part du chauffeur retirée : ${formaterFcfa(1955)}.'), findsOneWidget);

      await tester.tap(find.text('Suspendre le chauffeur'));
      await tester.pumpAndSettle();
      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'Plaintes répétées');
      await tester.tap(find.widgetWithText(FilledButton, 'Suspendre'));
      await tester.pumpAndSettle();
      expect(kyc.sanctions, [('moussa', StatutCompte.suspendu, 'Plaintes répétées')]);

      await tester.tap(find.text('Marquer résolu'));
      await tester.pumpAndSettle();
      expect(support.appels, contains('statut:${StatutTicket.resolu}'));
    });

    testWidgets('Ticket : course en cours ou déjà remboursée, pas de bouton de remboursement', (tester) async {
      await afficher(
        tester,
        AdminTicketPage(
          courseId: 'c1',
          adminId: 'chef',
          supportService: _SupportFactice(ticket: _ticket()),
          courseService: _CoursesFactices(course: _course('c1', StatutCourse.enCours)),
          kycService: _KycFactice(),
          chargerProfil: (uid) async => null,
        ),
      );
      expect(find.text('Course en cours : remboursable une fois terminée ou annulée.'), findsOneWidget);

      await afficher(
        tester,
        AdminTicketPage(
          key: const ValueKey('remboursee'),
          courseId: 'c1',
          adminId: 'chef',
          supportService: _SupportFactice(ticket: _ticket()),
          courseService: _CoursesFactices(course: _course('c1', StatutCourse.terminee, rembourseeLe: DateTime(2026, 9, 29))),
          kycService: _KycFactice(),
          chargerProfil: (uid) async => null,
        ),
      );
      expect(find.text('Course déjà remboursée.'), findsOneWidget);
    });
  });
}
