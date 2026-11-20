// Lot 148 : en publication 147, sur iPhone, l'ajout de la Photo échouait en « firestore/permission-denied » SANS
// suffixe (Storage avait accepté). Reproduit sur l'émulateur (firestore_rules_test/parcours_chauffeur.test.mjs,
// « compte réel de production ») : un vrai profil de chauffeur accepte ses pièces ; le refus vient d'un compte CLIENT
// connecté dans l'espace chauffeur, ou d'un compte SANS profil. L'espace chauffeur les reconnaît désormais.
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/network/api_exception.dart';
import 'package:sprint/core/widgets/numero_version.dart';
import 'package:sprint/features/auth/data/auth_repository.dart';
import 'package:sprint/features/conducteur/data/etape_dossier.dart';
import 'package:sprint/features/conducteur/data/piece_kyc.dart';
import 'package:sprint/features/conducteur/presentation/conducteur_compte_client_page.dart';
import 'package:sprint/features/conducteur/presentation/conducteur_profil_incomplet_page.dart';

void main() {
  group("écran d'entrée de l'espace chauffeur", () {
    test('profil absent : « Terminez votre inscription »', () {
      expect(etapeDossierChauffeur(null), EtapeDossierChauffeur.profilAbsent);
    });

    test('compte Client : écran dédié, jamais « Complétez votre dossier »', () {
      expect(etapeDossierChauffeur({'role': 'client'}), EtapeDossierChauffeur.compteClient);
      expect(etapeDossierChauffeur({'role': 'client', 'statutValidation': 'valide'}), EtapeDossierChauffeur.compteClient);
    });

    test('chauffeur : comme avant, selon son statut de validation', () {
      expect(etapeDossierChauffeur({'role': 'conducteur'}), EtapeDossierChauffeur.nonEnvoye);
      expect(etapeDossierChauffeur({'role': 'conducteur', 'statutValidation': 'rejete'}), EtapeDossierChauffeur.nonEnvoye);
      expect(etapeDossierChauffeur({'role': 'conducteur', 'statutValidation': 'en_attente'}), EtapeDossierChauffeur.enAttente);
      expect(etapeDossierChauffeur({'role': 'conducteur', 'statutValidation': 'valide'}), EtapeDossierChauffeur.valide);
    });

    test('Admin dans l\'espace chauffeur : inchangé (les règles lui permettent tout)', () {
      expect(etapeDossierChauffeur({'role': 'admin'}), EtapeDossierChauffeur.nonEnvoye);
    });
  });

  group('cause précise d\'un refus des règles à l\'envoi d\'une pièce', () {
    test('état du profil relu', () {
      expect(etatProfilRefus(null), 'profil absent');
      expect(etatProfilRefus({'role': 'client'}), 'compte client');
      expect(etatProfilRefus({'role': 'conducteur'}), 'profil chauffeur');
      expect(etatProfilRefus({'nom': 'X'}), 'profil sans rôle');
    });

    test('code affiché', () {
      expect(codeEchecFirestore('permission-denied', etatProfil: 'profil absent'), 'firestore/permission-denied (profil absent)');
      expect(
        codeEchecFirestore('permission-denied', codeStockage: 'storage/unauthorized', etatProfil: 'compte client'),
        'firestore/permission-denied (compte client), repli après storage/unauthorized',
      );
      // Sans état relu : inchangé.
      expect(codeEchecFirestore('permission-denied'), 'firestore/permission-denied');
    });
  });

  test("profil d'inscription chauffeur : uniquement des champs que les règles acceptent à la création", () {
    final regles = File('firestore.rules').readAsStringSync();
    final bloc = RegExp(r'match /users/\{uid\} \{[\s\S]*?allow create:[\s\S]*?hasOnly\(\[([\s\S]*?)\]\)').firstMatch(regles)!;
    final permis = RegExp("'([A-Za-z]+)'").allMatches(bloc.group(1)!).map((m) => m.group(1)!).toSet();
    expect(permis, contains('role'));

    final profil = profilConducteurInscription(
      email: 'moussa@exemple.sn',
      nom: 'Moussa Diop',
      telephone: '+221771234567',
      vehiculeId: 'Bajaj Boxer 125 Noir',
      prenom: 'Moussa',
      nomDeFamille: 'Diop',
      moto: {'marque': 'Bajaj', 'modele': 'Boxer 125', 'couleur': 'Noir'},
    );
    expect(permis.containsAll(profil.keys), isTrue, reason: '${profil.keys.toSet().difference(permis)}');
    expect(profil['role'], 'conducteur');
    expect(profil['estValide'], false);
    expect(profil.containsKey('plaqueImmatriculation'), isFalse, reason: 'plaque non demandée');
  });

  test("adresse e-mail déjà utilisée : le message parle de l'adresse, plus du numéro", () {
    final message = ApiException.depuisFirebaseAuth(FirebaseAuthException(code: 'email-already-in-use')).message;
    expect(message, contains('adresse e-mail est déjà utilisée'));
    expect(message, isNot(contains('numéro')));
  });

  testWidgets('compte Client : écran clair, « Créer un compte chauffeur » et « Se déconnecter »', (tester) async {
    var creer = 0;
    var deconnexion = 0;
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: ConducteurCompteClientPage(onCreerCompteChauffeur: () => creer++, onDeconnexion: () => deconnexion++),
    ));
    await tester.pump();
    expect(find.text('Ce compte est un compte Client'), findsOneWidget);
    expect(find.byType(NumeroVersion), findsOneWidget);
    await tester.tap(find.text('Créer un compte chauffeur'));
    await tester.pump();
    await tester.ensureVisible(find.text('Se déconnecter'));
    await tester.tap(find.text('Se déconnecter'));
    await tester.pump();
    expect((creer, deconnexion), (1, 1));
  });

  group('« Terminez votre inscription »', () {
    Future<void> remplir(WidgetTester tester) async {
      final champs = find.byType(TextFormField);
      for (final (i, v) in ['moussa', 'diop', '+221771234567', 'Bajaj', 'Boxer 125', 'Noir'].indexed) {
        await tester.enterText(champs.at(i), v);
      }
    }

    Future<void> ouvrir(WidgetTester tester, Widget page) async {
      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: page));
      await tester.pump();
    }

    testWidgets('champs vides : rien n\'est enregistré', (tester) async {
      var appels = 0;
      await ouvrir(
        tester,
        ConducteurProfilIncompletPage(
          onTermine: () {},
          onDeconnexion: () {},
          enregistrer: ({required nom, required telephone, required vehiculeId, required prenom, required nomDeFamille, required moto}) async => appels++,
        ),
      );
      await tester.tap(find.text('Enregistrer et continuer'));
      await tester.pump();
      expect(appels, 0);
      expect(find.textContaining('Prénom requis'), findsOneWidget);
    });

    testWidgets('formulaire rempli : profil enregistré tel que l\'inscription l\'écrit, puis la suite', (tester) async {
      Map<String, Object>? recu;
      var termine = 0;
      await ouvrir(
        tester,
        ConducteurProfilIncompletPage(
          onTermine: () => termine++,
          onDeconnexion: () {},
          enregistrer: ({required nom, required telephone, required vehiculeId, required prenom, required nomDeFamille, required moto}) async {
            recu = {'nom': nom, 'telephone': telephone, 'vehiculeId': vehiculeId, 'prenom': prenom, 'nomDeFamille': nomDeFamille, 'moto': moto};
          },
        ),
      );
      expect(find.byType(NumeroVersion), findsOneWidget, reason: 'numéro de version en bas, comme les écrans de connexion');
      await remplir(tester);
      await tester.tap(find.text('Enregistrer et continuer'));
      await tester.pumpAndSettle();
      expect(recu, {
        'nom': 'Moussa Diop',
        'telephone': '+221771234567',
        'vehiculeId': 'Bajaj Boxer 125 Noir',
        'prenom': 'Moussa',
        'nomDeFamille': 'Diop',
        'moto': {'marque': 'Bajaj', 'modele': 'Boxer 125', 'couleur': 'Noir'},
      });
      expect(termine, 1);
    });

    testWidgets("échec de l'enregistrement : la cause est dite, on reste sur l'écran", (tester) async {
      var termine = 0;
      await ouvrir(
        tester,
        ConducteurProfilIncompletPage(
          onTermine: () => termine++,
          onDeconnexion: () {},
          enregistrer: ({required nom, required telephone, required vehiculeId, required prenom, required nomDeFamille, required moto}) async =>
              throw ApiException("Votre profil n'a pas pu être enregistré (code : firestore/unavailable). Réessayez."),
        ),
      );
      await remplir(tester);
      await tester.tap(find.text('Enregistrer et continuer'));
      await tester.pumpAndSettle();
      expect(find.textContaining('firestore/unavailable'), findsOneWidget);
      expect(termine, 0);
    });
  });
}
