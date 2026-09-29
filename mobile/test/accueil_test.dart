import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:sprint/core/maps/fond_carte.dart';
import 'package:sprint/core/widgets/moto_vue_dessus.dart';
import 'package:sprint/features/home/data/proximite_service.dart';
import 'package:sprint/features/home/presentation/home_tab_page.dart';

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

Proximite _motos(int n, {int? approche = 3}) => Proximite(
      motos: [for (var i = 0; i < n; i++) MotoProche(position: LatLng(14.69 + i * 0.002, -17.44), cap: 90)],
      approcheMinutes: approche,
    );

void main() {
  // Sans clé Google : fond OpenStreetMap (aucun appel réseau à Google).
  final fond = FondCarte(cle: '', dio: Dio());

  Future<GoRouter> afficher(
    WidgetTester tester,
    ProximiteService service, {
    Localiser? localiser,
    Size taille = const Size(390, 844),
  }) async {
    tester.view.physicalSize = taille;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final routeur = GoRouter(
      initialLocation: '/accueil',
      routes: [
        GoRoute(
          path: '/accueil',
          builder: (_, __) => HomeTabPage(
            proximite: service,
            fond: fond,
            coucheFond: const SizedBox.shrink(),
            localiser: localiser ?? ({required bool demander}) async => null,
          ),
        ),
        GoRoute(path: '/client/passager', builder: (_, __) => const Scaffold(body: Text('PAGE PASSAGER'))),
        GoRoute(path: '/client/colis', builder: (_, __) => const Scaffold(body: Text('PAGE COLIS'))),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: routeur));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return routeur;
  }

  testWidgets('accueil : carte plein écran, motos vues de haut, disponibilité et approche', (tester) async {
    final service = _ProximiteFactice(() => _motos(5));
    await afficher(tester, service);

    expect(find.text('Où allez-vous ?'), findsOneWidget);
    expect(find.byType(MotoVueDessus), findsNWidgets(5));
    expect(find.text('5 motos disponibles à proximité · environ 3 min'), findsOneWidget);
    // Recherche autour du centre de Dakar tant que le client n'est pas localisé.
    expect(service.appels.single, HomeTabPage.centreDakar);
    // Plus de photos ni de carrousel.
    expect(find.text('Découvrez nos univers'), findsNothing);
    expect(find.text('Pourquoi Sprint'), findsNothing);
  });

  testWidgets('aucune moto, une seule moto, puis mise à jour périodique', (tester) async {
    var n = 0;
    final service = _ProximiteFactice(() => _motos(n, approche: n == 0 ? null : 2));
    await afficher(tester, service);
    expect(find.text('Aucune moto disponible ici pour le moment'), findsOneWidget);
    expect(find.byType(MotoVueDessus), findsNothing);

    n = 1;
    await tester.pump(HomeTabPage.rafraichissement);
    await tester.pump();
    expect(find.text('1 moto disponible à proximité · environ 2 min'), findsOneWidget);
    expect(service.appels, hasLength(2));
  });

  testWidgets('serveur injoignable : les motos déjà affichées restent', (tester) async {
    var panne = false;
    final service = _ProximiteFactice(() => panne ? throw Exception('réseau') : _motos(3));
    await afficher(tester, service);
    expect(find.byType(MotoVueDessus), findsNWidgets(3));

    panne = true;
    await tester.pump(HomeTabPage.rafraichissement);
    await tester.pump();
    expect(find.byType(MotoVueDessus), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('client déjà localisé : sa position affichée, motos cherchées autour de lui', (tester) async {
    const moi = LatLng(14.7167, -17.4677);
    final demandes = <bool>[];
    final service = _ProximiteFactice(() => _motos(2));
    await afficher(tester, service, localiser: ({required bool demander}) async {
      demandes.add(demander);
      return moi;
    });
    await tester.pump();

    expect(demandes.first, isFalse); // jamais de demande d'autorisation à l'ouverture
    expect(find.byWidgetPredicate((w) => w.runtimeType.toString() == '_PointMoi'), findsOneWidget);
    expect(service.appels.last, moi);

    await tester.tap(find.byTooltip('Me localiser'));
    await tester.pump();
    expect(demandes.last, isTrue); // demandée seulement sur le bouton
  });

  testWidgets('localisation refusée sur le bouton : message clair', (tester) async {
    await afficher(tester, _ProximiteFactice(() => _motos(0)));
    await tester.tap(find.byTooltip('Me localiser'));
    await tester.pump();
    expect(find.textContaining('Position indisponible'), findsOneWidget);
  });

  testWidgets('recherche et services : ouvrent la course moto ou le colis', (tester) async {
    await afficher(tester, _ProximiteFactice(() => _motos(1)));
    await tester.tap(find.text('Rechercher une destination'));
    await tester.pumpAndSettle();
    expect(find.text('PAGE PASSAGER'), findsOneWidget);
  });

  testWidgets('service Colis', (tester) async {
    await afficher(tester, _ProximiteFactice(() => _motos(1)));
    await tester.tap(find.text('Colis'));
    await tester.pumpAndSettle();
    expect(find.text('PAGE COLIS'), findsOneWidget);
  });

  testWidgets('grand écran : carte flottante limitée à la largeur d\'un téléphone', (tester) async {
    await afficher(tester, _ProximiteFactice(() => _motos(1)), taille: const Size(1280, 800));
    final carte = tester.getRect(find.ancestor(of: find.text('Où allez-vous ?'), matching: find.byType(Container)).first);
    expect(carte.width, lessThanOrEqualTo(460));
    expect(carte.left, 16);
  });

  test('mode démo : quelques motos, toujours les mêmes pour un même quartier', () async {
    const demo = ProximiteDemo();
    final a = await demo.chauffeursProches(const LatLng(14.6928, -17.4467));
    final b = await demo.chauffeursProches(const LatLng(14.6929, -17.4468));
    expect(a.motos, hasLength(6));
    expect([for (final m in a.motos) m.position], [for (final m in b.motos) m.position]);
    expect(a.approcheMinutes, 3);
  });
}
