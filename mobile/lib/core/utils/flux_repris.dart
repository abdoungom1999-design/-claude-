import 'dart:async';

/// Écoute un flux qui peut être refusé ou coupé passagèrement (règles
/// Firestore pas encore satisfaites, réseau qui saute) et le relance
/// tout seul, au lieu de rester bloqué sur la première erreur.
///
/// Les erreurs ne sont transmises qu'à partir de [echecsAvantErreur]
/// échecs d'affilée : un refus d'une fraction de seconde au moment où la
/// course est acceptée reste invisible. La relance continue ensuite, et la
/// prochaine donnée reçue remet tout à zéro.
Stream<T> fluxRepris<T>(
  Stream<T> Function() ouvrir, {
  int echecsAvantErreur = 3,
  Duration Function(int echecs)? delai,
}) {
  final attente = delai ?? delaiRelance;
  late final StreamController<T> sortie;
  StreamSubscription<T>? abonnement;
  Timer? minuteur;
  var echecs = 0;

  void souscrire() {
    abonnement = ouvrir().listen(
      (valeur) {
        echecs = 0;
        sortie.add(valeur);
      },
      onError: (Object erreur, StackTrace pile) {
        echecs++;
        if (echecs >= echecsAvantErreur) sortie.addError(erreur, pile);
        abonnement?.cancel();
        minuteur = Timer(attente(echecs), () {
          if (!sortie.isClosed) souscrire();
        });
      },
      cancelOnError: true,
    );
  }

  sortie = StreamController<T>(
    onListen: souscrire,
    onPause: () => abonnement?.pause(),
    onResume: () => abonnement?.resume(),
    onCancel: () async {
      minuteur?.cancel();
      await abonnement?.cancel();
    },
  );
  return sortie.stream;
}

/// 1 s, 2 s, 4 s, puis toutes les 8 s.
Duration delaiRelance(int echecs) => Duration(seconds: echecs >= 4 ? 8 : 1 << (echecs - 1));
