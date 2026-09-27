import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/demo/demo_data.dart';
import 'package:sprint/core/maps/distance_utils.dart';
import 'package:sprint/core/maps/geocoding_service.dart';
import 'package:sprint/core/network/api_exception.dart';
import 'package:sprint/core/utils/format_fcfa.dart';
import 'package:sprint/core/widgets/primary_button.dart';
import 'package:sprint/features/client/presentation/passager_page.dart';
import 'package:sprint/features/courses/data/estimation_course_controller.dart';
import 'package:sprint/features/courses/data/pricing_repository.dart';
import 'package:sprint/features/courses/presentation/estimation_prix_card.dart';

final _plateau = AdresseSuggestion(libelle: 'Plateau', latitude: 14.6680, longitude: -17.4380);
final _almadies = AdresseSuggestion(libelle: 'Almadies', latitude: 14.7450, longitude: -17.5170);
final _ouakam = AdresseSuggestion(libelle: 'Ouakam', latitude: 14.7230, longitude: -17.4870);

/// Tarification contrôlée par le test : chaque appel attend que le test
/// complète sa réponse.
class _TarificationFactice extends PricingRepository {
  _TarificationFactice() : super(dio: Dio());

  final demandes = <(double, Completer<EstimationPrix>)>[];

  @override
  Future<EstimationPrix> estimer({required String type, required double distanceKm}) {
    final reponse = Completer<EstimationPrix>();
    demandes.add((distanceKm, reponse));
    return reponse.future;
  }

  void repondre(int index, int prix) => demandes[index].$2.complete(
        EstimationPrix(distanceKm: demandes[index].$1, dureeEstimeeMin: 20, multiplicateurTrafic: 1, prixFcfa: prix),
      );
}

