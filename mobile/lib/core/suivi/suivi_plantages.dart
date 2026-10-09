import 'dart:io' show Platform;

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Ce que le suivi des plantages demande à Crashlytics (remplaçable dans les
/// tests : aucun appel réel hors d'un téléphone Android).
abstract interface class JournalPlantages {
  Future<void> activerLaCollecte(bool activee);

  /// Erreur du framework Flutter (écran qui ne se construit pas, etc.).
  void erreurDuFramework(FlutterErrorDetails details);

  /// Erreur que personne n'a rattrapée (souvent dans du code asynchrone).
  void erreurNonRattrapee(Object erreur, StackTrace pile);

  /// Plante l'application exprès, pour vérifier que le rapport arrive.
  void plantagePourTest();
}

class JournalCrashlytics implements JournalPlantages {
  const JournalCrashlytics();

  FirebaseCrashlytics get _crashlytics => FirebaseCrashlytics.instance;

  @override
  Future<void> activerLaCollecte(bool activee) => _crashlytics.setCrashlyticsCollectionEnabled(activee);

  @override
  void erreurDuFramework(FlutterErrorDetails details) => _crashlytics.recordFlutterFatalError(details);

  @override
  void erreurNonRattrapee(Object erreur, StackTrace pile) => _crashlytics.recordError(erreur, pile, fatal: true);

  @override
  void plantagePourTest() => _crashlytics.crash();
}

/// Suivi des plantages de l'application Android : chaque plantage et chaque
/// erreur imprévue part vers Firebase Crashlytics (console Firebase >
/// Crashlytics), avec la version de l'app et le modèle du téléphone, pour être
/// corrigé avant que les chauffeurs s'en plaignent. L'app n'y ajoute ni nom, ni
/// numéro, ni identifiant de compte (le texte d'une erreur imprévue, lui, n'est
/// pas filtré).
///
/// Android seulement : Crashlytics n'existe pas pour le web, donc ni pour le
/// site ni pour l'app installée sur l'iPhone. Les rapports ne sont envoyés
/// que par une app compilée en version finale (jamais pendant le
/// développement ni les tests). Rien ici ne doit jamais empêcher l'app de
/// démarrer : toute erreur du suivi lui-même est ignorée.
class SuiviDesPlantages {
  SuiviDesPlantages({JournalPlantages? journal, bool? compatible, bool? versionFinale})
      : _journal = journal ?? const JournalCrashlytics(),
        compatible = compatible ?? _surAndroid,
        _versionFinale = versionFinale ?? kReleaseMode;

  /// Le suivi de l'app (un seul pour toute l'app).
  static final SuiviDesPlantages instance = SuiviDesPlantages();

  /// Système réel (et non `defaultTargetPlatform`, qui vaut Android dans les
  /// tests) ; `kIsWeb` d'abord : `Platform` n'existe pas sur le web.
  static bool get _surAndroid => !kIsWeb && Platform.isAndroid;

  final JournalPlantages _journal;
  final bool _versionFinale;

  /// Cet appareil peut envoyer des rapports (Android).
  final bool compatible;

  bool _branche = false;

  /// Le suivi est branché : les erreurs de cet appareil sont transmises à Crashlytics.
  bool get actif => _branche;

  /// Un plantage de test arriverait réellement dans la console : suivi branché
  /// et app en version finale (en développement, la collecte est coupée).
  bool get testable => _branche && _versionFinale;

  /// Fait partir vers Crashlytics les erreurs du framework et les erreurs non
  /// rattrapées. À appeler une fois, juste après le démarrage de Firebase.
  Future<void> brancher() async {
    if (!compatible || _branche) return;
    try {
      await _journal.activerLaCollecte(_versionFinale);
      final precedent = FlutterError.onError;
      FlutterError.onError = (details) {
        // L'affichage habituel de l'erreur (console, écran rouge) est conservé.
        precedent?.call(details);
        _signaler(() => _journal.erreurDuFramework(details));
      };
      PlatformDispatcher.instance.onError = (erreur, pile) {
        _signaler(() => _journal.erreurNonRattrapee(erreur, pile));
        return true;
      };
      _branche = true;
    } on Object catch (e) {
      debugPrint('Suivi des plantages non branché : $e');
    }
  }

  /// Plante l'application exprès (Admin > Paramètres) : le rapport part à
  /// la prochaine ouverture et apparaît dans la console Firebase.
  void plantagePourTest() {
    if (!testable) return;
    _journal.plantagePourTest();
  }

  void _signaler(void Function() envoyer) {
    try {
      envoyer();
    } on Object catch (e) {
      debugPrint('Rapport de plantage non envoyé : $e');
    }
  }
}
