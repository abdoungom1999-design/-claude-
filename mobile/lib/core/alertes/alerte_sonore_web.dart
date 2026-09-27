import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('AudioContext')
external JSFunction? get _audioContext;

@JS('webkitAudioContext')
external JSFunction? get _webkitAudioContext;

@JS('navigator')
external JSObject get _navigator;

extension type _Contexte._(JSObject _) implements JSObject {
  external String get state;
  external JSPromise<JSAny?> resume();
  external double get currentTime;
  external JSObject get destination;
  external _Oscillateur createOscillator();
  external _Gain createGain();
}

extension type _Parametre._(JSObject _) implements JSObject {
  external void setValueAtTime(double valeur, double instant);
  external void linearRampToValueAtTime(double valeur, double instant);
}

extension type _Oscillateur._(JSObject _) implements JSObject {
  external set type(String type);
  external _Parametre get frequency;
  external void connect(JSObject destination);
  external void start(double instant);
  external void stop(double instant);
}

extension type _Gain._(JSObject _) implements JSObject {
  external _Parametre get gain;
  external void connect(JSObject destination);
}

_Contexte? _contexte;

_Contexte? _obtenirContexte() {
  if (_contexte != null) return _contexte;
  final constructeur = _audioContext ?? _webkitAudioContext;
  if (constructeur == null) return null;
  try {
    return _contexte = constructeur.callAsConstructor<_Contexte>();
  } catch (_) {
    return null;
  }
}

void preparer() {
  final contexte = _obtenirContexte();
  if (contexte != null && contexte.state == 'suspended') {
    contexte.resume().toDart.catchError((_) => null);
  }
}

void nouvelleCourse() {
  _vibrer();
  final contexte = _obtenirContexte();
  if (contexte == null) return;
  if (contexte.state == 'suspended') contexte.resume().toDart.catchError((_) => null);
  try {
    final debut = contexte.currentTime + 0.02;
    // Trois bips montants, onde carrée : perçante même dans la circulation.
    const frequences = [988.0, 1319.0, 1760.0];
    for (var i = 0; i < frequences.length; i++) {
      _bip(contexte, frequences[i], debut + i * 0.22, 0.16);
    }
  } catch (_) {
    // Audio indisponible : la vibration et l'affichage suffisent.
  }
}

void _bip(_Contexte contexte, double frequence, double debut, double duree) {
  final oscillateur = contexte.createOscillator()..type = 'square';
  oscillateur.frequency.setValueAtTime(frequence, debut);
  final volume = contexte.createGain();
  volume.gain
    ..setValueAtTime(0.0001, debut)
    ..linearRampToValueAtTime(0.9, debut + 0.01)
    ..setValueAtTime(0.9, debut + duree - 0.02)
    ..linearRampToValueAtTime(0.0001, debut + duree);
  oscillateur.connect(volume);
  volume.connect(contexte.destination);
  oscillateur
    ..start(debut)
    ..stop(debut + duree + 0.02);
}

void _vibrer() {
  try {
    if (_navigator.has('vibrate')) {
      _navigator.callMethod<JSAny?>('vibrate'.toJS, [300, 120, 300, 120, 300].jsify());
    }
  } catch (_) {}
}