void main() {
  group('Formatage FCFA', () {
    test('séparateur de milliers insécable', () {
      expect(formaterFcfa(500), '500 FCFA');
      expect(formaterFcfa(2500), '2 500 FCFA');
      expect(formaterFcfa(1250000), '1 250 000 FCFA');
    });
  });

  group('Distance et formule de prix', () {
    test('distance par la route = vol d\'oiseau x 1,1', () {
      final volOiseau = DistanceUtils.distanceKm(
        latDepart: _plateau.latitude,
        lngDepart: _plateau.longitude,
        latArrivee: _almadies.latitude,
        lngArrivee: _almadies.longitude,
      );
      final route = DistanceUtils.distanceRouteEstimeeKm(
        latDepart: _plateau.latitude,
        lngDepart: _plateau.longitude,
        latArrivee: _almadies.latitude,
        lngArrivee: _almadies.longitude,
      );
      expect(volOiseau, closeTo(12, 1));
      expect(route, closeTo(volOiseau * 1.1, 1e-9));
    });

    // Dakar est en UTC+0 : 10 h = heure creuse, 8 h = pointe, 23 h = nuit.
    final heureCreuse = DateTime.utc(2026, 9, 28, 10);
    final heurePointe = DateTime.utc(2026, 9, 28, 8);
    final nuit = DateTime.utc(2026, 9, 28, 23);
    int prix(double km, DateTime quand, {String type = 'PASSAGER'}) =>
        DemoData.estimerPrix(type: type, distanceKm: km, maintenant: quand).prixFcfa;

    test('15 km : 300 + 15 x 200 = 3 300 FCFA, sans facturation à la minute', () {
      expect(prix(15, heureCreuse), 3300);
      expect(prix(15, heureCreuse, type: 'COLIS'), 3300);
      expect(prix(15, heurePointe), 4000);
      expect(prix(15, nuit), 4000);
    });

    test('Plateau -> Almadies (~13,3 km par la route) : ~3 000 FCFA hors pointe', () {
      final km = DistanceUtils.distanceRouteEstimeeKm(
        latDepart: _plateau.latitude,
        lngDepart: _plateau.longitude,
        latArrivee: _almadies.latitude,
        lngArrivee: _almadies.longitude,
      );
      // 300 + 13,1 x 200 = 2 920 -> 3 000 ; x1,2 = 3 504 -> 3 500.
      expect(prix(km, heureCreuse), 3000);
      expect(prix(km, heurePointe), 3500);
      expect(prix(km, nuit), 3500);
    });

    test('motif de la majoration affiché au client', () {
      String? motif(DateTime quand) =>
          DemoData.estimerPrix(type: 'PASSAGER', distanceKm: 5, maintenant: quand).motifMajoration;
      expect(motif(heureCreuse), isNull);
      expect(motif(heurePointe), 'Heure de pointe');
      expect(motif(nuit), 'Tarif de nuit');
    });

    test('minimum de course 1 000 FCFA ; arrondi à la centaine', () {
      expect(prix(0.5, heureCreuse), 1000);
      expect(prix(3, heureCreuse), 1000);
      expect(prix(4, heureCreuse), 1100);
      expect(prix(7.3, heureCreuse) % 100, 0);
    });
  });

  group('EstimationCourseController', () {
    test('adresses manquantes -> calcul -> prix prêt ; commander autorisé seulement alors', () async {
      final tarification = _TarificationFactice();
      final controller = EstimationCourseController(type: 'PASSAGER', pricingRepository: tarification);

      expect(controller.etat, EtatEstimation.adressesManquantes);
      controller.definirDepart(_plateau);
      expect(controller.etat, EtatEstimation.adressesManquantes);
      expect(controller.peutCommander, isFalse);

      controller.definirArrivee(_almadies);
      expect(controller.etat, EtatEstimation.calcul);
      expect(controller.peutCommander, isFalse);
      expect(tarification.demandes.single.$1, closeTo(controller.distanceKm!, 1e-9));

      tarification.repondre(0, 4800);
      await Future<void>.delayed(Duration.zero);
      expect(controller.etat, EtatEstimation.prete);
      expect(controller.estimation!.prixFcfa, 4800);
      expect(controller.peutCommander, isTrue);
    });

    test('retoucher une adresse à la main efface le prix et bloque la commande', () async {
      final tarification = _TarificationFactice();
      final controller = EstimationCourseController(type: 'PASSAGER', pricingRepository: tarification)
        ..definirDepart(_plateau)
        ..definirArrivee(_almadies);
      tarification.repondre(0, 4800);
      await Future<void>.delayed(Duration.zero);

      controller.oublierArrivee();
      expect(controller.etat, EtatEstimation.adressesManquantes);
      expect(controller.estimation, isNull);
      expect(controller.peutCommander, isFalse);
    });

    test('échec du calcul : erreur, commande bloquée, puis "Réessayer" fonctionne', () async {
      var echec = true;
      final controller = EstimationCourseController(
        type: 'COLIS',
        pricingRepository: _TarificationScriptee(() {
          if (echec) throw ApiException('Serveur injoignable.');
          return 2500;
        }),
      )
        ..definirDepart(_plateau)
        ..definirArrivee(_almadies);
      await Future<void>.delayed(Duration.zero);
      expect(controller.etat, EtatEstimation.erreur);
      expect(controller.erreur, 'Serveur injoignable.');
      expect(controller.peutCommander, isFalse);

      echec = false;
      await controller.reessayer();
      expect(controller.etat, EtatEstimation.prete);
      expect(controller.estimation!.prixFcfa, 2500);
    });

    test('départ et arrivée identiques : refusé sans appeler la tarification', () {
      final tarification = _TarificationFactice();
      final controller = EstimationCourseController(type: 'PASSAGER', pricingRepository: tarification)
        ..definirDepart(_plateau)
        ..definirArrivee(_plateau);
      expect(controller.etat, EtatEstimation.erreur);
      expect(controller.erreur, contains('identiques'));
      expect(tarification.demandes, isEmpty);
    });

    test('une réponse en retard ne remplace pas le prix du dernier trajet choisi', () async {
      final tarification = _TarificationFactice();
      final controller = EstimationCourseController(type: 'PASSAGER', pricingRepository: tarification)
        ..definirDepart(_plateau)
        ..definirArrivee(_almadies)
        ..definirArrivee(_ouakam);

      tarification.repondre(1, 3200);
      await Future<void>.delayed(Duration.zero);
      tarification.repondre(0, 4800);
      await Future<void>.delayed(Duration.zero);

      expect(controller.estimation!.prixFcfa, 3200);
    });
  });

  group('Interface', () {
    testWidgets('prix affiché en grand, avec distance et durée', (tester) async {
      final tarification = _TarificationFactice();
      final controller = EstimationCourseController(type: 'PASSAGER', pricingRepository: tarification)
        ..definirDepart(_plateau)
        ..definirArrivee(_almadies);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: EstimationPrixCard(controller: controller))));
      expect(find.text('Calcul du prix…'), findsOneWidget);

      tarification.repondre(0, 4800);
      await tester.pumpAndSettle();
      expect(find.text('Prix estimé'), findsOneWidget);
      expect(find.text('~4 800 FCFA'), findsOneWidget);
      expect(find.text('≈ 20 min'), findsOneWidget);
    });

    testWidgets('écran Passager : "Commander" désactivé tant que le prix n\'est pas calculé', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: PassagerPage()));
      await tester.pump(const Duration(milliseconds: 100));

      final bouton = tester.widget<PrimaryButton>(find.byType(PrimaryButton));
      expect(bouton.onPressed, isNull);
      expect(find.textContaining('pour voir le prix'), findsOneWidget);
      expect(find.text('Le prix doit être calculé avant de commander.'), findsOneWidget);
    });
  });
}

class _TarificationScriptee extends PricingRepository {
  _TarificationScriptee(this._prix) : super(dio: Dio());

  final int Function() _prix;

  @override
  Future<EstimationPrix> estimer({required String type, required double distanceKm}) async =>
      EstimationPrix(distanceKm: distanceKm, dureeEstimeeMin: 15, multiplicateurTrafic: 1, prixFcfa: _prix());
}
