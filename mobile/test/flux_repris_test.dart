import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/utils/flux_repris.dart';

/// Attente quasi nulle entre deux essais : on teste la logique, pas l'horloge.
Duration _vite(int _) => const Duration(milliseconds: 1);

Future<void> _laisserPasser([int ms = 60]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  test('un refus passager est invisible : le flux se rouvre et livre la donnée', () async {
    var ouvertures = 0;
    final recu = <int>[];
    final erreurs = <Object>[];
    final abonnement = fluxRepris<int>(() {
      ouvertures++;
      // Les deux premières ouvertures sont refusées, la troisième aboutit.
      return ouvertures < 3 ? Stream<int>.error('permission-denied') : Stream.value(42);
    }, delai: _vite)
        .listen(recu.add, onError: erreurs.add);
    await _laisserPasser();
    await abonnement.cancel();

    expect(ouvertures, 3);
    expect(recu, [42]);
    expect(erreurs, isEmpty);
  });

  test('refus persistant : l\'erreur remonte au 3e échec, et on continue d\'essayer', () async {
    var ouvertures = 0;
    final erreurs = <Object>[];
    final abonnement = fluxRepris<int>(() {
      ouvertures++;
      return Stream<int>.error('permission-denied');
    }, delai: _vite)
        .listen((_) {}, onError: erreurs.add);
    await _laisserPasser(100);
    await abonnement.cancel();

    expect(erreurs, isNotEmpty);
    // Jamais d'erreur avant le 3e échec ; jamais d'abandon ensuite.
    expect(ouvertures, greaterThan(3));
  });

  test('erreur transmise seulement à partir du 3e échec d\'affilée', () async {
    var ouvertures = 0;
    final erreurs = <int>[];
    final abonnement = fluxRepris<int>(() {
      ouvertures++;
      return Stream<int>.error('x');
    }, delai: (_) => const Duration(milliseconds: 30))
        .listen((_) {}, onError: (_) => erreurs.add(ouvertures));
    await _laisserPasser(45); // 2 échecs (t≈0 et t≈30) : rien encore
    expect(erreurs, isEmpty);
    await _laisserPasser(45); // 3e échec (t≈60)
    await abonnement.cancel();
    expect(erreurs.first, 3);
  });

  test('après une donnée, le compteur d\'échecs repart de zéro', () async {
    var ouvertures = 0;
    final erreurs = <Object>[];
    final recu = <int>[];
    final abonnement = fluxRepris<int>(() {
      ouvertures++;
      if (ouvertures <= 2) return Stream<int>.error('x');
      if (ouvertures == 3) {
        return () async* {
          yield 1;
          throw 'coupure';
        }();
      }
      return Stream.value(2);
    }, delai: _vite)
        .listen(recu.add, onError: erreurs.add);
    await _laisserPasser();
    await abonnement.cancel();

    expect(recu, [1, 2]);
    expect(erreurs, isEmpty);
  });

  test('annuler l\'écoute arrête toute relance', () async {
    var ouvertures = 0;
    final abonnement = fluxRepris<int>(() {
      ouvertures++;
      return Stream<int>.error('x');
    }, delai: _vite)
        .listen((_) {}, onError: (_) {});
    await _laisserPasser(20);
    await abonnement.cancel();
    final avant = ouvertures;
    await _laisserPasser(50);
    expect(ouvertures, avant);
  });

  test('délais : 1 s, 2 s, 4 s puis 8 s', () {
    expect([1, 2, 3, 4, 5].map((n) => delaiRelance(n).inSeconds), [1, 2, 4, 8, 8]);
  });
}
