import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/notifications/capacites_navigateur.dart';
import 'package:sprint/core/notifications/carte_notifications.dart';
import 'package:sprint/core/notifications/notifications_push.dart';

class _Passerelle implements PasserellePush {
  bool autorise = true;
  bool navigateurCompatible = true;
  EtatAutorisation etat = EtatAutorisation.aDemander;
  String? jetonCourant = 'jeton-1';
  var autorisationsDemandees = 0;
  var jetonsSupprimes = 0;
  Object? erreurJeton;
  MessagePush? initial;
  final renouvellements = StreamController<String>.broadcast();
  final appuis = StreamController<MessagePush>.broadcast();

  @override
  Future<bool> supporte() async => navigateurCompatible;

  @override
  Future<EtatAutorisation> etatAutorisation() async => etat;

  @override
  Future<bool> demanderAutorisation() async {
    autorisationsDemandees++;
    return autorise;
  }

  @override
  Future<String?> jeton() async {
    if (erreurJeton != null) throw erreurJeton!;
    return jetonCourant;
  }

  @override
  Stream<String> get jetonRenouvele => renouvellements.stream;

  @override
  Future<void> supprimerJeton() async => jetonsSupprimes++;

  @override
  Stream<MessagePush> get ouvertures => appuis.stream;

  @override
  Future<MessagePush?> messageInitial() async => initial;
}

class _Stockage implements StockageJetons {
  final enregistres = <(String, String)>[];
  final supprimes = <(String, String)>[];
  bool refuse = false;

  @override
  Future<void> enregistrer(String uid, String jeton) async {
    if (refuse) throw Exception('permission-denied');
    enregistres.add((uid, jeton));
  }

  @override
  Future<void> supprimer(String uid, String jeton) async => supprimes.add((uid, jeton));
}

Future<void> _laisser() => Future<void>.delayed(Duration.zero);

