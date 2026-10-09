import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sprint/core/location/localiser.dart';
import 'package:sprint/core/maps/geocoding_service.dart';
import 'package:sprint/core/utils/format_fcfa.dart';
import 'package:sprint/core/widgets/primary_button.dart';
import 'package:sprint/features/client/presentation/passager_page.dart';
import 'package:sprint/features/courses/data/course_service.dart';
import 'package:sprint/features/courses/data/depart_gps.dart';
import 'package:sprint/features/courses/data/estimation_course_controller.dart';
import 'package:sprint/features/courses/data/pricing_repository.dart';

const _moi = LatLng(14.701234, -17.456789);

final _almadies = AdresseSuggestion(libelle: 'Almadies, Dakar', latitude: 14.7450, longitude: -17.5170);

class _Adresses implements ServiceAdresses {
  @override
  Future<List<PropositionAdresse>> rechercher(String texte) async =>
      [PropositionAdresse(principal: 'Almadies', secondaire: 'Dakar', coordonnees: _almadies)];

  @override
  Future<AdresseSuggestion> resoudre(PropositionAdresse proposition) async => proposition.coordonnees!;
}

class _Tarification extends PricingRepository {
  _Tarification() : super(dio: Dio());

  @override
  Future<EstimationPrix> estimer({required String type, required double distanceKm, PointsCourse? trajet}) async =>
      EstimationPrix(distanceKm: distanceKm, dureeEstimeeMin: 20, multiplicateurTrafic: 1, prixFcfa: 1500);
}

/// Position de l'appareil qui répond tout de suite, en notant ce qu'on lui demande.
class _Gps {
  _Gps(this.reponses);

  /// Une réponse par appel, dans l'ordre ; la dernière sert ensuite.
  final List<LatLng?> reponses;
  final demandes = <bool>[];

  /// Appels qui peuvent faire apparaître la demande d'autorisation du
  /// téléphone : ceux de l'écran de commande. La carte, elle, n'en fait jamais.
  int get avecAutorisation => demandes.where((demander) => demander).length;

  Future<LatLng?> localiser({required bool demander}) async {
    demandes.add(demander);
    return reponses[(demandes.length - 1).clamp(0, reponses.length - 1)];
  }
}

