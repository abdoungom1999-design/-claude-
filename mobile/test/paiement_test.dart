import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/network/api_exception.dart';
import 'package:sprint/core/utils/format_fcfa.dart';
import 'package:sprint/core/widgets/payment_method_selector.dart';
import 'package:sprint/features/client/presentation/payment_processing_page.dart';
import 'package:sprint/features/courses/data/course_service.dart';

/// Serveur factice : renvoie un lien de paiement, puis l'état de la
/// commande que le test fait évoluer (comme le webhook de l'opérateur).
class _ServeurFactice extends CourseService {
  _ServeurFactice({this.refus});

  /// Erreur renvoyée par le serveur à la demande de paiement.
  final Exception? refus;
  final commande = StreamController<CommandePaiement?>();
  PointsCourse? pointsRecus;
  int? prixRecu;
  String? methodeRecue;
  String? commandeSuivie;

  @override
  Future<DemandePaiement> creerPaiement({
    required String type,
    required String adresseDepart,
    required String adresseArrivee,
    required int prixFcfa,
    required String methodePaiement,
    required PointsCourse points,
  }) async {
    pointsRecus = points;
    prixRecu = prixFcfa;
    methodeRecue = methodePaiement;
    if (refus case final erreur?) throw erreur;
    return DemandePaiement(
      commandeId: 'k1',
      lienPaiement: Uri.parse('https://paiement.test/?session=sim_1'),
      prixFcfa: prixFcfa,
    );
  }

  @override
  Stream<CommandePaiement?> streamCommande(String commandeId) {
    commandeSuivie = commandeId;
    return commande.stream;
  }
}

class _Sas {
  String? retour;
  final liensOuverts = <Uri>[];
}

/// Ouvre le sas de paiement depuis un écran "commande" factice.
Future<_Sas> _ouvrirSas(
  WidgetTester tester,
  CourseService serveur, {
  PaymentMethod methode = PaymentMethod.wave,
  bool lienOuvrable = true,
}) async {
  final sas = _Sas();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            sas.retour = await Navigator.of(context).push<String>(
              MaterialPageRoute(
                builder: (_) => PaymentProcessingPage(
                  methode: methode,
                  type: 'PASSAGER',
                  adresseDepart: 'Plateau',
                  adresseArrivee: 'Almadies',
                  prixFcfa: 2100,
                  points: const PointsCourse(
                    latitudeDepart: 14.668,
                    longitudeDepart: -17.438,
                    latitudeArrivee: 14.745,
                    longitudeArrivee: -17.517,
                  ),
                  courseService: serveur,
                  ouvrirLien: (lien) async {
                    sas.liensOuverts.add(lien);
                    return lienOuvrable;
                  },
                ),
              ),
            );
          },
          child: const Text('Commander'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Commander'));
  await tester.pumpAndSettle();
  return sas;
}

