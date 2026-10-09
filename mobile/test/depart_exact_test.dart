import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/features/courses/data/course_service.dart';
import 'package:sprint/features/courses/data/depart_exact.dart';

// Le client est au Plateau ; le document de la course n'en garde que le centre de sa case de ~150 m.
const _arrondi = PointsCourse(
  latitudeDepart: 14.69273,
  longitudeDepart: -17.44582,
  latitudeArrivee: 14.7450,
  longitudeArrivee: -17.5170,
);
const _exact = DepartExact(latitude: 14.69281, longitude: -17.44673);

CourseFirestore _course({
  String id = 'c1',
  String statut = StatutCourse.acceptee,
  bool arrondi = true,
  PointsCourse? points = _arrondi,
}) =>
    CourseFirestore(
      id: id,
      clientId: 'awa',
      chauffeurId: 'moussa',
      statut: statut,
      type: 'PASSAGER',
      adresseDepart: 'Position GPS du client',
      adresseArrivee: 'Almadies',
      prixFcfa: 3000,
      methodePaiement: 'WAVE',
      timestamp: DateTime(2026, 10, 9, 12),
      points: points,
      departArrondi: arrondi,
      commandeId: 'k1',
    );

/// Flux des courses et des positions exactes contrôlés par le test.
class _Banc {
  final courses = StreamController<CourseFirestore?>();
  final exactes = <String, StreamController<DepartExact?>>{};
  final ouvertes = <String>[];
  final abandonnees = <String>[];

  Stream<DepartExact?> ouvrir(String id) {
    ouvertes.add(id);
    final flux = StreamController<DepartExact?>(onCancel: () => abandonnees.add(id));
    exactes[id] = flux;
    return flux.stream;
  }

  late final Stream<CourseFirestore?> sortie = completerDepartExact(courses.stream, ouvrir);
  final recues = <CourseFirestore?>[];
  final erreurs = <Object>[];
  late StreamSubscription<CourseFirestore?> abonnement;

  void ecouter() {
    abonnement = sortie.listen(recues.add, onError: erreurs.add);
  }

