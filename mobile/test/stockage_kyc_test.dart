import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/network/api_exception.dart';
import 'package:sprint/features/admin/data/admin_kyc_service.dart';
import 'package:sprint/features/admin/presentation/widgets/carte_stockage_kyc.dart';

class _KycFactice extends AdminKycService {
  _KycFactice(this.reponses);

  /// Réponses successives ; une [ApiException] est levée telle quelle.
  final List<Object> reponses;
  final appels = <bool>[];

  @override
  Future<BilanMigrationKyc> migrerDocumentsKyc({bool apercu = false}) async {
    appels.add(apercu);
    final r = reponses.removeAt(0);
    if (r is ApiException) throw r;
    return r as BilanMigrationKyc;
  }
}

BilanMigrationKyc _bilan({int aMigrer = 0, int chauffeurs = 0, int migres = 0, int ignores = 0, int restants = 0}) =>
    BilanMigrationKyc(
      documentsAMigrer: aMigrer,
      chauffeursConcernes: chauffeurs,
      migres: migres,
      ignores: ignores,
      restants: restants,
    );

Future<void> _afficher(WidgetTester tester, AdminKycService service) async {
  tester.view.physicalSize = const Size(1000, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: CarteStockageKyc(service: service)))));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('aperçu automatique, puis migration par lots jusqu\'à « terminée »', (tester) async {
    final service = _KycFactice([
      _bilan(aMigrer: 14, chauffeurs: 13, restants: 14),
      // lot 1, puis relecture de l'état réel
      _bilan(aMigrer: 14, chauffeurs: 13, migres: 10, restants: 4),
      _bilan(aMigrer: 4, chauffeurs: 3, restants: 4),
      // lot 2, puis relecture
      _bilan(aMigrer: 4, chauffeurs: 3, migres: 4, restants: 0),
      _bilan(),
    ]);
    await _afficher(tester, service);

    expect(service.appels, [true], reason: 'au chargement : aperçu seulement, rien n\'est écrit');
    expect(find.text('14 pièce(s) encore en Base64, chez 13 chauffeur(s).'), findsOneWidget);

    await tester.tap(find.text('Migrer vers Storage'));
    await tester.pumpAndSettle();
    expect(service.appels, [true, false, true]);
    expect(find.text('10 pièce(s) déplacée(s). Relancez pour continuer (4 restante(s)).'), findsOneWidget);
    expect(find.text('4 pièce(s) encore en Base64, chez 3 chauffeur(s).'), findsOneWidget);

    await tester.tap(find.text('Migrer vers Storage'));
    await tester.pumpAndSettle();
    expect(find.text('Migration terminée : 4 pièce(s) déplacée(s) dans Firebase Storage.'), findsOneWidget);
    expect(find.text('Aucune pièce en Base64 : tout est dans Firebase Storage.'), findsOneWidget);
    expect(find.text('Migrer vers Storage'), findsNothing, reason: 'plus rien à migrer : le bouton disparaît');
  });

  testWidgets('Storage non activé : le message du serveur est affiché, rien n\'est présenté comme migré', (tester) async {
    final service = _KycFactice([
      _bilan(aMigrer: 2, chauffeurs: 2, restants: 2),
      ApiException("Firebase Storage n'est pas utilisable (activé dans la Console ? règles publiées ?) : aucune pièce n'a été modifiée."),
    ]);
    await _afficher(tester, service);
    await tester.tap(find.text('Migrer vers Storage'));
    await tester.pumpAndSettle();

    expect(find.textContaining("Firebase Storage n'est pas utilisable"), findsOneWidget);
    expect(find.textContaining('Migration terminée'), findsNothing);
    expect(find.text('2 pièce(s) encore en Base64, chez 2 chauffeur(s).'), findsOneWidget);
    expect(find.text('Migrer vers Storage'), findsOneWidget, reason: 'on peut réessayer');
  });

  testWidgets('aucun document Base64 : pas de bouton de migration', (tester) async {
    await _afficher(tester, _KycFactice([_bilan()]));
    expect(find.text('Aucune pièce en Base64 : tout est dans Firebase Storage.'), findsOneWidget);
    expect(find.text('Migrer vers Storage'), findsNothing);
  });
}
