import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/features/conducteur/data/rayon_alertes.dart';
import 'package:sprint/features/courses/data/course_service.dart';
import 'package:sprint/features/courses/data/position_chauffeur.dart';

const _plateau = (latitude: 14.6928, longitude: -17.4467);
const _almadies = (latitude: 14.7456, longitude: -17.5134);
const _thies = (latitude: 14.7910, longitude: -16.9359);
const _mbour = (latitude: 14.4196, longitude: -16.9640);

final _maintenant = DateTime.utc(2026, 10, 12, 12);

CourseFirestore _course(({double latitude, double longitude})? depart) => CourseFirestore(
      id: 'c1',
      clientId: 'awa',
      chauffeurId: null,
      statut: 'en_attente',
      type: 'PASSAGER',
      adresseDepart: 'Départ',
      adresseArrivee: 'Arrivée',
      prixFcfa: 2300,
      methodePaiement: 'WAVE',
      timestamp: _maintenant,
      points: depart == null
          ? null
          : PointsCourse(
              latitudeDepart: depart.latitude,
              longitudeDepart: depart.longitude,
              latitudeArrivee: depart.latitude + 0.01,
              longitudeArrivee: depart.longitude,
            ),
    );

PositionChauffeurDirect _position(({double latitude, double longitude}) lieu, {Duration age = const Duration(minutes: 1)}) =>
    PositionChauffeurDirect(
      uid: 'moussa',
      latitude: lieu.latitude,
      longitude: lieu.longitude,
      majLe: _maintenant.subtract(age),
    );

bool _proposer(CourseFirestore course, PositionChauffeurDirect? position) =>
    RayonAlertes.proposer(course, position, maintenant: _maintenant);

void main() {
  group('Alertes aux chauffeurs : à moins de 30 km du départ', () {
    test('le rayon est de 30 km', () {
      expect(RayonAlertes.rayonKm, 30);
      expect(RayonAlertes.fraicheurPosition, const Duration(minutes: 30));
    });

    test('une course à Dakar est proposée aux chauffeurs de Dakar, pas à ceux de Thiès ni de Mbour', () {
      final course = _course(_plateau);
      expect(_proposer(course, _position(_almadies)), isTrue);
      expect(_proposer(course, _position(_thies)), isFalse);
      expect(_proposer(course, _position(_mbour)), isFalse);
    });

    test('une course à Thiès est proposée au chauffeur de Thiès, pas à celui de Dakar', () {
      final course = _course(_thies);
      expect(_proposer(course, _position(_thies)), isTrue);
      expect(_proposer(course, _position(_plateau)), isFalse);
    });

    test('position inconnue, trop ancienne ou sans heure : proposée comme avant', () {
      final course = _course(_plateau);
      expect(_proposer(course, null), isTrue);
      expect(_proposer(course, _position(_thies, age: RayonAlertes.fraicheurPosition + const Duration(minutes: 1))), isTrue);
      expect(
        _proposer(course, const PositionChauffeurDirect(uid: 'moussa', latitude: 14.791, longitude: -16.9359, majLe: null)),
        isTrue,
      );
      // Juste à la limite de fraîcheur, la position compte encore.
      expect(_proposer(course, _position(_thies, age: RayonAlertes.fraicheurPosition)), isFalse);
    });

    test('course sans coordonnées (ancienne) : proposée comme avant', () {
      expect(_proposer(_course(null), _position(_thies)), isTrue);
    });

    test('la limite exacte est 30 km : 29,9 km proposée, 30,1 km non', () {
      final course = _course(_plateau);
      ({double latitude, double longitude}) auNord(double km) =>
          (latitude: _plateau.latitude + km / 111.195, longitude: _plateau.longitude);
      expect(_proposer(course, _position(auNord(29.9))), isTrue);
      expect(_proposer(course, _position(auNord(30.1))), isFalse);
    });
  });
}
