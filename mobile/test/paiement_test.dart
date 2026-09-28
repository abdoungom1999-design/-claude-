import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/network/api_exception.dart';
import 'package:sprint/core/utils/format_fcfa.dart';
import 'package:sprint/core/widgets/payment_method_selector.dart';
import 'package:sprint/features/client/presentation/payment_processing_page.dart';
import 'package:sprint/features/courses/data/course_service.dart';
import 'package:sprint/features/paiement/data/paiement_service.dart';

class _PaiementRefuse implements PaiementService {
  @override
  Future<TransactionResult> initierPaiementWave(double montant) async =>
      const TransactionResult(statut: StatutTransaction.echec, id: '');

  @override
  Future<TransactionResult> initierPaiementOrangeMoney(double montant) async =>
      const TransactionResult(statut: StatutTransaction.echec, id: '');
}

class _CourseServiceEspion extends CourseService {
  _CourseServiceEspion({this.refus});

  /// Erreur renvoyée par le serveur à la création, le cas échéant.
  final Exception? refus;
  String? transactionIdRecu;
  PointsCourse? pointsRecus;
  int? prixRecu;

  @override
  Future<String> creerCourse({
    required String type,
    required String adresseDepart,
    required String adresseArrivee,
    required int prixFcfa,
    required String methodePaiement,
    required String transactionId,
    required PointsCourse points,
  }) async {
    transactionIdRecu = transactionId;
    pointsRecus = points;
    prixRecu = prixFcfa;
    if (refus case final erreur?) throw erreur;
    return 'course-test';
  }
}

/// Ouvre le sas de paiement depuis un écran "commande" factice et
/// renvoie le message éventuellement retourné à la fermeture.
Future<String?> _ouvrirSas(
  WidgetTester tester, {
  required PaiementService paiement,
  required CourseService courses,
}) async {
  String? retour;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            retour = await Navigator.of(context).push<String>(
              MaterialPageRoute(
                builder: (_) => PaymentProcessingPage(
                  methode: PaymentMethod.wave,
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
                  paiementService: paiement,
                  courseService: courses,
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
  await tester.pump();
  await tester.pump(const Duration(seconds: 3));
  return retour;
}

void main() {
  test('Sandbox : Wave et Orange Money renvoient un succès avec une référence de test', () async {
    const service = PaiementServiceSandbox(delai: Duration.zero);

    final wave = await service.initierPaiementWave(2100);
    final orange = await service.initierPaiementOrangeMoney(2100);

    expect(wave.estReussie, isTrue);
    expect(wave.id, startsWith('TXN-WAVE-DEMO'));
    expect(orange.estReussie, isTrue);
    expect(orange.id, startsWith('TXN-OM-DEMO'));
  });

  testWidgets('Paiement refusé : aucune course créée, retour à la commande avec un message', (tester) async {
    final courses = _CourseServiceEspion();

    final retour = await _ouvrirSas(tester, paiement: _PaiementRefuse(), courses: courses);

    expect(courses.transactionIdRecu, isNull);
    expect(retour, contains('refusé'));
    expect(find.text('Commander'), findsOneWidget);
  });

  testWidgets('Paiement réussi : la course est créée avec la référence de transaction', (tester) async {
    final courses = _CourseServiceEspion();

    await _ouvrirSas(
      tester,
      paiement: const PaiementServiceSandbox(delai: Duration(milliseconds: 100)),
      courses: courses,
    );

    expect(courses.transactionIdRecu, startsWith('TXN-WAVE-DEMO'));
    // Coordonnées du point de prise en charge enregistrées pour le suivi
    // d'approche côté client.
    expect(courses.pointsRecus?.latitudeDepart, 14.668);
    // L'écran suivant (SuiviCoursePage) écoute Firestore, indisponible
    // dans les tests : l'erreur attendue est absorbée ici.
    tester.takeException();
  });

  testWidgets('Prix changé côté serveur : aucune course, le nouveau prix est annoncé', (tester) async {
    final courses = _CourseServiceEspion(refus: const PrixModifie(2600));

    final retour = await _ouvrirSas(
      tester,
      paiement: const PaiementServiceSandbox(delai: Duration.zero),
      courses: courses,
    );

    // Le prix vu par le client est envoyé au serveur, pour contrôle.
    expect(courses.prixRecu, 2100);
    expect(
      retour,
      'Le prix de ce trajet vient de changer : ${formaterFcfa(2600)}. '
      "Aucune course n'a été créée : vérifiez le nouveau prix avant de commander.",
    );
    expect(find.text('Commander'), findsOneWidget);
  });

  testWidgets('Commande refusée par le serveur : son message est affiché', (tester) async {
    final courses = _CourseServiceEspion(refus: ApiException('Votre compte ne permet pas de commander une course.'));

    final retour = await _ouvrirSas(
      tester,
      paiement: const PaiementServiceSandbox(delai: Duration.zero),
      courses: courses,
    );

    expect(retour, "Votre compte ne permet pas de commander une course. Aucune course n'a été créée.");
  });
}
