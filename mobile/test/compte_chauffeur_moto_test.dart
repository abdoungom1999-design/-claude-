import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/features/admin/data/admin_kyc_service.dart';
import 'package:sprint/features/admin/presentation/widgets/dossier_chauffeur_panel.dart';
import 'package:sprint/features/auth/presentation/conducteur_onboarding/conducteur_onboarding_page.dart';
import 'package:sprint/features/conducteur/data/fiche_chauffeur.dart';
import 'package:sprint/features/conducteur/presentation/modifier_fiche_chauffeur_page.dart';
import 'package:sprint/features/conducteur/presentation/tabs/conducteur_compte_tab.dart';

/// Compte chauffeur 100 % moto (demande du client, 2 novembre 2026) : vrai
/// prénom et nom, fiche modifiable par le chauffeur (identité et moto
/// vérifiées par l'Admin une fois le dossier validé), inscription et menus
/// sans voiture.

class _FicheFactice extends FicheChauffeurService {
  _FicheFactice({this.resultat = ResultatFiche.enregistre, this.erreur});

  final ResultatFiche resultat;
  final Object? erreur;
  final appels = <Map<String, Object>>[];
  var annulations = 0;

  @override
  Future<ResultatFiche> enregistrer({
    required FicheChauffeur avant,
    required String prenom,
    required String nomDeFamille,
    required String telephone,
    required MotoChauffeur moto,
    required String plaque,
  }) async {
    if (erreur case final e?) throw e;
    appels.add({
      'prenom': prenom,
      'nomDeFamille': nomDeFamille,
      'telephone': telephone,
      'moto': moto.description,
      'plaque': plaque,
    });
    return resultat;
  }

  @override
  Future<void> annulerDemande() async => annulations++;
}

const _moto = {'marque': 'Bajaj', 'modele': 'Boxer 125', 'couleur': 'Noir'};

Map<String, dynamic> _profil({Map<String, dynamic> extra = const {}}) => {
      'role': 'conducteur',
      'prenom': 'moussa',
      'nomDeFamille': 'DIOP',
      'nom': 'moussa DIOP',
      'telephone': '+221 77 123 45 67',
      'email': 'moussa@test.sn',
      'moto': _moto,
      'vehiculeId': 'Bajaj Boxer 125 Noir',
      'plaqueImmatriculation': 'DK-1234-AB',
      'statutValidation': 'valide',
      ...extra,
    };

