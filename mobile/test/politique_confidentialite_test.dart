import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/widgets/legal_page.dart';
import 'package:sprint/features/compte/presentation/politique_confidentialite_page.dart';

void main() {
  Future<LegalPage> ouvrir(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: PolitiqueConfidentialitePage()));
    return tester.widget<LegalPage>(find.byType(LegalPage));
  }

  String corps(LegalPage page, String titre) => page.sections.firstWhere((s) => s.titre == titre).corps;

  testWidgets('mise à jour du 9 octobre 2026, avec les sections approuvées par le client', (tester) async {
    final page = await ouvrir(tester);

    expect(page.derniereMiseAJour, '9 octobre 2026');
    expect(page.sections.map((s) => s.titre),
        containsAll(['Position GPS et mise en relation', 'Suivi technique des erreurs']));
    // Ordre : après le partage des données, avant la durée de conservation.
    final titres = page.sections.map((s) => s.titre).toList();
    expect(titres.indexOf('Partage des données'), lessThan(titres.indexOf('Position GPS et mise en relation')));
    expect(titres.indexOf('Suivi technique des erreurs'), lessThan(titres.indexOf('Durée de conservation')));
  });

  testWidgets('suivi technique des erreurs : Crashlytics, ce qui est envoyé, ce que Sprint n\'y ajoute pas',
      (tester) async {
    final texte = corps(await ouvrir(tester), 'Suivi technique des erreurs');

    expect(texte, contains('Firebase Crashlytics'));
    expect(texte, contains('version de l\'application'));
    expect(texte, contains('identifiant technique propre à l\'installation'));
    expect(
        texte,
        contains(
            'Sprint n\'y ajoute ni votre nom, ni votre numéro de téléphone, ni votre adresse e-mail, ni l\'identifiant de votre compte'));
    expect(texte, contains('pas utilisés à des fins publicitaires'));
    // Mot évité : le rapport contient un identifiant d'installation, il n'est donc pas anonyme.
    expect(texte.toLowerCase(), isNot(contains('anonym')));
  });

  testWidgets(
      'position GPS : transmise au chauffeur qui accepte, visible des chauffeurs disponibles avant, Google pour l\'itinéraire',
      (tester) async {
    final texte = corps(await ouvrir(tester), 'Position GPS et mise en relation');

    expect(texte, contains('Ma position actuelle'));
    expect(texte, contains('avec votre autorisation'));
    expect(texte, contains('Conducteur qui l\'accepte'));
    // Honnêteté : tant que la course attend, les chauffeurs disponibles y ont accès.
    expect(texte, contains('Les Conducteurs disponibles ont accès aux demandes en attente'));
    expect(texte, contains('Google Maps Platform'));
    expect(texte, contains('refuser ou retirer l\'autorisation'));
  });

  testWidgets('données collectées et base légale mentionnent la position GPS et le suivi des erreurs', (tester) async {
    final page = await ouvrir(tester);

    final collectees = corps(page, 'Données collectées');
    expect(collectees, contains('votre position GPS'));
    expect(collectees, contains('rapports techniques d\'erreur de l\'application Android'));

    final base = corps(page, 'Base légale');
    expect(base, contains('position GPS de votre téléphone'));
    expect(base, contains('intérêt légitime'));
  });
}
