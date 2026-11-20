
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
  required Future<Uint8List?> Function(BuildContext, String) choisir,
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

  group('envoi de secours (image encodée) : borné par ce que les règles Firestore savent évaluer', () {
    test('tailleBase64 : 4 caractères pour 3 octets, arrondi vers le haut', () {
      expect([0, 1, 2, 3, 4, 6, 7].map(tailleBase64), [0, 4, 4, 4, 8, 8, 12]);
      expect(tailleBase64(180 * 1024), 245760);
    });

    test('repli permis pour une photo de 180 Ko au plus, jamais pour une photo plus lourde ni pour un PDF', () {
      expect(repliBase64Possible(TypePiece.jpeg, 180 * 1024), isTrue);
      expect(repliBase64Possible(TypePiece.png, 50 * 1024), isTrue);
      expect(repliBase64Possible(TypePiece.webp, 1), isTrue);
      expect(repliBase64Possible(TypePiece.jpeg, 180 * 1024 + 1), isFalse);
      // La photo de 700 Ko qui passait avant faisait refuser la deuxième pièce par Firestore.
      expect(repliBase64Possible(TypePiece.jpeg, 700 * 1024), isFalse);
      expect(repliBase64Possible(TypePiece.pdf, 10 * 1024), isFalse);
      expect(ConducteurDocumentsService.limiteOctetsBase64, limiteOctetsRepliBase64);
    });

    test('quatre pièces de secours au plafond tiennent sous la capacité des règles (mesurée : environ 1 000 000 de caractères)', () {
      const prefixe = 'data:image/jpeg;base64,';
      final unePiece = prefixe.length + tailleBase64(limiteOctetsRepliBase64);
      expect(capaciteReglesBase64Caracteres, 1000000);
      expect(unePiece * 4, lessThanOrEqualTo(capaciteReglesBase64Caracteres));
      // Et l'ancien plafond (700 Ko) ne tenait que pour UNE pièce.
      final ancien = prefixe.length + tailleBase64(700 * 1024);
      expect(ancien * 2, greaterThan(capaciteReglesBase64Caracteres));
    });

    test('après un repli, le code d\'échec Firestore garde la cause de l\'échec de Storage', () {
      expect(codeEchecFirestore('permission-denied'), 'firestore/permission-denied');
      expect(
        codeEchecFirestore('permission-denied', codeStockage: 'storage/unauthorized'),
        'firestore/permission-denied, repli après storage/unauthorized',
      );
      final message = messageErreurEnvoi(
        EchecEnvoiPieceException(codeEchecFirestore('permission-denied', codeStockage: 'storage/retry-limit-exceeded')),
      );
      expect(message, contains('firestore/permission-denied'));
      expect(message, contains('storage/retry-limit-exceeded'));
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
    testWidgets('envoi réussi : la photo puis la carte d\'identité partent sous la bonne clé, avec l\'identifiant du compte', (tester) async {
      final service = _ServiceFactice();
      final demandes = <String>[];
      await _ouvrir(tester, choisir: (_, cle) async {
        demandes.add(cle);
        return _jpeg;
      }, service: service);

      await tester.tap(find.text('Photo'));
      await tester.pump();
      await tester.tap(find.text("Carte d'identité"));
      await tester.pump();

      expect(demandes, ['photoProfil', 'carteIdentite'], reason: 'le sélecteur sait quelle pièce est demandée (pas de PDF pour la photo)');
      expect([for (final e in service.envois) (e.$1, e.$2)], [('chauffeur-1', 'photoProfil'), ('chauffeur-1', 'carteIdentite')]);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('annulation du choix : rien n\'est envoyé, aucun message', (tester) async {
      final service = _ServiceFactice();
      await _ouvrir(tester, choisir: (_, __) async => null, service: service);

      await tester.tap(find.text("Carte d'identité"));
      await tester.pump();

      expect(service.envois, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('échec technique : le code exact est affiché (plus de « Échec de l\'envoi. Réessayez. » muet)', (tester) async {
      final service = _ServiceFactice(erreur: const EchecEnvoiPieceException('storage/unauthorized'));
      await _ouvrir(tester, choisir: (_, __) async => _png, service: service);

      await tester.tap(find.text('Photo'));
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
        await _ouvrir(tester, choisir: (_, __) async => _pdf, service: _ServiceFactice(erreur: erreur));
        await tester.tap(find.text('Photo'));
        await tester.pump();
        expect(find.textContaining(attendu), findsOneWidget);
        expect(find.textContaining('code :'), findsNothing);
      });
    }

    testWidgets('le sélecteur lui-même échoue (ex. accès appareil photo refusé) : le code est dit', (tester) async {
      final service = _ServiceFactice();
      await _ouvrir(
        tester,
        choisir: (_, __) async => throw PlatformException(code: 'camera_access_denied'),
        service: service,
      );

      await tester.tap(find.text("Carte d'identité"));
      await tester.pump();

      expect(find.textContaining('selection/camera_access_denied'), findsOneWidget);
      expect(service.envois, isEmpty);
    });
  });
}