  Future<void> envoyer(CourseFirestore? course) async {
    courses.add(course);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> recevoirExacte(String id, DepartExact? valeur) async {
    exactes[id]!.add(valeur);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> fermer() async {
    await abonnement.cancel();
    await courses.close();
    for (final flux in exactes.values) {
      await flux.close();
    }
  }
}

void main() {
  late _Banc banc;

  setUp(() {
    banc = _Banc()..ecouter();
  });
  tearDown(() => banc.fermer());

  group('course dont le départ est arrondi', () {
    test('émise tout de suite, puis complétée par la position exacte dès qu\'elle arrive', () async {
      await banc.envoyer(_course());

      expect(banc.recues, hasLength(1));
      expect(banc.recues.single!.departArrondi, isTrue);
      expect(banc.recues.single!.points!.latitudeDepart, _arrondi.latitudeDepart);
      expect(banc.ouvertes, ['c1']);

      await banc.recevoirExacte('c1', _exact);

      expect(banc.recues, hasLength(2));
      final complete = banc.recues.last!;
      expect(complete.departArrondi, isFalse);
      expect(complete.points!.latitudeDepart, _exact.latitude);
      expect(complete.points!.longitudeDepart, _exact.longitude);
      // L'arrivée et tout le reste de la course sont intacts.
      expect(complete.points!.latitudeArrivee, _arrondi.latitudeArrivee);
      expect(complete.points!.longitudeArrivee, _arrondi.longitudeArrivee);
      expect(complete.id, 'c1');
      expect(complete.clientId, 'awa');
      expect(complete.chauffeurId, 'moussa');
      expect(complete.statut, StatutCourse.acceptee);
      expect(complete.adresseDepart, 'Position GPS du client');
      expect(complete.adresseArrivee, 'Almadies');
      expect(complete.prixFcfa, 3000);
      expect(complete.commandeId, 'k1');
      expect(complete.timestamp, DateTime(2026, 10, 9, 12));
    });

    test('nouvelle version de la même course : la position exacte déjà reçue est reprise, sans la redemander',
        () async {
      await banc.envoyer(_course());
      await banc.recevoirExacte('c1', _exact);

      await banc.envoyer(_course(statut: StatutCourse.enCours));

      expect(banc.recues.last!.statut, StatutCourse.enCours);
      expect(banc.recues.last!.points!.latitudeDepart, _exact.latitude);
      expect(banc.recues.last!.departArrondi, isFalse);
      expect(banc.ouvertes, ['c1'], reason: 'une seule lecture pour toute la course');
      expect(banc.abandonnees, isEmpty);
    });

    test('une autre course : la lecture de la précédente est abandonnée et sa position n\'est jamais reprise',
        () async {
      await banc.envoyer(_course());
      await banc.recevoirExacte('c1', _exact);

      await banc.envoyer(_course(id: 'c2'));

      expect(banc.abandonnees, ['c1']);
      expect(banc.ouvertes, ['c1', 'c2']);
      expect(banc.recues.last!.id, 'c2');
      expect(banc.recues.last!.departArrondi, isTrue, reason: 'pas la position du client de la course précédente');
      expect(banc.recues.last!.points!.latitudeDepart, _arrondi.latitudeDepart);
    });

    test('course terminée, annulée ou disparue : plus de lecture de la position exacte', () async {
      for (final fin in <CourseFirestore?>[
        _course(statut: StatutCourse.terminee),
        _course(statut: StatutCourse.annulee),
        null,
      ]) {
        banc.ouvertes.clear();
        banc.abandonnees.clear();
        await banc.envoyer(_course());
        expect(banc.ouvertes, ['c1']);

        await banc.envoyer(fin);

        expect(banc.abandonnees, ['c1'], reason: 'fin : ${fin?.statut}');
        expect(banc.recues.last, same(fin));
      }
    });

    test('lecture en erreur ou position absente : la course reste utilisable avec son départ arrondi', () async {
      await banc.envoyer(_course());

      banc.exactes['c1']!.addError(StateError('permission-denied'));
      await Future<void>.delayed(Duration.zero);
      await banc.recevoirExacte('c1', null);

      expect(banc.erreurs, isEmpty, reason: 'la lecture se retente toute seule, sans déranger l\'écran');
      expect(banc.recues.last!.departArrondi, isTrue);
      expect(banc.recues.last!.points!.latitudeDepart, _arrondi.latitudeDepart);

      // La position finit par arriver.
      await banc.recevoirExacte('c1', _exact);
      expect(banc.recues.last!.departArrondi, isFalse);
      expect(banc.recues.last!.points!.latitudeDepart, _exact.latitude);
    });

    test('course sans coordonnées : rien à compléter, aucune erreur', () async {
      await banc.envoyer(_course(points: null));
      await banc.recevoirExacte('c1', _exact);

      expect(banc.recues.last!.points, isNull);
      expect(banc.erreurs, isEmpty);
    });
  });

  test('course d\'avant le masquage (départ exact dans la course) : transmise telle quelle, rien n\'est demandé',
      () async {
    final ancienne = _course(arrondi: false);
    await banc.envoyer(ancienne);

    expect(banc.recues.single, same(ancienne));
    expect(banc.ouvertes, isEmpty);
  });

  test('course encore en attente d\'un chauffeur (vue du client) : sa position exacte est lue aussi', () async {
    await banc.envoyer(_course(statut: StatutCourse.enAttente));
    await banc.recevoirExacte('c1', _exact);

    expect(banc.recues.last!.statut, StatutCourse.enAttente);
    expect(banc.recues.last!.points!.latitudeDepart, _exact.latitude);
  });

  test('erreur du flux des courses : transmise telle quelle', () async {
    banc.courses.addError(StateError('hors ligne'));
    await Future<void>.delayed(Duration.zero);

    expect(banc.erreurs.single, isA<StateError>());
  });

  test('flux des courses terminé : le flux se termine et la lecture est abandonnée', () async {
    final fini = Completer<void>();
    banc.abonnement.onDone(fini.complete);
    await banc.envoyer(_course());

    await banc.courses.close();
    await fini.future.timeout(const Duration(seconds: 2));

    expect(banc.abandonnees, ['c1']);
  });

  test('abonnement annulé : les deux lectures sont arrêtées', () async {
    var coursesAnnulees = false;
    final courses = StreamController<CourseFirestore?>(onCancel: () => coursesAnnulees = true);
    final abandonnees = <String>[];
    final exactes = StreamController<DepartExact?>(onCancel: () => abandonnees.add('c1'));
    final abonnement = completerDepartExact(courses.stream, (_) => exactes.stream).listen((_) {});
    courses.add(_course());
    await Future<void>.delayed(Duration.zero);

    await abonnement.cancel();

    expect(coursesAnnulees, isTrue);
    expect(abandonnees, ['c1']);
  });

  group('lecture du document', () {
    test('la course lit departArrondi', () {
      CourseFirestore lire(Map<String, dynamic> extra) => CourseFirestore.depuisDocument('c1', {
            'clientId': 'awa',
            'statut': 'en_attente',
            'latitudeDepart': 14.69273,
            'longitudeDepart': -17.44582,
            'latitudeArrivee': 14.7450,
            'longitudeArrivee': -17.5170,
            ...extra,
          });

      expect(lire({'departArrondi': true}).departArrondi, isTrue);
      expect(lire({'departArrondi': false}).departArrondi, isFalse);
      expect(lire({}).departArrondi, isFalse, reason: 'course d\'avant le masquage');
      expect(lire({'departArrondi': 'oui'}).departArrondi, isFalse, reason: 'seul « true » compte');
    });

    test('la position exacte demande une latitude et une longitude', () {
      expect(DepartExact.depuisDocument({'latitude': 14.69281, 'longitude': -17.44673})!.latitude, 14.69281);
      expect(DepartExact.depuisDocument({'latitude': 14, 'longitude': -17})!.longitude, -17.0);
      expect(DepartExact.depuisDocument(null), isNull);
      expect(DepartExact.depuisDocument({}), isNull);
      expect(DepartExact.depuisDocument({'latitude': 'x', 'longitude': 1}), isNull);
      expect(DepartExact.depuisDocument({'latitude': 1.0}), isNull);
    });
  });
}
