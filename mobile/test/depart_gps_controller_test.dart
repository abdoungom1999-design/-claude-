import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sprint/core/maps/geocoding_service.dart';
import 'package:sprint/features/client/presentation/depart_gps_controller.dart';
import 'package:sprint/features/client/presentation/widgets/depart_gps_etat.dart';
import 'package:sprint/features/courses/data/course_service.dart';
import 'package:sprint/features/courses/data/estimation_course_controller.dart';
import 'package:sprint/features/courses/data/pricing_repository.dart';

const _moi = LatLng(14.701234, -17.456789);

final _plateau = AdresseSuggestion(libelle: 'Plateau, Dakar', latitude: 14.6680, longitude: -17.4380);

class _Tarification extends PricingRepository {
  _Tarification() : super(dio: Dio());

  @override
  Future<EstimationPrix> estimer({required String type, required double distanceKm, PointsCourse? trajet}) async =>
      EstimationPrix(distanceKm: distanceKm, dureeEstimeeMin: 20, multiplicateurTrafic: 1, prixFcfa: 1500);
}

void main() {
  late EstimationCourseController estimation;
  late TextEditingController texte;
  late DepartGpsController gps;
  late List<Completer<LatLng?>> reponses;
  late List<bool> demandes;

  setUp(() {
    estimation = EstimationCourseController(type: 'COLIS', pricingRepository: _Tarification());
    texte = TextEditingController();
    reponses = [];
    demandes = [];
    gps = DepartGpsController(
      estimation: estimation,
      texte: texte,
      localiser: ({required bool demander}) {
        demandes.add(demander);
        final reponse = Completer<LatLng?>();
        reponses.add(reponse);
        return reponse.future;
      },
    );
  });

  tearDown(() {
    gps.dispose();
    texte.dispose();
    estimation.dispose();
  });

  test('en attente de la position : « recherche », rien n\'est choisi', () {
    gps.chercherPosition();
    expect(gps.etat, EtatDepartGps.recherche);
    expect(demandes, [true], reason: 'avec la demande d\'autorisation');
    expect(estimation.depart, isNull);
    expect(texte.text, isEmpty);
  });

  test('position trouvée : « Ma position actuelle », coordonnées exactes, départ GPS', () async {
    final fin = gps.chercherPosition();
    reponses.single.complete(_moi);
    await fin;

    expect(gps.etat, EtatDepartGps.actif);
    expect(texte.text, 'Ma position actuelle');
    expect(estimation.depart!.gps, isTrue);
    expect(estimation.depart!.latitude, 14.701234);
    expect(estimation.depart!.longitude, -17.456789);
  });

  test('position introuvable : « indisponible », le champ reste vide ; réessayer reprend la recherche', () async {
    var fin = gps.chercherPosition();
    reponses.single.complete(null);
    await fin;
    expect(gps.etat, EtatDepartGps.indisponible);
    expect(texte.text, isEmpty);
    expect(estimation.depart, isNull);

    final version = gps.versionChamp;
    fin = gps.chercherPosition();
    expect(gps.etat, EtatDepartGps.recherche);
    expect(gps.versionChamp, version + 1, reason: 'le champ est reconstruit : ses suggestions disparaissent');
    reponses.last.complete(_moi);
    await fin;
    expect(gps.etat, EtatDepartGps.actif);
    expect(demandes, [true, true]);
  });

  test('adresse choisie dans la liste : elle remplace le GPS ; une position tardive est ignorée', () async {
    final fin = gps.chercherPosition();
    gps.departChoisi(_plateau);
    reponses.single.complete(_moi);
    await fin;

    expect(gps.etat, EtatDepartGps.manuel);
    expect(estimation.depart!.libelle, 'Plateau, Dakar');
    expect(estimation.depart!.gps, isFalse);
    expect(texte.text, isEmpty, reason: 'la position tardive n\'a rien écrit');
  });

  test('texte retouché : le point GPS est oublié, une position tardive est ignorée', () async {
    var fin = gps.chercherPosition();
    reponses.single.complete(_moi);
    await fin;
    expect(estimation.depart, isNotNull);

    gps.departModifie();
    expect(gps.etat, EtatDepartGps.manuel);
    expect(estimation.depart, isNull);

    // « Utiliser ma position actuelle » : nouvelle recherche, qui reprend le GPS.
    fin = gps.chercherPosition();
    gps.departModifie(); // le client retape avant la réponse
    reponses.last.complete(_moi);
    await fin;
    expect(gps.etat, EtatDepartGps.manuel);
    expect(estimation.depart, isNull);
  });

  test('toucher le champ sélectionne « Ma position actuelle » seulement quand le départ est le GPS', () async {
    texte.text = 'Plateau';
    gps.departTouche();
    expect(texte.selection.isCollapsed, isTrue, reason: 'pas de GPS : le toucher ne sélectionne rien');

    final fin = gps.chercherPosition();
    reponses.single.complete(_moi);
    await fin;
    gps.departTouche();
    expect(texte.selection, const TextSelection(baseOffset: 0, extentOffset: 20));
  });

  test('écran fermé pendant la recherche : la réponse ne touche plus à rien', () async {
    final fin = gps.chercherPosition();
    gps.dispose();
    reponses.single.complete(_moi);
    await fin;

    expect(texte.text, isEmpty);
    expect(estimation.depart, isNull);
    // tearDown rappelle dispose : ChangeNotifier l'accepte tant qu'on ne notifie plus.
    gps =
        DepartGpsController(estimation: estimation, texte: texte, localiser: ({required bool demander}) async => null);
  });
}
