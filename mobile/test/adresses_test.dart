import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/maps/geocoding_service.dart';
import 'package:sprint/core/widgets/address_search_field.dart';

/// Service d'adresses contrôlé par le test.
class _AdressesFactices implements ServiceAdresses {
  final recherches = <String, Completer<List<PropositionAdresse>>>{};
  final resolues = <PropositionAdresse>[];
  bool echecResolution = false;

  @override
  Future<List<PropositionAdresse>> rechercher(String texte) =>
      (recherches[texte] = Completer<List<PropositionAdresse>>()).future;

  @override
  Future<AdresseSuggestion> resoudre(PropositionAdresse proposition) async {
    resolues.add(proposition);
    if (echecResolution) throw Exception('introuvable');
    return AdresseSuggestion(libelle: proposition.libelle, latitude: 14.69, longitude: -17.46);
  }
}

class _SecoursFactice implements ServiceAdresses {
  int appels = 0;

  @override
  Future<List<PropositionAdresse>> rechercher(String texte) async {
    appels++;
    return [const PropositionAdresse(principal: 'Plateau (OSM)')];
  }

  @override
  Future<AdresseSuggestion> resoudre(PropositionAdresse proposition) async => throw UnimplementedError();
}

const _ucad = PropositionAdresse(principal: 'UCAD', secondaire: 'Dakar, Sénégal', placeId: 'ChIJ-ucad-1234');

Future<(_AdressesFactices, List<AdresseSuggestion>, TextEditingController)> _champ(WidgetTester tester) async {
  final service = _AdressesFactices();
  final choisies = <AdresseSuggestion>[];
  final controleur = TextEditingController();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: AddressSearchField(label: 'Départ', controller: controleur, onSelected: choisies.add, service: service),
    ),
  ));
  return (service, choisies, controleur);
}

void main() {
  group('Champ d\'adresse', () {
    testWidgets('suggestions Google (nom + quartier), choix -> coordonnées demandées puis transmises', (tester) async {
      final (service, choisies, controleur) = await _champ(tester);
      await tester.enterText(find.byType(TextField), 'ucad');
      await tester.pump(const Duration(milliseconds: 600));
      service.recherches['ucad']!.complete([_ucad]);
      await tester.pump();

      expect(find.text('UCAD'), findsOneWidget);
      expect(find.text('Dakar, Sénégal'), findsOneWidget);

      await tester.tap(find.text('UCAD'));
      await tester.pump();
      expect(service.resolues.single.placeId, 'ChIJ-ucad-1234');
      expect(controleur.text, 'UCAD, Dakar, Sénégal');
      expect(choisies.single.latitude, 14.69);
    });

    testWidgets('coordonnées introuvables : message, aucune adresse transmise', (tester) async {
      final (service, choisies, _) = await _champ(tester);
      service.echecResolution = true;
      await tester.enterText(find.byType(TextField), 'ucad');
      await tester.pump(const Duration(milliseconds: 600));
      service.recherches['ucad']!.complete([_ucad]);
      await tester.pump();
      await tester.tap(find.text('UCAD'));
      await tester.pump();

      expect(choisies, isEmpty);
      expect(find.textContaining('Adresse introuvable'), findsOneWidget);
    });

    testWidgets('une réponse en retard n\'écrase pas les suggestions du texte actuel', (tester) async {
      final (service, _, _) = await _champ(tester);
      await tester.enterText(find.byType(TextField), 'plat');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.enterText(find.byType(TextField), 'plateau');
      await tester.pump(const Duration(milliseconds: 600));

      service.recherches['plateau']!.complete([const PropositionAdresse(principal: 'Plateau', placeId: 'ChIJ-plateau-1')]);
      await tester.pump();
      service.recherches['plat']!.complete([const PropositionAdresse(principal: 'Plateforme', placeId: 'ChIJ-plat-12')]);
      await tester.pump();

      expect(find.text('Plateau'), findsOneWidget);
      expect(find.text('Plateforme'), findsNothing);
    });
  });

  group('Google Places via les Cloud Functions', () {
    test('recherche, puis coordonnées dans la même session, renouvelée après le choix', () async {
      final appels = <(String, Map<String, dynamic>)>[];
      final google = AdressesGoogle(
        secours: _SecoursFactice(),
        appeler: (nom, donnees) async {
          appels.add((nom, donnees));
          return nom == 'rechercherAdresses'
              ? {
                  'propositions': [
                    {'placeId': 'ChIJ-ucad-1234', 'principal': 'UCAD', 'secondaire': 'Dakar, Sénégal'},
                  ],
                }
              : {'latitude': 14.69, 'longitude': -17.46, 'adresse': 'Dakar'};
        },
      );
      final session = google.session;

      final propositions = await google.rechercher('ucad');
      final adresse = await google.resoudre(propositions.single);

      expect(adresse.libelle, 'UCAD, Dakar, Sénégal');
      expect((adresse.latitude, adresse.longitude), (14.69, -17.46));
      expect(appels.map((a) => a.$2['session']), [session, session]);
      expect(appels.last.$2['placeId'], 'ChIJ-ucad-1234');
      expect(google.session, isNot(session));
      expect(session.length, 32);
    });

    test('serveur indisponible (quota, panne) : secours OpenStreetMap', () async {
      final secours = _SecoursFactice();
      final google = AdressesGoogle(
        secours: secours,
        appeler: (nom, donnees) async => throw FirebaseFunctionsException(code: 'unavailable', message: 'quota'),
      );

      final propositions = await google.rechercher('plateau');
      expect(propositions.single.principal, 'Plateau (OSM)');
      expect(secours.appels, 1);
    });

    test('moins de 3 caractères : aucun appel', () async {
      var appels = 0;
      final google = AdressesGoogle(secours: _SecoursFactice(), appeler: (n, d) async {
        appels++;
        return {};
      });
      expect(await google.rechercher('uc'), isEmpty);
      expect(appels, 0);
    });
  });
}
