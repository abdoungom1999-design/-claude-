import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sprint/core/maps/trace_utils.dart';

/// Encodeur « encoded polyline » de Google, pour fabriquer des tracés de test.
String _encoder(List<LatLng> points) {
  final tampon = StringBuffer();
  var derniereLat = 0;
  var derniereLng = 0;

  void ecrire(int valeur) {
    var v = valeur < 0 ? ~(valeur << 1) : valeur << 1;
    while (v >= 0x20) {
      tampon.writeCharCode((0x20 | (v & 0x1f)) + 63);
      v >>= 5;
    }
    tampon.writeCharCode(v + 63);
  }

  for (final p in points) {
    final lat = (p.latitude * 1e5).round();
    final lng = (p.longitude * 1e5).round();
    ecrire(lat - derniereLat);
    ecrire(lng - derniereLng);
    derniereLat = lat;
    derniereLng = lng;
  }
  return tampon.toString();
}

// Une rue d'ouest en est à Dakar : 0,01° de longitude ≈ 1,07 km.
const _ouest = LatLng(14.6900, -17.4600);
const _milieu = LatLng(14.6900, -17.4500);
const _est = LatLng(14.6900, -17.4400);

void main() {
  group('décodage « encoded polyline »', () {
    test('exemple de la documentation de Google', () {
      final points = TraceUtils.decoder(r'_p~iF~ps|U_ulLnnqC_mqNvxq`@');
      expect(points, hasLength(3));
      expect(points[0].latitude, closeTo(38.5, 1e-9));
      expect(points[0].longitude, closeTo(-120.2, 1e-9));
      expect(points[1].latitude, closeTo(40.7, 1e-9));
      expect(points[1].longitude, closeTo(-120.95, 1e-9));
      expect(points[2].latitude, closeTo(43.252, 1e-9));
      expect(points[2].longitude, closeTo(-126.453, 1e-9));
    });

    test('aller-retour avec des coordonnées de Dakar (précision 5 décimales)', () {
      const trace = [LatLng(14.69283, -17.44671), LatLng(14.69301, -17.44702), LatLng(14.7450, -17.5170)];
      final decode = TraceUtils.decoder(_encoder(trace));
      expect(decode, hasLength(trace.length));
      for (var i = 0; i < trace.length; i++) {
        expect(decode[i].latitude, closeTo(trace[i].latitude, 1e-9));
        expect(decode[i].longitude, closeTo(trace[i].longitude, 1e-9));
      }
    });

    test('tracé du serveur à Dakar : longitudes négatives, deltas des deux signes', () {
      // Réponse réelle de la fonction itineraireCourse sur l'émulateur : le décodage de ce texte
      // donnait « coordonnées hors du globe » sur le web (la PWA), pas sur la machine virtuelle.
      final points = TraceUtils.decoder('czsxAv}piB?gRmL??eRmL??me@');
      const attendus = [
        LatLng(14.6885, -17.459),
        LatLng(14.6885, -17.45592),
        LatLng(14.69065, -17.45592),
        LatLng(14.69065, -17.45285),
        LatLng(14.6928, -17.45285),
        LatLng(14.6928, -17.4467),
      ];
      expect(points, hasLength(attendus.length));
      for (var i = 0; i < attendus.length; i++) {
        expect(points[i].latitude, closeTo(attendus[i].latitude, 1e-9), reason: 'latitude $i');
        expect(points[i].longitude, closeTo(attendus[i].longitude, 1e-9), reason: 'longitude $i');
      }
    });

    test('aller-retour sur un maillage de Dakar, dans les deux sens (deltas négatifs et positifs)', () {
      final trace = [
        for (var i = 0; i < 40; i++) LatLng(14.60 + (i * 37 % 29) / 100, -17.55 + (i * 53 % 31) / 100),
      ];
      final decode = TraceUtils.decoder(_encoder(trace));
      expect(decode, hasLength(trace.length));
      for (var i = 0; i < trace.length; i++) {
        expect(decode[i].latitude, closeTo(trace[i].latitude, 1e-5), reason: 'latitude $i');
        expect(decode[i].longitude, closeTo(trace[i].longitude, 1e-5), reason: 'longitude $i');
      }
    });

    test('le décodeur n\'emploie aucun opérateur binaire : ils sont faux sur le web (32 bits, « ~ » non signé)', () {
      // Cette suite tourne sur la machine virtuelle, où les entiers font 64 bits : elle ne peut pas
      // voir ce défaut. On garde donc la cause hors du code (voir le commentaire de lireValeur).
      final source = File('lib/core/maps/trace_utils.dart')
          .readAsLinesSync()
          .where((ligne) => !ligne.trimLeft().startsWith('//'))
          .join('\n');
      final binaire = RegExp(r'<<|>>|\|=|&=|(?<![~/])~(?!/)|\s&\s|\s\|\s|\s\^\s');
      expect(binaire.allMatches(source).map((m) => m.group(0)).toList(), isEmpty);
    });

    test('texte vide : aucun point', () {
      expect(TraceUtils.decoder(''), isEmpty);
    });

    test('tracé tronqué, caractère invalide ou point hors du globe : FormatException', () {
      final valide = _encoder(const [_ouest, _est]);
      expect(() => TraceUtils.decoder(valide.substring(0, valide.length - 1)), throwsFormatException);
      expect(() => TraceUtils.decoder('\u0001\u0001'), throwsFormatException);
      expect(() => TraceUtils.decoder(_encoder(const [LatLng(95, 10)])), throwsFormatException);
    });
  });

  group('longueur et position sur le tracé', () {
    test('longueur : somme des segments', () {
      final deux = TraceUtils.longueurM(const [_ouest, _milieu]);
      expect(deux, closeTo(1075, 15));
      expect(TraceUtils.longueurM(const [_ouest, _milieu, _est]), closeTo(deux * 2, 1));
      expect(TraceUtils.longueurM(const [_ouest]), 0);
      expect(TraceUtils.longueurM(const []), 0);
    });

    test('sur le tracé : écart nul, reste = ce qui est devant', () {
      const trace = [_ouest, _milieu, _est];
      final p = TraceUtils.projeter(trace, _milieu)!;
      expect(p.ecartM, lessThan(1));
      expect(p.resteM, closeTo(TraceUtils.longueurM(const [_milieu, _est]), 1));
    });

    test('à côté du tracé : écart en mètres, reste mesuré depuis le point le plus proche', () {
      const trace = [_ouest, _milieu, _est];
      // ~55 m au nord de la rue, à mi-chemin du premier segment.
      const position = LatLng(14.6905, -17.4550);
      final p = TraceUtils.projeter(trace, position)!;
      expect(p.ecartM, closeTo(55, 3));
      expect(p.segment, 0);
      expect(p.point.latitude, closeTo(14.6900, 1e-6));
      expect(p.point.longitude, closeTo(-17.4550, 1e-5));
      expect(p.resteM, closeTo(TraceUtils.longueurM(const [LatLng(14.69, -17.455), _milieu, _est]), 2));
    });

    test('avant le début ou après la fin : ramené à l\'extrémité', () {
      const trace = [_ouest, _milieu, _est];
      final avant = TraceUtils.projeter(trace, const LatLng(14.6900, -17.4650))!;
      expect(avant.point.longitude, closeTo(_ouest.longitude, 1e-9));
      expect(avant.resteM, closeTo(TraceUtils.longueurM(trace), 1));

      final apres = TraceUtils.projeter(trace, const LatLng(14.6900, -17.4350))!;
      expect(apres.point.longitude, closeTo(_est.longitude, 1e-9));
      expect(apres.resteM, closeTo(0, 0.5));
      expect(apres.ecartM, closeTo(TraceUtils.distanceM(_est, const LatLng(14.6900, -17.4350)), 1));
    });

    test('route qui fait demi-tour : on ne se raccroche pas au tronçon d\'aller', () {
      // Aller vers l'est, demi-tour, retour vers l'ouest 30 m plus au nord.
      const aller = LatLng(14.6900, -17.4400);
      const retourEst = LatLng(14.6903, -17.4400);
      const retourOuest = LatLng(14.6903, -17.4600);
      const trace = [_ouest, aller, retourEst, retourOuest];
      const position = LatLng(14.6901, -17.4550); // entre les deux tronçons

      // Sans indication, le tronçon d'aller (11 m) est plus proche que celui du retour (22 m).
      expect(TraceUtils.projeter(trace, position)!.segment, 0);

      final apresLeDemiTour = TraceUtils.projeter(trace, position, depuisSegment: 2)!;
      expect(apresLeDemiTour.segment, 2);
      expect(apresLeDemiTour.ecartM, closeTo(22, 1));
      // Il ne reste que ~540 m vers l'ouest, pas tout l'aller et le demi-tour.
      expect(apresLeDemiTour.resteM, closeTo(TraceUtils.distanceM(const LatLng(14.6903, -17.4550), retourOuest), 2));
    });

    test('tracé vide ou réduit à un point', () {
      expect(TraceUtils.projeter(const [], _milieu), isNull);
      final seul = TraceUtils.projeter(const [_est], _milieu)!;
      expect(seul.resteM, 0);
      expect(seul.ecartM, closeTo(TraceUtils.distanceM(_milieu, _est), 1e-6));
    });

    test('ce qui reste du tracé : le point le plus proche puis les points suivants', () {
      const trace = [_ouest, _milieu, _est];
      final p = TraceUtils.projeter(trace, const LatLng(14.6901, -17.4550))!;
      final reste = TraceUtils.restant(trace, p);
      expect(reste, hasLength(3));
      expect(reste.first, p.point);
      expect(reste[1], _milieu);
      expect(reste[2], _est);
    });
  });
}