void main() {
  group('DepartGps', () {
    test('le départ GPS porte les coordonnées exactes et le libellé « Ma position actuelle »', () {
      final depart = DepartGps.depuis(_moi);
      expect(depart.gps, isTrue);
      expect(depart.libelle, 'Ma position actuelle');
      expect(depart.latitude, 14.701234);
      expect(depart.longitude, -17.456789);
    });

    test('une adresse choisie dans la liste n\'est pas un départ GPS', () {
      expect(_almadies.gps, isFalse);
    });

    test('le trajet envoyé au serveur part des coordonnées exactes du GPS', () {
      final estimation = EstimationCourseController(type: 'PASSAGER', pricingRepository: _Tarification())
        ..definirDepart(DepartGps.depuis(_moi))
        ..definirArrivee(_almadies);
      addTearDown(estimation.dispose);

      final trajet = estimation.trajet!;
      expect(trajet.latitudeDepart, 14.701234);
      expect(trajet.longitudeDepart, -17.456789);
      expect(trajet.latitudeArrivee, 14.7450);
      expect(trajet.longitudeArrivee, -17.5170);
    });

    test('la course enregistre « Position GPS du client » pour un départ GPS, l\'adresse saisie sinon', () {
      expect(DepartGps.pourLaCourse(DepartGps.depuis(_moi), 'Ma position actuelle'), 'Position GPS du client');
      expect(DepartGps.pourLaCourse(_almadies, '  Almadies, Dakar '), 'Almadies, Dakar');
    });
  });

  group('écran « Réserver une course »', () {
    Future<void> afficher(WidgetTester tester, Localiser localiser) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: PassagerPage(
          localiser: localiser,
          adresses: _Adresses(),
          pricingRepository: _Tarification(),
        ),
      ));
      await tester.pump();
      // Laisse finir l'animation de hauteur de la ligne sous le champ.
      await tester.pump(const Duration(milliseconds: 300));
    }

    final champDepart = find.widgetWithText(TextFormField, 'Adresse de départ');
    final champArrivee = find.widgetWithText(TextFormField, "Adresse d'arrivée");

    String texteDe(WidgetTester tester, Finder champ) =>
        tester.widget<EditableText>(find.descendant(of: champ, matching: find.byType(EditableText))).controller.text;

    Future<void> choisirArrivee(WidgetTester tester) async {
      await tester.enterText(champArrivee, 'Alma');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('Almadies'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
    }

    testWidgets('à l\'ouverture, la position GPS est demandée et remplit le départ', (tester) async {
      final gps = _Gps([_moi]);
      await afficher(tester, gps.localiser);

      expect(gps.avecAutorisation, 1, reason: 'la position est demandée une fois, avec autorisation');
      expect(texteDe(tester, champDepart), 'Ma position actuelle');
      expect(find.text('Votre chauffeur viendra vous chercher à votre position GPS exacte.'), findsOneWidget);
      // Le départ est connu : seule l'arrivée est à choisir.
      expect(find.text("Choisissez l'adresse d'arrivée dans les suggestions pour voir le prix."), findsOneWidget);
      expect(tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed, isNull);
    });

    testWidgets('départ GPS + arrivée choisie : prix calculé, « Commander » s\'active', (tester) async {
      await afficher(tester, _Gps([_moi]).localiser);
      expect(tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed, isNull);

      await choisirArrivee(tester);

      expect(find.text('~${formaterFcfa(1500)}'), findsOneWidget);
      expect(tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed, isNotNull);
    });

    testWidgets('GPS introuvable : champ vide, explication, « Réessayer » reprend la position', (tester) async {
      final gps = _Gps([null, _moi]);
      await afficher(tester, gps.localiser);

      expect(texteDe(tester, champDepart), isEmpty);
      expect(find.textContaining('Position GPS introuvable'), findsOneWidget);
      expect(find.text("Choisissez l'adresse de départ et d'arrivée dans les suggestions pour voir le prix."),
          findsOneWidget);

      await tester.tap(find.text('Réessayer'));
      await tester.pump();
      await tester.pump();

      expect(gps.avecAutorisation, 2, reason: 'une nouvelle demande à chaque « Réessayer »');
      expect(texteDe(tester, champDepart), 'Ma position actuelle');
      expect(find.textContaining('Position GPS introuvable'), findsNothing);
    });

    testWidgets('le client change le départ à la main : le point GPS est oublié, il peut le reprendre', (tester) async {
      final gps = _Gps([_moi]);
      await afficher(tester, gps.localiser);
      await choisirArrivee(tester);
      expect(tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed, isNotNull);

      await tester.enterText(champDepart, 'Plateau');
      await tester.pump();

      // Plus de point de départ : on ne peut plus commander avant d'en choisir un.
      expect(tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed, isNull);
      expect(find.text('Votre chauffeur viendra vous chercher à votre position GPS exacte.'), findsNothing);
      expect(find.text('Utiliser ma position actuelle'), findsOneWidget);

      await tester.tap(find.text('Utiliser ma position actuelle'));
      await tester.pumpAndSettle();

      expect(texteDe(tester, champDepart), 'Ma position actuelle');
      expect(find.text('Votre chauffeur viendra vous chercher à votre position GPS exacte.'), findsOneWidget);
      expect(tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed, isNotNull);
    });

    testWidgets('une position qui arrive après que le client a commencé à saisir ne remplace pas sa saisie',
        (tester) async {
      final reponse = Completer<LatLng?>();
      await afficher(tester, ({required bool demander}) => reponse.future);
      expect(find.text('Recherche de votre position GPS…'), findsOneWidget);

      await tester.enterText(champDepart, 'Plateau');
      await tester.pump();
      reponse.complete(_moi);
      await tester.pump();
      await tester.pump();

      expect(texteDe(tester, champDepart), 'Plateau');
      expect(find.text('Utiliser ma position actuelle'), findsOneWidget);
      expect(find.text('Votre chauffeur viendra vous chercher à votre position GPS exacte.'), findsNothing);
    });

    testWidgets('toucher « Ma position actuelle » sélectionne tout le texte : la première lettre le remplace',
        (tester) async {
      await afficher(tester, _Gps([_moi]).localiser);

      await tester.tap(champDepart);
      await tester.pump();

      final editable =
          tester.widget<EditableText>(find.descendant(of: champDepart, matching: find.byType(EditableText)));
      expect(editable.controller.selection, const TextSelection(baseOffset: 0, extentOffset: 20));
      expect(editable.controller.text.length, 20);
    });
  });
}
