import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sprint/core/location/localiser.dart';
import 'package:sprint/core/maps/geocoding_service.dart';
import 'package:sprint/core/maps/motos_proches_controller.dart';
import 'package:sprint/core/maps/proximite_service.dart';
import 'package:sprint/core/widgets/moto_vue_dessus.dart';
import 'package:sprint/core/widgets/trip_map.dart';
import 'package:sprint/features/client/presentation/widgets/carte_commande.dart';
import 'package:sprint/features/courses/data/course_service.dart';
import 'package:sprint/features/courses/data/estimation_course_controller.dart';
import 'package:sprint/features/courses/data/pricing_repository.dart';

class _ProximiteFactice implements ProximiteService {
  _ProximiteFactice(this.reponse);

  Proximite Function() reponse;
  final appels = <LatLng>[];

  @override
  Future<Proximite> chauffeursProches(LatLng autour) async {
    appels.add(autour);
    return reponse();
  }
}

class _Tarification extends PricingRepository {
  _Tarification() : super(dio: Dio());

  @override
  Future<EstimationPrix> estimer({required String type, required double distanceKm, PointsCourse? trajet}) async =>
      EstimationPrix(distanceKm: distanceKm, dureeEstimeeMin: 20, multiplicateurTrafic: 1, prixFcfa: 1500);
}

Proximite _motos(int n, {int? approche = 3}) => Proximite(
      motos: [for (var i = 0; i < n; i++) MotoProche(position: LatLng(14.69 + i * 0.002, -17.44), cap: 90)],
      approcheMinutes: approche,
    );

final _plateau = AdresseSuggestion(libelle: 'Plateau', latitude: 14.6680, longitude: -17.4380);
final _almadies = AdresseSuggestion(libelle: 'Almadies', latitude: 14.7450, longitude: -17.5170);

void main() {
  late EstimationCourseController estimation;

  setUp(() => estimation = EstimationCourseController(type: 'PASSAGER', pricingRepository: _Tarification()));
  tearDown(() => estimation.dispose());

  Future<void> afficher(
    WidgetTester tester,
    _ProximiteFactice service, {
    Localiser? localiser,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CarteCommande(
            estimation: estimation,
            proximite: service,
            localiser: localiser ?? ({required bool demander}) async => null,
            // Pas de réseau dans les tests : fond vide.
            coucheFond: const SizedBox.shrink(),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('les motos disponibles restent visibles sur la carte pendant la commande', (tester) async {
    final service = _ProximiteFactice(() => _motos(4));
    await afficher(tester, service);

    expect(find.byType(TripMap), findsOneWidget);
    expect(find.byType(MotoVueDessus), findsNWidgets(4));
    expect(find.text('4 motos disponibles · ~3 min'), findsOneWidget);
    // Client ni localisé ni départ choisi : autour du centre de Dakar.
    expect(service.appels.single, CarteCommande.centreDakar);
  });

  testWidgets('départ choisi : les motos sont cherchées autour du départ, pas à chaque calcul de prix', (tester) async {
    final service = _ProximiteFactice(() => _motos(2));
    await afficher(tester, service);
    expect(service.appels, hasLength(1));

    estimation.definirDepart(_plateau);
    await tester.pump();
    await tester.pump();
    expect(service.appels.last, LatLng(_plateau.latitude, _plateau.longitude));
    expect(service.appels, hasLength(2));

    // L'arrivée choisie déclenche le calcul du prix (notifications
    // répétées) : le départ n'a pas bougé, aucun nouvel appel serveur.
    estimation.definirArrivee(_almadies);
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(estimation.peutCommander, isTrue);
    expect(service.appels, hasLength(2));
    // Le trajet et les motos cohabitent sur la même carte.
    expect(find.byType(MotoVueDessus), findsNWidgets(2));

    // Départ effacé : retour autour du centre de Dakar.
    estimation.oublierDepart();
    await tester.pump();
    await tester.pump();
    expect(service.appels.last, CarteCommande.centreDakar);
  });

  testWidgets('client déjà localisé : motos cherchées autour de lui, sans jamais demander l\'autorisation', (tester) async {
    const moi = LatLng(14.7167, -17.4677);
    final demandes = <bool>[];
    final service = _ProximiteFactice(() => _motos(1));
    await afficher(tester, service, localiser: ({required bool demander}) async {
      demandes.add(demander);
      return moi;
    });
    await tester.pump();

    expect(demandes, [false]);
    expect(service.appels.last, moi);
  });

  testWidgets('aucune moto, une seule moto, serveur injoignable', (tester) async {
    var n = 0;
    var panne = false;
    final service = _ProximiteFactice(() => panne ? throw Exception('réseau') : _motos(n, approche: n == 0 ? null : 2));
    await afficher(tester, service);
    expect(find.text('Aucune moto à proximité pour le moment'), findsOneWidget);

    n = 1;
    await tester.pump(const Duration(seconds: 20));
    await tester.pump();
    expect(find.text('1 moto disponible · ~2 min'), findsOneWidget);

    // Réseau coupé : la moto déjà affichée reste.
    panne = true;
    await tester.pump(const Duration(seconds: 20));
    await tester.pump();
    expect(find.byType(MotoVueDessus), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la carte se recadre sans erreur quand le départ et l\'arrivée changent', (tester) async {
    await afficher(tester, _ProximiteFactice(() => _motos(1)));
    estimation.definirDepart(_plateau);
    await tester.pump();
    await tester.pump();
    estimation.definirArrivee(_almadies);
    await tester.pump();
    await tester.pump();
    estimation.oublierArrivee();
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  test('contrôleur : une réponse arrivée après un changement de point est ignorée', () async {
    final lente = <LatLng>[];
    late Proximite Function() reponse;
    final service = _ServiceDiffere((point) {
      lente.add(point);
      return reponse();
    });
    final controleur = MotosProchesController(service: service, rafraichissement: const Duration(hours: 1));
    reponse = () => _motos(5);
    final premiere = controleur.chercherAutour(const LatLng(14.0, -17.0));
    reponse = () => _motos(2);
    final seconde = controleur.chercherAutour(const LatLng(14.7, -17.4));
    service.liberer(1);
    await seconde;
    service.liberer(0);
    await premiere;
    expect(controleur.motos, hasLength(2));
    controleur.dispose();
  });
}

/// Service dont chaque réponse attend que le test la libère.
class _ServiceDiffere implements ProximiteService {
  _ServiceDiffere(this._calculer);

  final Proximite Function(LatLng) _calculer;
  final _portes = <Completer<void>>[];

  @override
  Future<Proximite> chauffeursProches(LatLng autour) async {
    final resultat = _calculer(autour);
    final porte = Completer<void>();
    _portes.add(porte);
    await porte.future;
    return resultat;
  }

  void liberer(int i) => _portes[i].complete();
}