void main() {
  group('fiche du chauffeur : vrai nom, moto, saisies', () {
    test('noms en majuscules initiales, casse mixte respectée', () {
      expect(capitaliserNom('lueur dell'), 'Lueur Dell');
      expect(capitaliserNom('MOUSSA'), 'Moussa');
      expect(capitaliserNom("n'diaye"), "N'Diaye");
      expect(capitaliserNom('ba-sow'), 'Ba-Sow');
      expect(capitaliserNom('  mame   diarra '), 'Mame Diarra');
      expect(capitaliserNom('McDonald'), 'McDonald');
      expect(nomCompletDe('moussa', 'diop'), 'Moussa Diop');
      expect(nomCompletDe('', ''), '');
      expect(normaliserPlaque(' dk 1234  ab '), 'DK 1234 AB');
    });

    test('contrôles de saisie : nom, moto, plaque', () {
      expect(validerNomPropre('Moussa', champ: 'Prénom'), isNull);
      expect(validerNomPropre("N'Diaye-Sow", champ: 'Nom'), isNull);
      expect(validerNomPropre('Ndèye', champ: 'Prénom'), isNull);
      expect(validerNomPropre('M', champ: 'Prénom'), contains('2 lettres'));
      expect(validerNomPropre('lueur123', champ: 'Prénom'), contains('lettres'));
      expect(validerNomPropre('x' * 41, champ: 'Nom'), contains('40'));
      expect(validerChampMoto('Bajaj', champ: 'Marque'), isNull);
      expect(validerChampMoto('  ', champ: 'Couleur'), 'Couleur requis.');
      expect(validerChampMoto('x' * 31, champ: 'Modèle'), contains('30'));
      expect(validerPlaque('DK-1234-AB'), isNull);
      expect(validerPlaque('dk 1234 ab'), isNull);
      for (final invalide in ['DK', 'DK-1234-AB-0000000', 'DK_1234', '']) {
        expect(validerPlaque(invalide), isNotNull, reason: invalide);
      }
    });

    test('lecture : compte structuré, ancien compte (nom et véhicule libres), demande en attente', () {
      final fiche = FicheChauffeur.depuis(_profil());
      expect(fiche.nomComplet, 'Moussa Diop');
      expect(fiche.motoEtPlaque, 'Bajaj Boxer 125 Noir - DK-1234-AB');
      expect(fiche.estValide, isTrue);

      final ancien = FicheChauffeur.depuis({'nom': 'lueur dell', 'vehiculeId': 'Yamaha X (2019)', 'plaqueImmatriculation': 'DK-1'});
      expect(ancien.nomComplet, 'Lueur Dell');
      expect(ancien.prenomEtNom, ('Lueur', 'Dell'));
      expect(ancien.motoEtPlaque, 'Yamaha X (2019) - DK-1');

      final demande = FicheChauffeur.depuis(_profil(extra: {
        'modificationDemandee': {
          'prenom': 'Moussa',
          'nomDeFamille': 'Diop',
          'marque': 'TVS',
          'modele': 'HLX 125',
          'couleur': 'Rouge',
          'plaque': 'DK-5678-CD',
          'demandeLe': Timestamp.fromDate(DateTime(2026, 11, 2, 15)),
        },
      })).modificationDemandee!;
      expect([demande.nomComplet, demande.motoEtPlaque], ['Moussa Diop', 'TVS HLX 125 Rouge - DK-5678-CD']);
      expect(demande.demandeLe, DateTime(2026, 11, 2, 15));
      expect(FicheChauffeur.depuis(null).nomComplet, '');
    });

    group('enregistrement : quoi écrire', () {
      PlanFiche plan(FicheChauffeur avant, {String? prenom, String? nom, String? telephone, Map<String, String>? moto, String? plaque}) {
        final m = moto ?? _moto;
        return planifierFiche(
          avant: avant,
          prenom: prenom ?? avant.prenomEtNom.$1,
          nomDeFamille: nom ?? avant.prenomEtNom.$2,
          telephone: telephone ?? avant.telephone,
          moto: MotoChauffeur(marque: m['marque']!, modele: m['modele']!, couleur: m['couleur']!),
          plaque: plaque ?? avant.plaque,
        );
      }

      final valide = FicheChauffeur.depuis({..._profil(), 'prenom': 'Moussa', 'nomDeFamille': 'Diop'});
      final enAttente = FicheChauffeur.depuis({..._profil(), 'prenom': 'Moussa', 'nomDeFamille': 'Diop', 'statutValidation': 'en_attente'});

      test('rien de changé : rien d\'écrit', () {
        final p = plan(valide);
        expect([p.resultat, p.telephone, p.demande, p.ecritureDirecte], [ResultatFiche.inchange, null, null, null]);
      });

      test('téléphone seul : écrit aussitôt, même dossier validé', () {
        final p = plan(valide, telephone: '+221 70 000 00 00');
        expect([p.resultat, p.telephone, p.demande], [ResultatFiche.enregistre, '+221 70 000 00 00', null]);
      });

      test('dossier pas encore validé : identité et moto écrites aussitôt (vérifiées à la validation)', () {
        final p = plan(enAttente, prenom: 'ibou', nom: 'sarr', moto: {'marque': 'TVS', 'modele': 'HLX', 'couleur': 'Rouge'}, plaque: 'dk-9');
        expect(p.resultat, ResultatFiche.enregistre);
        expect(p.ecritureDirecte, {
          'prenom': 'Ibou',
          'nomDeFamille': 'Sarr',
          'moto': {'marque': 'TVS', 'modele': 'HLX', 'couleur': 'Rouge'},
          'vehiculeId': 'TVS HLX Rouge',
          'plaqueImmatriculation': 'DK-9',
        });
        expect(p.nomDirect, 'Ibou Sarr');
        expect(p.demande, isNull);
      });

      test('dossier validé : identité ou moto en demande à vérifier ; le téléphone, lui, change aussitôt', () {
        final p = plan(valide, plaque: 'DK-5678-CD', telephone: '+221 70 000 00 00');
        expect(p.resultat, ResultatFiche.aVerifier);
        expect(p.ecritureDirecte, isNull);
        expect(p.telephone, '+221 70 000 00 00');
        expect(p.demande, {
          'prenom': 'Moussa',
          'nomDeFamille': 'Diop',
          'marque': 'Bajaj',
          'modele': 'Boxer 125',
          'couleur': 'Noir',
          'plaque': 'DK-5678-CD',
        });
      });

      test('ancien compte validé : compléter sa moto passe par la vérification', () {
        final ancien = FicheChauffeur.depuis({'nom': 'lueur dell', 'telephone': '+221771', 'vehiculeId': 'Yamaha', 'statutValidation': 'valide'});
        final p = plan(ancien, plaque: 'DK-1234-AB');
        expect(p.resultat, ResultatFiche.aVerifier);
        expect(p.demande!['prenom'], 'Lueur');
      });
    });
  });

  group('onglet Compte du chauffeur', () {
    Future<_FicheFactice> ouvrir(WidgetTester tester, Map<String, dynamic> profil, {_FicheFactice? service}) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final fiche = service ?? _FicheFactice();
      await tester.pumpWidget(MaterialApp(
        home: ConducteurCompteTab(profil: null, onDeconnexion: () {}, fluxProfil: Stream.value(profil), ficheService: fiche),
      ));
      await tester.pump();
      return fiche;
    }

    testWidgets('vrai prénom et nom, téléphone et moto du compte (plus le profil de démonstration)', (tester) async {
      await ouvrir(tester, _profil());
      expect(find.text('Moussa Diop'), findsOneWidget);
      expect(find.text('+221 77 123 45 67'), findsOneWidget);
      expect(find.text('Bajaj Boxer 125 Noir - DK-1234-AB'), findsOneWidget);
      expect(find.textContaining('démo'), findsNothing);
      expect(find.text('+221 77 000 00 00'), findsNothing);
    });

    testWidgets('ancien compte au nom saisi en minuscules : affiché en majuscules initiales ; moto à compléter', (tester) async {
      await ouvrir(tester, {'nom': 'lueur dell', 'telephone': '+221 77 1', 'statutValidation': 'valide'});
      expect(find.text('Lueur Dell'), findsOneWidget);
      expect(find.text('Ajoutez votre moto et sa plaque'), findsOneWidget);
    });

    testWidgets('menus 100 % moto : plus de « Paramètres » vide ; fiche et centre d\'aide', (tester) async {
      await ouvrir(tester, _profil());
      expect(find.text('Paramètres'), findsNothing);
      expect(find.text('Mes informations et ma moto'), findsOneWidget);
      expect(find.text('Centre d\'aide'), findsOneWidget);
      expect(find.text('Modifier mon profil'), findsOneWidget);
      expect(find.text('Se déconnecter'), findsOneWidget);
    });

    testWidgets('bouton « Modifier mon profil » et zone cliquable : ouvrent la fiche, préremplie', (tester) async {
      await ouvrir(tester, _profil());
      for (final acces in [find.byKey(const ValueKey('bouton-modifier-profil')), find.byKey(const ValueKey('zone-fiche'))]) {
        await tester.tap(acces);
        await tester.pumpAndSettle();
        expect(find.text('Mon profil'), findsOneWidget);
        expect(find.widgetWithText(TextFormField, 'Moussa'), findsOneWidget);
        expect(find.widgetWithText(TextFormField, 'Diop'), findsOneWidget);
        expect(find.widgetWithText(TextFormField, 'Boxer 125'), findsOneWidget);
        expect(find.widgetWithText(TextFormField, 'DK-1234-AB'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    });

    testWidgets('enregistré : le chauffeur est prévenu ; demande à vérifier : il sait que Sprint vérifie', (tester) async {
      final service = await ouvrir(tester, _profil(), service: _FicheFactice(resultat: ResultatFiche.aVerifier));
      await tester.tap(find.byKey(const ValueKey('bouton-modifier-profil')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('champ-plaque')), 'DK-5678-CD');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(service.appels.single['plaque'], 'DK-5678-CD');
      expect(find.text('Mon profil'), findsNothing);
      expect(find.textContaining('Sprint la vérifie avec vos pièces'), findsOneWidget);
    });

    testWidgets('demande en attente : visible, avec ce qui a été demandé ; annulable', (tester) async {
      final service = await ouvrir(
        tester,
        _profil(extra: {
          'modificationDemandee': {
            'prenom': 'Moussa',
            'nomDeFamille': 'Diop',
            'marque': 'TVS',
            'modele': 'HLX 125',
            'couleur': 'Rouge',
            'plaque': 'DK-5678-CD',
            'demandeLe': Timestamp.fromDate(DateTime(2026, 11, 2, 15)),
          },
        }),
      );
      expect(find.byKey(const ValueKey('demande-en-attente')), findsOneWidget);
      expect(find.textContaining('le 02/11, en vérification par Sprint'), findsOneWidget);
      expect(find.textContaining('TVS HLX 125 Rouge - DK-5678-CD'), findsOneWidget);
      // Ce que voient les clients reste la moto vérifiée.
      expect(find.text('Bajaj Boxer 125 Noir - DK-1234-AB'), findsOneWidget);
      await tester.tap(find.text('Annuler la demande'));
      await tester.pump();
      expect(service.annulations, 1);
    });

    testWidgets('modification refusée : le chauffeur en est informé', (tester) async {
      await ouvrir(tester, _profil(extra: {'modificationRefuseeLe': Timestamp.fromDate(DateTime(2026, 11, 2))}));
      expect(find.byKey(const ValueKey('modification-refusee')), findsOneWidget);
    });
  });

  group('page « Mon profil »', () {
    Future<ResultatFiche?> Function() ouvrir(WidgetTester tester, FicheChauffeur fiche, _FicheFactice service) {
      ResultatFiche? resultat;
      var termine = false;
      return () async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          // Nouvelle app à chaque ouverture (plusieurs cas dans un même test).
          key: UniqueKey(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                resultat = await Navigator.of(context).push<ResultatFiche>(
                  MaterialPageRoute(builder: (_) => ModifierFicheChauffeurPage(fiche: fiche, service: service)),
                );
                termine = true;
              },
              child: const Text('Ouvrir'),
            ),
          ),
        ));
        await tester.tap(find.text('Ouvrir'));
        await tester.pumpAndSettle();
        return termine ? resultat : null;
      };
    }

    testWidgets('dossier validé : la vérification par Sprint est expliquée ; pas encore validé : rien à expliquer', (tester) async {
      await ouvrir(tester, FicheChauffeur.depuis(_profil()), _FicheFactice())();
      expect(find.byKey(const ValueKey('info-verification')), findsOneWidget);
      await ouvrir(tester, FicheChauffeur.depuis(_profil(extra: {'statutValidation': 'en_attente'})), _FicheFactice())();
      expect(find.byKey(const ValueKey('info-verification')), findsNothing);
    });

    testWidgets('saisies invalides : messages sous les champs, rien n\'est envoyé', (tester) async {
      final service = _FicheFactice();
      await ouvrir(tester, FicheChauffeur.depuis(_profil()), service)();
      await tester.enterText(find.byKey(const ValueKey('champ-prenom')), 'L');
      await tester.enterText(find.byKey(const ValueKey('champ-couleur')), '');
      await tester.enterText(find.byKey(const ValueKey('champ-plaque')), 'DK');
      await tester.tap(find.text('Enregistrer'));
      await tester.pump();
      expect(find.text('Prénom requis (2 lettres au moins).'), findsOneWidget);
      expect(find.text('Couleur requis.'), findsOneWidget);
      expect(find.text('Plaque invalide (ex : DK-1234-AB).'), findsOneWidget);
      expect(service.appels, isEmpty);
    });

    testWidgets('ce qui est saisi part au service ; une erreur s\'affiche, la page reste ouverte', (tester) async {
      final service = _FicheFactice(erreur: Exception('hors ligne'));
      await ouvrir(tester, FicheChauffeur.depuis(_profil()), service)();
      await tester.enterText(find.byKey(const ValueKey('champ-marque')), 'TVS');
      await tester.enterText(find.byKey(const ValueKey('champ-modele')), 'HLX 125');
      await tester.enterText(find.byKey(const ValueKey('champ-couleur')), 'Rouge');
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(find.text('Enregistrement impossible. Vérifiez votre connexion et réessayez.'), findsOneWidget);
      expect(find.text('Mon profil'), findsOneWidget);
    });
  });

  group('inscription chauffeur 100 % moto', () {
    testWidgets('étape « Votre moto » : marque, modèle, couleur, plaque ; plus de voiture (Peugeot) ni d\'année', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: ConducteurOnboardingPage()));
      expect(find.text('Moto'), findsOneWidget);
      expect(find.textContaining('comme sur votre permis de conduire'), findsOneWidget);
      final champs = find.byType(TextFormField);
      for (final (i, valeur) in ['Moussa', 'Diop', 'moussa@test.sn', '+221771234567', 'motdepasse1', 'motdepasse1'].indexed) {
        await tester.enterText(champs.at(i), valeur);
      }
      await tester.tap(find.text('Suivant'));
      await tester.pumpAndSettle();
      expect(find.text('Votre moto'), findsOneWidget);
      for (final libelle in ['Marque', 'Modèle', 'Couleur', "Plaque d'immatriculation"]) {
        expect(find.text(libelle), findsOneWidget, reason: libelle);
      }
      expect(find.text('Ex : Bajaj'), findsOneWidget);
      expect(find.textContaining('Peugeot'), findsNothing);
      expect(find.textContaining('Année'), findsNothing);
      expect(find.byIcon(Icons.directions_car_outlined), findsNothing);
      expect(find.byIcon(Icons.two_wheeler_rounded), findsWidgets);
      // Champs vides : refus clair, compte non créé.
      await tester.tap(find.text('Créer mon compte'));
      await tester.pump();
      expect(find.text('Marque requis.'), findsOneWidget);
      expect(find.text('Plaque invalide (ex : DK-1234-AB).'), findsOneWidget);
    });

    testWidgets('prénom ou nom fantaisistes refusés dès la première étape', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: ConducteurOnboardingPage()));
      await tester.enterText(find.byType(TextFormField).at(0), 'lueur123');
      await tester.tap(find.text('Suivant'));
      await tester.pump();
      expect(find.text('Prénom : lettres, espaces, tirets et apostrophes seulement.'), findsOneWidget);
      expect(find.text('Votre moto'), findsNothing);
    });
  });

  group('Admin : modification demandée par un chauffeur validé', () {
    testWidgets('avant / après, à comparer aux pièces ; « Valider » et « Refuser » appellent le service', (tester) async {
      final service = _AdminEspion();
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => ouvrirDossierChauffeur(context, uid: 'chauffeur-1', service: service),
            child: const Text('Ouvrir'),
          ),
        ),
      ));
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('modification-demandee')), findsOneWidget);
      expect(find.textContaining('Lueur Dell', findRichText: true), findsWidgets);
      expect(find.textContaining('Moussa Diop', findRichText: true), findsWidgets);
      expect(find.textContaining('TVS HLX 125 Rouge - DK-5678-CD', findRichText: true), findsOneWidget);
      await tester.tap(find.text('Valider la modification'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Refuser'));
      await tester.pumpAndSettle();
      expect(service.actions, [('valider', 'chauffeur-1'), ('refuser', 'chauffeur-1')]);
    });
  });
}

class _AdminEspion extends AdminKycService {
  final actions = <(String, String)>[];

  @override
  Stream<ConducteurKycAdmin?> streamConducteur(String uid) => Stream.value(
        ConducteurKycAdmin(
          id: uid,
          nom: 'Lueur Dell',
          telephone: '+221770000000',
          vehiculeId: 'Bajaj Boxer 125 Noir',
          plaqueImmatriculation: 'DK-1234-AB',
          statutValidation: 'valide',
          statutCompte: 'actif',
          documents: const {},
          modificationDemandee: const ModificationDemandee(
            prenom: 'Moussa',
            nomDeFamille: 'Diop',
            moto: MotoChauffeur(marque: 'TVS', modele: 'HLX 125', couleur: 'Rouge'),
            plaque: 'DK-5678-CD',
          ),
        ),
      );

  @override
  Future<void> validerModification(String uid) async => actions.add(('valider', uid));

  @override
  Future<void> refuserModification(String uid) async => actions.add(('refuser', uid));
}