/// Laisse passer les animations (un indicateur d'attente tourne sans fin :
/// pas de pumpAndSettle).
Future<void> _attendre(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _recevoir(WidgetTester tester, _ServeurFactice serveur, CommandePaiement commande) async {
  serveur.commande.add(commande);
  await tester.pumpAndSettle();
}

void main() {
  final payer = find.text('Payer avec Wave · ${formaterFcfa(2100)}');

  testWidgets('demande de paiement au serveur : prix vu, trajet et opérateur envoyés', (tester) async {
    final serveur = _ServeurFactice();
    await _ouvrirSas(tester, serveur, methode: PaymentMethod.orangeMoney);

    expect(serveur.prixRecu, 2100);
    expect(serveur.methodeRecue, 'ORANGE_MONEY');
    expect(serveur.pointsRecus?.latitudeDepart, 14.668);
    expect(serveur.commandeSuivie, 'k1');
    expect(find.text('Payer avec Orange Money · ${formaterFcfa(2100)}'), findsOneWidget);
  });

  testWidgets('le client ouvre la page de paiement de l\'opérateur, puis attend la confirmation', (tester) async {
    final serveur = _ServeurFactice();
    final sas = await _ouvrirSas(tester, serveur);

    await tester.tap(payer);
    await _attendre(tester);

    expect(sas.liensOuverts, [Uri.parse('https://paiement.test/?session=sim_1')]);
    expect(find.text('En attente de la confirmation de\nvotre paiement Wave…'), findsOneWidget);
    // Page fermée par erreur : on peut la rouvrir.
    await tester.tap(find.text('Rouvrir la page de paiement'));
    await tester.pump();
    expect(sas.liensOuverts, hasLength(2));
  });

  testWidgets('tant que le serveur n\'a pas confirmé, aucune course n\'est suivie', (tester) async {
    final serveur = _ServeurFactice();
    await _ouvrirSas(tester, serveur);
    await tester.tap(payer);
    await _attendre(tester);

    serveur.commande.add(const CommandePaiement(statut: StatutCommande.enAttente));
    await _attendre(tester);
    expect(find.text('Paiement confirmé !'), findsNothing);
    expect(find.textContaining('En attente de la confirmation'), findsOneWidget);
  });

  testWidgets('paiement confirmé par le serveur : la course créée est suivie', (tester) async {
    final serveur = _ServeurFactice();
    await _ouvrirSas(tester, serveur);
    await tester.tap(payer);
    await _attendre(tester);

    serveur.commande.add(const CommandePaiement(statut: StatutCommande.payee, courseId: 'course-1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Paiement confirmé !'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    // L'écran suivant (SuiviCoursePage) écoute Firestore, indisponible
    // dans les tests : l'erreur attendue est absorbée ici.
    tester.takeException();
  });

  testWidgets('paiement refusé chez l\'opérateur : retour à la commande avec un message', (tester) async {
    final serveur = _ServeurFactice();
    final sas = await _ouvrirSas(tester, serveur);
    await tester.tap(payer);
    await _attendre(tester);

    await _recevoir(tester, serveur, const CommandePaiement(statut: StatutCommande.echouee));

    expect(sas.retour, "Paiement Wave refusé ou annulé. Aucune course n'a été créée.");
    expect(find.text('Commander'), findsOneWidget);
  });

  testWidgets('délai de paiement dépassé : retour avec un message', (tester) async {
    final serveur = _ServeurFactice();
    final sas = await _ouvrirSas(tester, serveur);

    await _recevoir(tester, serveur, const CommandePaiement(statut: StatutCommande.expiree));

    expect(sas.retour, "Le délai de paiement est dépassé. Aucune course n'a été créée.");
  });

  testWidgets('paiement à vérifier (montant incohérent) : le client est rassuré sur le remboursement', (tester) async {
    final serveur = _ServeurFactice();
    final sas = await _ouvrirSas(tester, serveur);

    await _recevoir(tester, serveur, const CommandePaiement(statut: 'anomalie'));

    expect(sas.retour, contains('vous serez remboursé'));
  });

  testWidgets('le client abandonne avant de payer : aucune course', (tester) async {
    final serveur = _ServeurFactice();
    final sas = await _ouvrirSas(tester, serveur);

    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    expect(sas.retour, "Paiement annulé. Aucune course n'a été créée.");
    expect(sas.liensOuverts, isEmpty);
  });

  testWidgets('page de paiement impossible à ouvrir : message, le client reste dans le sas', (tester) async {
    final serveur = _ServeurFactice();
    final sas = await _ouvrirSas(tester, serveur, lienOuvrable: false);

    await tester.tap(payer);
    await tester.pump();

    expect(find.text("Impossible d'ouvrir la page de paiement Wave. Réessayez."), findsOneWidget);
    expect(sas.retour, isNull);
    expect(payer, findsOneWidget);
  });

  testWidgets('prix changé côté serveur : aucun paiement, le nouveau prix est annoncé', (tester) async {
    final sas = await _ouvrirSas(tester, _ServeurFactice(refus: const PrixModifie(2600)));

    expect(
      sas.retour,
      'Le prix de ce trajet vient de changer : ${formaterFcfa(2600)}. '
      "Aucune course n'a été créée : vérifiez le nouveau prix avant de commander.",
    );
    expect(find.text('Commander'), findsOneWidget);
  });

  testWidgets('demande refusée par le serveur : son message est affiché', (tester) async {
    final sas = await _ouvrirSas(
      tester,
      _ServeurFactice(refus: ApiException('Votre compte ne permet pas de commander une course.')),
    );

    expect(sas.retour, "Votre compte ne permet pas de commander une course. Aucune course n'a été créée.");
  });
}
