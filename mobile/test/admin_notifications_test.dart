import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/notifications/capacites_navigateur.dart';
import 'package:sprint/core/notifications/carte_notifications.dart';
import 'package:sprint/core/notifications/notifications_push.dart';
import 'package:sprint/core/widgets/app_card.dart';
import 'package:sprint/features/admin/presentation/admin_dashboard_page.dart';
import 'package:sprint/features/admin/presentation/sections/admin_parametres_section.dart';

class _Passerelle implements PasserellePush {
  EtatAutorisation etat = EtatAutorisation.aDemander;
  var autorisationsDemandees = 0;
  final renouvellements = StreamController<String>.broadcast();
  final appuis = StreamController<MessagePush>.broadcast();

  @override
  Future<bool> supporte() async => true;

  @override
  Future<EtatAutorisation> etatAutorisation() async => etat;

  @override
  Future<bool> demanderAutorisation() async {
    autorisationsDemandees++;
    return true;
  }

  @override
  Future<String?> jeton() async => 'jeton-admin';

  @override
  Stream<String> get jetonRenouvele => renouvellements.stream;

  @override
  Future<void> supprimerJeton() async {}

  @override
  Stream<MessagePush> get ouvertures => appuis.stream;

  @override
  Future<MessagePush?> messageInitial() async => null;
}

class _Stockage implements StockageJetons {
  final enregistres = <(String, String)>[];

  @override
  Future<void> enregistrer(String uid, String jeton) async => enregistres.add((uid, jeton));

  @override
  Future<void> supprimer(String uid, String jeton) async {}
}

void main() {
  late _Passerelle passerelle;
  late _Stockage stockage;

  NotificationsPush service(PlateformePush plateforme) => NotificationsPush(
        passerelle: passerelle,
        stockage: stockage,
        plateforme: plateforme,
        capacites: () => const CapacitesNavigateur(),
      );

  setUp(() {
    passerelle = _Passerelle();
    stockage = _Stockage();
  });

  Future<void> afficherParametres(WidgetTester tester, NotificationsPush push) async {
    tester.view.physicalSize = const Size(1000, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: AdminParametresSection(demo: false, push: push))),
    ));
    await tester.pumpAndSettle();
  }

  group('Admin > Paramètres', () {
    testWidgets('site : la carte propose d\'activer les alertes, entre les règles et le stockage KYC', (tester) async {
      final push = service(PlateformePush.web);
      await push.activer(uid: 'admin1', surAppui: (_) {});
      await afficherParametres(tester, push);

      expect(find.text('Activez les notifications'), findsOneWidget);
      expect(find.text('Recevez les alertes importantes, comme un problème de sauvegarde de la base.'), findsOneWidget);
      expect(find.text('Activer les notifications'), findsOneWidget);

      final regles = tester.getTopLeft(find.text('Règles en vigueur')).dy;
      final carte = tester.getTopLeft(find.text('Activez les notifications')).dy;
      final kyc = tester.getTopLeft(find.text('Stockage des documents KYC')).dy;
      expect(carte, greaterThan(regles));
      expect(kyc, greaterThan(carte));
      expect(stockage.enregistres, isEmpty, reason: 'rien n\'est enregistré avant l\'appui sur le bouton');
    });

    testWidgets('le bouton demande l\'autorisation, enregistre l\'appareil de l\'Admin, et la carte confirme', (tester) async {
      final push = service(PlateformePush.web);
      await push.activer(uid: 'admin1', surAppui: (_) {});
      await afficherParametres(tester, push);

      await tester.tap(find.text('Activer les notifications'));
      await tester.pumpAndSettle();

      expect(passerelle.autorisationsDemandees, 1);
      expect(stockage.enregistres, [('admin1', 'jeton-admin')]);
      expect(find.text('Notifications activées'), findsOneWidget);
      expect(find.text('Vous recevrez les alertes importantes, comme un problème de sauvegarde de la base.'), findsOneWidget);
      expect(find.text('Activer les notifications'), findsNothing);
    });

    testWidgets('autorisation déjà donnée : l\'appareil est enregistré dès l\'ouverture, la carte dit « activées »', (tester) async {
      passerelle.etat = EtatAutorisation.accordee;
      final push = service(PlateformePush.web);
      await push.activer(uid: 'admin1', surAppui: (_) {});
      await afficherParametres(tester, push);

      expect(stockage.enregistres, [('admin1', 'jeton-admin')]);
      expect(find.text('Notifications activées'), findsOneWidget);
    });

    testWidgets('notifications refusées dans le navigateur : la carte l\'explique, sans bouton', (tester) async {
      passerelle.etat = EtatAutorisation.refusee;
      final push = service(PlateformePush.web);
      await push.activer(uid: 'admin1', surAppui: (_) {});
      await afficherParametres(tester, push);

      expect(find.text('Notifications bloquées'), findsOneWidget);
      expect(find.text('Activer les notifications'), findsNothing);
    });

    testWidgets('état pas encore connu : ni carte ni espace en plus, la page est celle d\'avant', (tester) async {
      await afficherParametres(tester, service(PlateformePush.web));

      expect(find.byType(CarteNotifications), findsNothing);
      expect(find.text('Règles en vigueur'), findsOneWidget);
      // Les deux cartes d'avant se suivent à 20 px l'une de l'autre, comme avant l'ajout.
      final regles = tester.getRect(find.byType(AppCard).at(0));
      final kyc = tester.getRect(find.byType(AppCard).at(1));
      expect(kyc.top - regles.bottom, 20);
    });
  });

  group('Admin > tableau de bord', () {
    Future<void> ouvrir(WidgetTester tester, NotificationsPush push, {String? uid}) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: AdminDashboardPage(monUid: uid, notificationsPush: push)));
      // La police de test (Ahem) élargit les textes : débordement sans objet en vrai.
      tester.takeException();
      await tester.pump();
    }

    testWidgets('à l\'ouverture, l\'appareil de l\'Admin est enregistré pour ses notifications (APK)', (tester) async {
      final push = service(PlateformePush.android);
      await ouvrir(tester, push, uid: 'admin1');
      await tester.pump();

      expect(push.uid, 'admin1');
      expect(passerelle.autorisationsDemandees, 1);
      expect(stockage.enregistres, [('admin1', 'jeton-admin')]);
    });

    testWidgets('sans compte connecté (démo, tests) : rien n\'est enregistré, aucune erreur', (tester) async {
      final push = service(PlateformePush.android);
      await ouvrir(tester, push);
      await tester.pump();

      expect(push.uid, isNull);
      expect(passerelle.autorisationsDemandees, 0);
      expect(stockage.enregistres, isEmpty);
    });
  });
}
