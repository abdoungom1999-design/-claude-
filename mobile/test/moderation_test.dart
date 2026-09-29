import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/models/statut_compte.dart';
import 'package:sprint/features/admin/data/admin_kyc_service.dart';
import 'package:sprint/features/admin/presentation/widgets/dossier_chauffeur_panel.dart';
import 'package:sprint/features/conducteur/presentation/conducteur_compte_bloque_page.dart';

class _AdminKycServiceEspion extends AdminKycService {
  _AdminKycServiceEspion(this.statutCompte);

  final String statutCompte;
  final List<(String, String, String?)> sanctions = [];

  @override
  Stream<ConducteurKycAdmin?> streamConducteur(String uid) => Stream.value(
        ConducteurKycAdmin(
          id: uid,
          nom: 'Moussa Diop',
          telephone: '+221770000000',
          vehiculeId: 'Yamaha',
          plaqueImmatriculation: 'DK-1234-AB',
          statutValidation: 'valide',
          statutCompte: statutCompte,
          documents: const {},
        ),
      );

  @override
  Future<SanctionAppliquee> definirStatutCompte(String uid, String statut, {String? motif}) async {
    sanctions.add((uid, statut, motif));
    return const SanctionAppliquee(coursesAnnulees: 0, remboursements: 0);
  }
}

Future<void> _ouvrirDossier(WidgetTester tester, AdminKycService service) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => ouvrirDossierChauffeur(context, uid: 'chauffeur-1', service: service),
          child: const Text('Ouvrir'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Ouvrir'));
  await tester.pumpAndSettle();
}

/// Le panneau est une liste construite à la demande : on la fait
/// défiler jusqu'à la zone de modération, sous les pièces justificatives.
Future<void> _defilerJusqua(WidgetTester tester, Finder cible) =>
    tester.scrollUntilVisible(cible, 300, scrollable: find.byType(Scrollable).last);

Future<void> _sanctionner(WidgetTester tester, String bouton, String confirmation, {String motif = 'Plainte client'}) async {
  await _defilerJusqua(tester, find.text(bouton));
  await tester.tap(find.text(bouton));
  await tester.pumpAndSettle();
  await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), motif);
  await tester.tap(
    find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(FilledButton, confirmation)),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('Seuls les comptes suspendus ou bannis sont bloqués', () {
    expect(StatutCompte.estBloque(null), isFalse);
    expect(StatutCompte.estBloque(StatutCompte.actif), isFalse);
    expect(StatutCompte.estBloque(StatutCompte.suspendu), isTrue);
    expect(StatutCompte.estBloque(StatutCompte.banni), isTrue);
  });

  testWidgets('Dossier : "Suspendre le compte" écrit statutCompte = suspendu après confirmation', (tester) async {
    final service = _AdminKycServiceEspion(StatutCompte.actif);
    await _ouvrirDossier(tester, service);

    await _sanctionner(tester, 'Suspendre le compte', 'Suspendre');

    expect(service.sanctions, [('chauffeur-1', StatutCompte.suspendu, 'Plainte client')]);
  });

  testWidgets('Dossier : sanction sans motif refusée, rien n\'est envoyé', (tester) async {
    final service = _AdminKycServiceEspion(StatutCompte.actif);
    await _ouvrirDossier(tester, service);

    await _sanctionner(tester, 'Suspendre le compte', 'Suspendre', motif: '   ');

    expect(find.text('Indiquez le motif.'), findsOneWidget);
    expect(service.sanctions, isEmpty);
  });

  testWidgets('Dossier : "Bannir définitivement" écrit statutCompte = banni après confirmation', (tester) async {
    final service = _AdminKycServiceEspion(StatutCompte.actif);
    await _ouvrirDossier(tester, service);

    await _sanctionner(tester, 'Bannir définitivement', 'Bannir définitivement');

    expect(service.sanctions, [('chauffeur-1', StatutCompte.banni, 'Plainte client')]);
  });

  testWidgets('Dossier : annuler la confirmation n\'applique aucune sanction', (tester) async {
    final service = _AdminKycServiceEspion(StatutCompte.actif);
    await _ouvrirDossier(tester, service);

    await _defilerJusqua(tester, find.text('Suspendre le compte'));
    await tester.tap(find.text('Suspendre le compte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    expect(service.sanctions, isEmpty);
  });

  testWidgets('Dossier : un compte banni ne propose plus aucune action de modération', (tester) async {
    await _ouvrirDossier(tester, _AdminKycServiceEspion(StatutCompte.banni));
    await _defilerJusqua(tester, find.textContaining('Compte banni définitivement'));

    expect(find.textContaining('Compte banni définitivement'), findsOneWidget);
    expect(find.text('Suspendre le compte'), findsNothing);
    expect(find.text('Réactiver le compte'), findsNothing);
  });

  testWidgets('Chauffeur suspendu : écran d\'éjection explicite', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ConducteurCompteBloquePage(statutCompte: StatutCompte.suspendu)));
    expect(find.text('Compte suspendu'), findsOneWidget);
  });

  testWidgets('Chauffeur banni : écran d\'éjection explicite', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ConducteurCompteBloquePage(statutCompte: StatutCompte.banni)));
    expect(find.text('Compte désactivé'), findsOneWidget);
  });
}
