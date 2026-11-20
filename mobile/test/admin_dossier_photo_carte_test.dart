// Publication 146 : l'Admin voit la PHOTO du chauffeur et sa CARTE D'IDENTITÉ
// (les deux pièces demandées désormais) et peut approuver le dossier. Les anciens
// dossiers (carte d'identité + carte grise, sans photo) restent validables.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sprint/core/models/statut_compte.dart';
import 'package:sprint/features/admin/data/admin_kyc_service.dart';
import 'package:sprint/features/admin/presentation/widgets/dossier_chauffeur_panel.dart';
import 'package:sprint/features/conducteur/data/compression_image.dart';

class _AdminKycServiceEspion extends AdminKycService {
  _AdminKycServiceEspion(this.documents);

  final Map<String, dynamic> documents;
  final List<String> approuves = [];

  @override
  Stream<ConducteurKycAdmin?> streamConducteur(String uid) => Stream.value(
        ConducteurKycAdmin(
          id: uid,
          nom: 'Moussa Diop',
          telephone: '+221770000000',
          vehiculeId: 'Yamaha',
          plaqueImmatriculation: null,
          statutValidation: 'en_attente',
          statutCompte: StatutCompte.actif,
          documents: documents,
        ),
      );

  @override
  Future<void> approuverConducteur(String uid) async => approuves.add(uid);
}

/// Une photo telle que l'app l'enregistre après compression (JPEG de moins de
/// 150 Ko), sous forme d'image encodée : le même rendu que l'adresse Storage,
/// sans réseau.
String _photoCompressee(int largeur, int hauteur) {
  final image = img.Image(width: largeur, height: hauteur);
  for (var y = 0; y < hauteur; y++) {
    for (var x = 0; x < largeur; x++) {
      image.setPixelRgb(x, y, x * 255 ~/ largeur, y * 255 ~/ hauteur, 120);
    }
  }
  final octets = Uint8List.fromList(img.encodeJpg(image, quality: 65));
  expect(octets.lengthInBytes, lessThan(tailleMaxImageKyc));
  return 'data:image/jpeg;base64,${base64Encode(octets)}';
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

Future<void> _defilerJusqua(WidgetTester tester, Finder cible) =>
    tester.scrollUntilVisible(cible, 300, scrollable: find.byType(Scrollable).last);

Finder _boutonApprouver() => find.ancestor(of: find.text('Approuver le chauffeur'), matching: find.bySubtype<ButtonStyleButton>());

void main() {
  testWidgets("nouveau dossier : la photo et la carte d'identité sont visibles, l'Admin approuve", (tester) async {
    final service = _AdminKycServiceEspion({
      'photoProfil': _photoCompressee(300, 400),
      'carteIdentite': _photoCompressee(400, 260),
    });
    await _ouvrirDossier(tester, service);

    await _defilerJusqua(tester, find.text("Carte d'identité"));
    expect(find.text('Photo du chauffeur'), findsOneWidget);
    expect(find.text("Carte d'identité"), findsOneWidget);
    expect(find.text('Non envoyé'), findsNothing, reason: 'les deux pièces sont là');
    expect(find.text('Plein écran'), findsNWidgets(2));
    expect(find.text('Carte grise'), findsNothing, reason: 'plus demandée');

    await _defilerJusqua(tester, find.text('Approuver le chauffeur'));
    expect(tester.widget<ButtonStyleButton>(_boutonApprouver()).onPressed, isNotNull);
    await tester.tap(find.text('Approuver le chauffeur'));
    await tester.pumpAndSettle();
    expect(service.approuves, ['chauffeur-1']);
  });

  testWidgets("ancien dossier (carte d'identité + carte grise, sans photo) : toujours visible et validable", (tester) async {
    final service = _AdminKycServiceEspion({
      'carteIdentite': _photoCompressee(400, 260),
      'carteGrise': _photoCompressee(400, 260),
    });
    await _ouvrirDossier(tester, service);

    await _defilerJusqua(tester, find.text('Carte grise'));
    expect(find.text('Carte grise'), findsOneWidget);
    expect(find.text('Non envoyé'), findsOneWidget, reason: 'la photo manque, elle est signalée');

    await _defilerJusqua(tester, find.text('Approuver le chauffeur'));
    await tester.tap(find.text('Approuver le chauffeur'));
    await tester.pumpAndSettle();
    expect(service.approuves, ['chauffeur-1']);
  });

  testWidgets("photo seule, sans carte d'identité : approbation impossible", (tester) async {
    final service = _AdminKycServiceEspion({'photoProfil': _photoCompressee(300, 400)});
    await _ouvrirDossier(tester, service);

    await _defilerJusqua(tester, find.text('Approuver le chauffeur'));
    expect(tester.widget<ButtonStyleButton>(_boutonApprouver()).onPressed, isNull);
  });
}
