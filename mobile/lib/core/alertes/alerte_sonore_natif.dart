import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// APK Android : son de notification du téléphone et vibrations, joués
/// par le code natif (android/…/MainActivity.kt). Ailleurs (tests, poste
/// de développement) : rien.
const _canal = MethodChannel('sprint/alerte');

// Aucune autorisation à débloquer hors navigateur.
void preparer() {}

void nouvelleCourse() {
  if (!Platform.isAndroid) return;
  unawaited(_canal.invokeMethod<void>('nouvelleCourse').then((_) {}, onError: (_) {}));
}
