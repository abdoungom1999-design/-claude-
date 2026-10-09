import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sprint/core/location/localiser.dart';
import 'package:sprint/core/maps/geocoding_service.dart';
import 'package:sprint/core/utils/format_fcfa.dart';
import 'package:sprint/core/widgets/primary_button.dart';
import 'package:sprint/features/client/presentation/colis_page.dart';
import 'package:sprint/features/client/presentation/widgets/depart_gps_etat.dart';
import 'package:sprint/features/courses/data/course_service.dart';
import 'package:sprint/features/courses/data/pricing_repository.dart';

const _moi = LatLng(14.701234, -17.456789);

final _livraison = AdresseSuggestion(libelle: 'Almadies, Dakar', latitude: 14.7450, longitude: -17.5170);

class _Adresses implements ServiceAdresses {
  @override
  Future<List<PropositionAdresse>> rechercher(String texte) async =>
      [PropositionAdresse(principal: 'Almadies', secondaire: 'Dakar', coordonnees: _livraison)];

  @override
  Future<AdresseSuggestion> resoudre(PropositionAdresse proposition) async => proposition.coordonnees!;
}

class _Tarification extends PricingRepository {
  _Tarification() : super(dio: Dio());

  @override
  Future<EstimationPrix> estimer({required String type, required double distanceKm, PointsCourse? trajet}) async =>
      EstimationPrix(distanceKm: distanceKm, dureeEstimeeMin: 20, multiplicateurTrafic: 1, prixFcfa: 1800);
}

Localiser _gps(List<LatLng?> reponses, [List<bool>? demandes]) {
  var n = 0;
  return ({required bool demander}) async {
    demandes?.add(demander);
    return reponses[(n++).clamp(0, reponses.length - 1)];
  };
}

void main() {
  Future<void> afficher(WidgetTester tester, Localiser localiser) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: ColisPage(localiser: localiser, adresses: _Adresses(), pricingRepository: _Tarification()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  final champRetrait = find.widgetWithText(TextFormField, 'Adresse de retrait');
  final champLivraison = find.widgetWithText(TextFormField, 'Adresse de livraison');

  String texteDe(WidgetTester tester, Finder champ) =>
      tester.widget<EditableText>(find.descendant(of: champ, matching: find.byType(EditableText))).controller.text;

  testWidgets('à l\'ouverture, la position GPS est demandée et remplit le point de retrait', (tester) async {
    final demandes = <bool>[];
    await afficher(tester, _gps([_moi], demandes));

    expect(demandes.where((d) => d), hasLength(1), reason: 'une demande avec autorisation, celle de l\'écran');
    expect(texteDe(tester, champRetrait), 'Ma position actuelle');
    expect(find.text(DepartGpsEtat.messageActifColis), findsOneWidget);
    expect(find.textContaining('Modifiez l\'adresse si le colis est ailleurs'), findsOneWidget);
    expect(tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed, isNull);
  });

  testWidgets('retrait GPS + livraison choisie : prix calculé, « Envoyer le colis » s\'active', (tester) async {
    await afficher(tester, _gps([_moi]));

    await tester.enterText(champLivraison, 'Alma');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Almadies'));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('~${formaterFcfa(1800)}'), findsOneWidget);
    final bouton = tester.widget<PrimaryButton>(find.byType(PrimaryButton));
    expect(bouton.label, 'Envoyer le colis');
    expect(bouton.onPressed, isNotNull);
  });

  testWidgets('GPS introuvable : champ vide, explication, « Réessayer » reprend la position', (tester) async {
    await afficher(tester, _gps([null, _moi]));

    expect(texteDe(tester, champRetrait), isEmpty);
    expect(find.textContaining('Position GPS introuvable'), findsOneWidget);

    await tester.tap(find.text('Réessayer'));
    await tester.pump();
    await tester.pump();

    expect(texteDe(tester, champRetrait), 'Ma position actuelle');
    expect(find.textContaining('Position GPS introuvable'), findsNothing);
  });

  testWidgets('le colis est ailleurs : le client change l\'adresse de retrait, puis peut reprendre sa position',
      (tester) async {
    await afficher(tester, _gps([_moi]));

    await tester.enterText(champRetrait, 'Boutique, Médina');
    await tester.pump();
    expect(find.text(DepartGpsEtat.messageActifColis), findsNothing);
    expect(find.text('Utiliser ma position actuelle'), findsOneWidget);

    await tester.tap(find.text('Utiliser ma position actuelle'));
    await tester.pumpAndSettle();
    expect(texteDe(tester, champRetrait), 'Ma position actuelle');
  });
}
