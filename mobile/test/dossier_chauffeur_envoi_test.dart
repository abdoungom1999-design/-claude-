
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/features/conducteur/data/conducteur_documents_service.dart';
import 'package:sprint/features/conducteur/data/piece_kyc.dart';
import 'package:sprint/features/conducteur/presentation/conducteur_kyc_page.dart';

Uint8List _octets(List<int> debut, [int total = 64]) {
  final o = Uint8List(total);
  for (var i = 0; i < debut.length; i++) {
    o[i] = debut[i];
  }
  return o;
}

final _jpeg = _octets([0xFF, 0xD8, 0xFF, 0xE0]);
final _png = _octets([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
final _webp = _octets([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50]);
final _pdf = _octets([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34]);
// « ....ftypheic » : photo HEIC brute d'un iPhone.
final _heic = _octets([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63]);

/// Faux envoi : aucun accès Firebase, tout est piloté par le test.
class _ServiceFactice extends ConducteurDocumentsService {
  _ServiceFactice({this.erreur});

  final Object? erreur;
  final envois = <(String uid, String cle, Uint8List octets)>[];

  @override
  Future<void> televerserDocument({required String uid, required String cle, required Uint8List octets}) async {
    envois.add((uid, cle, octets));
    if (erreur case final e?) throw e;
  }
}

Future<void> _ouvrir(
  WidgetTester tester, {
  required Future<Uint8List?> Function(BuildContext) choisir,
  required _ServiceFactice service,
  Map<String, dynamic> documents = const {},
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: ConducteurKYCPage(
      onDossierSoumis: () {},
      onDeconnexion: () {},
      fluxProfil: Stream.value({'documents': documents}),
      choisirPiece: choisir,
      service: service,
      uid: 'chauffeur-1',
    ),
  ));
  await tester.pump();
}

void main() {
  group('type réel d\'une pièce (jamais d\'après le nom ni le type annoncé)', () {
    test('JPEG, PNG, WebP et PDF sont reconnus', () {
      expect(detecterTypePiece(_jpeg), TypePiece.jpeg);
      expect(detecterTypePiece(_png), TypePiece.png);
      expect(detecterTypePiece(_webp), TypePiece.webp);
      expect(detecterTypePiece(_pdf), TypePiece.pdf);
    });

    test('type annoncé à Storage : exact pour chaque format ; seul le PDF n\'est pas une image', () {
      expect(TypePiece.jpeg.contentType, 'image/jpeg');
      expect(TypePiece.png.contentType, 'image/png');
      expect(TypePiece.webp.contentType, 'image/webp');
      expect(TypePiece.pdf.contentType, 'application/pdf');
      expect([for (final t in TypePiece.values) t.estImage], [true, true, true, false]);
    });

    test('HEIC, texte, vide et fichier tronqué : non reconnus', () {
      expect(detecterTypePiece(_heic), isNull);
      expect(estPieceHeic(_heic), isTrue);
      expect(estPieceHeic(_jpeg), isFalse);
      expect(detecterTypePiece(Uint8List.fromList('bonjour'.codeUnits)), isNull);
      expect(detecterTypePiece(Uint8List(0)), isNull);
      expect(detecterTypePiece(Uint8List.fromList([0xFF, 0xD8])), isNull);
      expect(estPieceHeic(Uint8List.fromList([0, 0, 0])), isFalse);
    });
  });

  group('messages d\'erreur : la cause n\'est jamais cachée', () {
    test('taille, format, HEIC, code précis, erreur inconnue', () {
      expect(messageErreurEnvoi(const DocumentTropVolumineuxException()), contains('10 Mo'));
      expect(messageErreurEnvoi(const FormatPieceNonSupporteException()), contains('PDF'));
      expect(messageErreurEnvoi(const FormatPieceNonSupporteException(heic: true)), contains('HEIC'));
      expect(messageErreurEnvoi(const EchecEnvoiPieceException('storage/unauthorized')), contains('storage/unauthorized'));
      expect(messageErreurEnvoi(StateError('x')), contains('StateError'));
      expect(messageErreurEnvoi(StateError('x')), isNot(equals("Échec de l'envoi. Réessayez.")));
    });
  });

  group('page « Complétez votre dossier » : envoi d\'une pièce', () {
    testWidgets('envoi réussi : la pièce part sous la bonne clé, avec l\'identifiant du compte', (tester) async {
      final service = _ServiceFactice();
      await _ouvrir(tester, choisir: (_) async => _jpeg, service: service);

      await tester.tap(find.text("Carte d'identité"));
      await tester.pump();
      await tester.tap(find.text('Carte grise'));
      await tester.pump();

      expect([for (final e in service.envois) (e.$1, e.$2)], [('chauffeur-1', 'carteIdentite'), ('chauffeur-1', 'carteGrise')]);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('annulation du choix : rien n\'est envoyé, aucun message', (tester) async {
      final service = _ServiceFactice();
      await _ouvrir(tester, choisir: (_) async => null, service: service);

      await tester.tap(find.text("Carte d'identité"));
      await tester.pump();

      expect(service.envois, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('échec technique : le code exact est affiché (plus de « Échec de l\'envoi. Réessayez. » muet)', (tester) async {
      final service = _ServiceFactice(erreur: const EchecEnvoiPieceException('storage/unauthorized'));
      await _ouvrir(tester, choisir: (_) async => _png, service: service);

      await tester.tap(find.text('Carte grise'));
      await tester.pump();

      expect(find.textContaining('storage/unauthorized'), findsOneWidget);
      // Le bouton « Ajouter » est de nouveau disponible : on peut réessayer.
      expect(find.text('Ajouter'), findsNWidgets(2));
    });

    for (final (nom, erreur, attendu) in [
      ('fichier trop lourd', const DocumentTropVolumineuxException() as Object, '10 Mo'),
      ('format non pris en charge', const FormatPieceNonSupporteException() as Object, 'Format non pris en charge'),
      ('photo HEIC brute', const FormatPieceNonSupporteException(heic: true) as Object, 'HEIC'),
    ]) {
      testWidgets('$nom : un message clair, sans code technique inutile', (tester) async {
        await _ouvrir(tester, choisir: (_) async => _pdf, service: _ServiceFactice(erreur: erreur));
        await tester.tap(find.text('Carte grise'));
        await tester.pump();
        expect(find.textContaining(attendu), findsOneWidget);
        expect(find.textContaining('code :'), findsNothing);
      });
    }

    testWidgets('le sélecteur lui-même échoue (ex. accès appareil photo refusé) : le code est dit', (tester) async {
      final service = _ServiceFactice();
      await _ouvrir(
        tester,
        choisir: (_) async => throw PlatformException(code: 'camera_access_denied'),
        service: service,
      );

      await tester.tap(find.text("Carte d'identité"));
      await tester.pump();

      expect(find.textContaining('selection/camera_access_denied'), findsOneWidget);
      expect(service.envois, isEmpty);
    });
  });
}