void main() {
  late _Passerelle passerelle;
  late _Stockage stockage;
  late List<MessagePush> appuis;

  NotificationsPush service(PlateformePush plateforme, {CapacitesNavigateur navigateur = const CapacitesNavigateur()}) =>
      NotificationsPush(passerelle: passerelle, stockage: stockage, plateforme: plateforme, capacites: () => navigateur);

  setUp(() {
    passerelle = _Passerelle();
    stockage = _Stockage();
    appuis = [];
  });

  group('APK Android', () {
    late NotificationsPush push;
    setUp(() => push = service(PlateformePush.android));

    test('connexion : autorisation demandée, puis jeton enregistré pour ce compte', () async {
      await push.activer(uid: 'awa', surAppui: appuis.add);
      expect(passerelle.autorisationsDemandees, 1);
      expect(stockage.enregistres, [('awa', 'jeton-1')]);
      expect(push.uid, 'awa');
      expect(push.etat.value, EtatNotifications.activees);
    });

    test('jeton renouvelé par Google : réenregistré', () async {
      await push.activer(uid: 'awa', surAppui: appuis.add);
      passerelle.renouvellements.add('jeton-2');
      await _laisser();
      expect(stockage.enregistres, [('awa', 'jeton-1'), ('awa', 'jeton-2')]);
    });

    test('autorisation refusée : rien n\'est enregistré, état « bloquées »', () async {
      passerelle.autorise = false;
      await push.activer(uid: 'awa', surAppui: appuis.add);
      expect(stockage.enregistres, isEmpty);
      expect(push.etat.value, EtatNotifications.bloquees);
    });

    test('activer deux fois pour le même compte : une seule demande, un seul enregistrement', () async {
      await push.activer(uid: 'awa', surAppui: appuis.add);
      await push.activer(uid: 'awa', surAppui: appuis.add);
      expect(passerelle.autorisationsDemandees, 1);
      expect(stockage.enregistres.length, 1);
    });

    test('déconnexion : jeton supprimé (base et Google), plus de renouvellement enregistré', () async {
      await push.activer(uid: 'awa', surAppui: appuis.add);
      await push.desactiver();
      expect(stockage.supprimes, [('awa', 'jeton-1')]);
      expect(passerelle.jetonsSupprimes, 1);
      expect(push.uid, isNull);
      expect(push.etat.value, EtatNotifications.inconnu);

      passerelle.renouvellements.add('jeton-3');
      await _laisser();
      expect(stockage.enregistres.length, 1);
      await push.desactiver();
      expect(stockage.supprimes.length, 1);
    });

    test('changement de compte : le jeton de l\'ancien compte est supprimé avant celui du nouveau', () async {
      await push.activer(uid: 'awa', surAppui: appuis.add);
      passerelle.jetonCourant = 'jeton-2';
      await push.activer(uid: 'moussa', surAppui: appuis.add);
      expect(stockage.supprimes, [('awa', 'jeton-1')]);
      expect(stockage.enregistres, [('awa', 'jeton-1'), ('moussa', 'jeton-2')]);
    });

    test('appui sur une notification : transmis avec son contenu, plus rien après la déconnexion', () async {
      passerelle.initial = const MessagePush({'type': 'acceptee', 'courseId': 'c1'});
      await push.activer(uid: 'awa', surAppui: appuis.add);
      expect(appuis.single.type, 'acceptee');
      expect(appuis.single.courseId, 'c1');

      passerelle.appuis.add(const MessagePush({'type': 'message', 'expediteurId': 'moussa'}));
      await _laisser();
      expect(appuis.length, 2);

      await push.desactiver();
      passerelle.appuis.add(const MessagePush({'type': 'message'}));
      await _laisser();
      expect(appuis.length, 2);
    });

    test('aucun problème de notification ne fait échouer l\'app : jeton illisible, base qui refuse', () async {
      passerelle.erreurJeton = Exception('SERVICE_NOT_AVAILABLE');
      await push.activer(uid: 'awa', surAppui: appuis.add);
      expect(stockage.enregistres, isEmpty);

      final autre = NotificationsPush(
        passerelle: _Passerelle(),
        stockage: _Stockage()..refuse = true,
        plateforme: PlateformePush.android,
      );
      await autre.activer(uid: 'awa', surAppui: appuis.add);
      await autre.desactiver();
    });
  });

  group('Site (navigateur, iPhone installé)', () {
    test('autorisation jamais demandée sans appui : état « à activer », aucun jeton', () async {
      final push = service(PlateformePush.web);
      await push.activer(uid: 'awa', surAppui: appuis.add);
      expect(passerelle.autorisationsDemandees, 0);
      expect(stockage.enregistres, isEmpty);
      expect(push.etat.value, EtatNotifications.aActiver);
    });

    test('à l\'appui sur le bouton : autorisation demandée puis jeton enregistré (plateforme web)', () async {
      final push = service(PlateformePush.web);
      await push.activer(uid: 'awa', surAppui: appuis.add);
      await push.demander();
      expect(passerelle.autorisationsDemandees, 1);
      expect(stockage.enregistres, [('awa', 'jeton-1')]);
      expect(push.etat.value, EtatNotifications.activees);
    });

    test('déjà autorisé (visite suivante) : jeton enregistré tout de suite, sans redemander', () async {
      passerelle.etat = EtatAutorisation.accordee;
      final push = service(PlateformePush.web);
      await push.activer(uid: 'awa', surAppui: appuis.add);
      expect(passerelle.autorisationsDemandees, 0);
      expect(stockage.enregistres, [('awa', 'jeton-1')]);
      expect(push.etat.value, EtatNotifications.activees);
    });

    test('refus du navigateur : « bloquées », pas de jeton', () async {
      passerelle.autorise = false;
      final push = service(PlateformePush.web);
      await push.activer(uid: 'awa', surAppui: appuis.add);
      await push.demander();
      expect(push.etat.value, EtatNotifications.bloquees);
      expect(stockage.enregistres, isEmpty);

      passerelle.etat = EtatAutorisation.refusee;
      final suivant = service(PlateformePush.web);
      await suivant.activer(uid: 'awa', surAppui: appuis.add);
      expect(suivant.etat.value, EtatNotifications.bloquees);
    });

    test('iPhone dans Safari (site non installé) : consigne d\'installation, aucune demande', () async {
      final push = service(PlateformePush.web, navigateur: const CapacitesNavigateur(iphone: true));
      await push.activer(uid: 'awa', surAppui: appuis.add);
      await push.demander();
      expect(push.etat.value, EtatNotifications.iphoneHorsEcranAccueil);
      expect(passerelle.autorisationsDemandees, 0);
      expect(stockage.enregistres, isEmpty);
    });

    test('iPhone, site installé sur l\'écran d\'accueil : l\'activation est possible', () async {
      final push = service(PlateformePush.web, navigateur: const CapacitesNavigateur(iphone: true, ecranAccueil: true));
      await push.activer(uid: 'awa', surAppui: appuis.add);
      expect(push.etat.value, EtatNotifications.aActiver);
      await push.demander();
      expect(stockage.enregistres, [('awa', 'jeton-1')]);
    });

    test('navigateur sans notifications : état « non supportées », aucune demande', () async {
      passerelle.navigateurCompatible = false;
      final push = service(PlateformePush.web);
      await push.activer(uid: 'awa', surAppui: appuis.add);
      await push.demander();
      expect(push.etat.value, EtatNotifications.nonSupportees);
      expect(passerelle.autorisationsDemandees, 0);
    });

    test('déconnexion : le jeton du site est supprimé aussi', () async {
      passerelle.etat = EtatAutorisation.accordee;
      final push = service(PlateformePush.web);
      await push.activer(uid: 'awa', surAppui: appuis.add);
      await push.desactiver();
      expect(stockage.supprimes, [('awa', 'jeton-1')]);
      expect(passerelle.jetonsSupprimes, 1);
    });

    test('appui sur la notification du site : transmis (route choisie par l\'app)', () async {
      passerelle.etat = EtatAutorisation.accordee;
      final push = service(PlateformePush.web);
      await push.activer(uid: 'awa', surAppui: appuis.add);
      passerelle.appuis.add(const MessagePush({'type': 'message'}));
      await _laisser();
      expect(appuis.single.type, 'message');
    });
  });

  test('ni APK Android ni site (tests, autres systèmes) : aucune demande, aucun enregistrement', () async {
    final push = service(PlateformePush.aucune);
    await push.activer(uid: 'awa', surAppui: appuis.add);
    await push.demander();
    await push.desactiver();
    expect(passerelle.autorisationsDemandees, 0);
    expect(stockage.enregistres, isEmpty);
    expect(passerelle.jetonsSupprimes, 0);
    expect(push.etat.value, EtatNotifications.inconnu);
  });

  group('Carte « Notifications »', () {
    Future<NotificationsPush> afficher(
      WidgetTester tester, {
      PlateformePush plateforme = PlateformePush.web,
      CapacitesNavigateur navigateur = const CapacitesNavigateur(),
      bool enBandeau = false,
    }) async {
      final push = service(plateforme, navigateur: navigateur);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: CarteNotifications(push: push, enBandeau: enBandeau))),
      ));
      await push.activer(uid: 'awa', surAppui: (_) {});
      await tester.pump();
      return push;
    }

    testWidgets('à activer : bouton ; l\'appui active et la carte confirme', (tester) async {
      await afficher(tester);
      expect(find.text('Activez les notifications'), findsOneWidget);
      await tester.tap(find.text('Activer les notifications'));
      await tester.pump();
      await tester.pump();
      expect(passerelle.autorisationsDemandees, 1);
      expect(find.text('Notifications activées'), findsOneWidget);
      expect(find.text('Activer les notifications'), findsNothing);
    });

    testWidgets('iPhone dans Safari : la marche à suivre pour installer le site', (tester) async {
      await afficher(tester, navigateur: const CapacitesNavigateur(iphone: true));
      expect(find.text('Installez Sprint sur votre iPhone'), findsOneWidget);
      expect(find.textContaining("Sur l'écran d'accueil"), findsOneWidget);
      expect(find.text('Activer les notifications'), findsNothing);
    });

    testWidgets('bloquées : explique où les rouvrir, sans bouton', (tester) async {
      passerelle.etat = EtatAutorisation.refusee;
      await afficher(tester);
      expect(find.text('Notifications bloquées'), findsOneWidget);
      expect(find.textContaining('réglages de votre navigateur'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('en bandeau : visible seulement s\'il y a quelque chose à faire', (tester) async {
      final push = await afficher(tester, enBandeau: true);
      expect(find.text('Activez les notifications'), findsOneWidget);
      await push.demander();
      await tester.pump();
      expect(find.text('Notifications activées'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('pas de compte connecté (mode démo) : rien d\'affiché', (tester) async {
      final push = service(PlateformePush.web);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: CarteNotifications(push: push))));
      expect(find.byType(FilledButton), findsNothing);
      expect(find.textContaining('notifications'), findsNothing);
    });
  });
}
