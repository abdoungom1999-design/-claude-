import 'dart:js_interop';

@JS('navigator.wakeLock')
external _WakeLock? get _wakeLock;

@JS('document')
external _Document get _document;

extension type _WakeLock._(JSObject _) implements JSObject {
  external JSPromise<_Verrou> request(JSString type);
}

extension type _Verrou._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> release();
}

extension type _Document._(JSObject _) implements JSObject {
  external JSString get visibilityState;
  external void addEventListener(JSString type, JSFunction ecouteur);
  external void removeEventListener(JSString type, JSFunction ecouteur);
}

_Verrou? _verrou;
bool _souhaite = false;

// Le navigateur libère le verrou dès que l'onglet est masqué : on le
// redemande quand le chauffeur revient sur l'app.
final JSFunction _surVisibilite = ((JSAny? _) {
  if (_souhaite && _document.visibilityState.toDart == 'visible') _demander();
}).toJS;

Future<void> activer() async {
  _souhaite = true;
  _document.addEventListener('visibilitychange'.toJS, _surVisibilite);
  await _demander();
}

Future<void> desactiver() async {
  _souhaite = false;
  _document.removeEventListener('visibilitychange'.toJS, _surVisibilite);
  final verrou = _verrou;
  _verrou = null;
  if (verrou == null) return;
  try {
    await verrou.release().toDart;
  } catch (_) {}
}

Future<void> _demander() async {
  final wakeLock = _wakeLock;
  if (wakeLock == null) return;
  try {
    _verrou = await wakeLock.request('screen'.toJS).toDart;
  } catch (_) {
    // Refusé (économie d'énergie, onglet masqué…) : sans conséquence.
  }
}
