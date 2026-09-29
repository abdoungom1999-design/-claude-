import 'dart:async';

/// Partage un flux (ex. `snapshots()` Firestore, qui n'accepte qu'un seul
/// abonné) entre plusieurs widgets : chaque nouvel abonné reçoit
/// aussitôt la dernière valeur, puis les suivantes. La source n'est
/// écoutée qu'une fois ; [fermer] l'arrête.
class FluxPartage<T> {
  FluxPartage(Stream<T> source) {
    _abonnement = source.listen(
      (valeur) {
        _dernier = valeur;
        _aValeur = true;
        for (final c in [..._abonnes]) {
          c.add(valeur);
        }
      },
      onError: (Object e, StackTrace pile) {
        for (final c in [..._abonnes]) {
          c.addError(e, pile);
        }
      },
    );
  }

  late final StreamSubscription<T> _abonnement;
  final _abonnes = <MultiStreamController<T>>{};
  T? _dernier;
  bool _aValeur = false;

  Stream<T> get flux => Stream.multi((controleur) {
        if (_aValeur) controleur.add(_dernier as T);
        _abonnes.add(controleur);
        controleur.onCancel = () => _abonnes.remove(controleur);
      });

  Future<void> fermer() => _abonnement.cancel();
}
