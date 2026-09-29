import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Ce que contient une notification push quand on appuie dessus
/// (`type` : `message`, `course`, `acceptee` ou `annulee` ; voir
/// `functions/src/notifications.ts`).
class MessagePush {
  const MessagePush(this.donnees);

  final Map<String, String> donnees;

  String? get type => donnees['type'];
  String? get courseId => donnees['courseId'];
}

/// Accès à Firebase Cloud Messaging, isolé pour pouvoir être remplacé dans
/// les tests.
abstract class PasserellePush {
  /// Demande l'autorisation d'afficher des notifications (Android 13+ :
  /// boîte de dialogue du système) ; `true` si elle est accordée.
  Future<bool> demanderAutorisation();

  Future<String?> jeton();

  /// Jeton renouvelé par Google (à réenregistrer).
  Stream<String> get jetonRenouvele;

  Future<void> supprimerJeton();

  /// Appui sur une notification alors que l'app tournait en arrière-plan.
  Stream<MessagePush> get ouvertures;

  /// Notification sur laquelle on a appuyé alors que l'app était fermée.
  Future<MessagePush?> messageInitial();
}

class PasserelleFirebase implements PasserellePush {
  FirebaseMessaging get _fcm => FirebaseMessaging.instance;

  static MessagePush _versMessage(RemoteMessage m) =>
      MessagePush({for (final e in m.data.entries) e.key: '${e.value}'});

  @override
  Future<bool> demanderAutorisation() async {
    final r = await _fcm.requestPermission();
    return r.authorizationStatus == AuthorizationStatus.authorized;
  }

  @override
  Future<String?> jeton() => _fcm.getToken();

  @override
  Stream<String> get jetonRenouvele => _fcm.onTokenRefresh;

  @override
  Future<void> supprimerJeton() => _fcm.deleteToken();

  @override
  Stream<MessagePush> get ouvertures => FirebaseMessaging.onMessageOpenedApp.map(_versMessage);

  @override
  Future<MessagePush?> messageInitial() async {
    final m = await _fcm.getInitialMessage();
    return m == null ? null : _versMessage(m);
  }
}

/// Où sont enregistrés les jetons : `appareils/{uid}/jetons/{jeton}`
/// (règles Firestore : chacun n'écrit que les siens, personne ne les lit).
abstract class StockageJetons {
  Future<void> enregistrer(String uid, String jeton);

  Future<void> supprimer(String uid, String jeton);
}

class StockageJetonsFirestore implements StockageJetons {
  DocumentReference<Map<String, dynamic>> _doc(String uid, String jeton) =>
      FirebaseFirestore.instance.collection('appareils').doc(uid).collection('jetons').doc(jeton);

  @override
  Future<void> enregistrer(String uid, String jeton) =>
      _doc(uid, jeton).set({'plateforme': 'android', 'majLe': FieldValue.serverTimestamp()});

  @override
  Future<void> supprimer(String uid, String jeton) => _doc(uid, jeton).delete();
}

/// Notifications push (APK Android) : elles arrivent même app fermée.
///
/// À la connexion, l'app demande l'autorisation puis enregistre le jeton du
/// téléphone ; à la déconnexion, elle le supprime (le téléphone ne doit pas
/// continuer à recevoir les notifications d'un autre compte). Quand l'app
/// est ouverte, Android n'affiche pas ces notifications : l'app a déjà ses
/// propres alertes (son, vibration, pastille). Version web et iPhone : plus
/// tard, dans un autre lot.
class NotificationsPush {
  NotificationsPush({PasserellePush? passerelle, StockageJetons? stockage, bool? estAndroid})
      : _passerelle = passerelle ?? PasserelleFirebase(),
        _stockage = stockage ?? StockageJetonsFirestore(),
        _estAndroid = estAndroid ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  /// Instance de l'application ; les tests créent la leur.
  static final instance = NotificationsPush();

  final PasserellePush _passerelle;
  final StockageJetons _stockage;
  final bool _estAndroid;

  String? _uid;
  String? _jeton;
  StreamSubscription<String>? _abonnementRenouvellement;
  StreamSubscription<MessagePush>? _abonnementOuvertures;

  /// Compte pour lequel les notifications sont actives, `null` sinon.
  String? get uid => _uid;

  /// Active les notifications pour [uid]. [surAppui] est appelé quand
  /// l'utilisateur appuie sur une notification (app en arrière-plan ou
  /// fermée). Sans effet hors APK Android. Ne lève jamais d'erreur : un
  /// problème de notification ne doit pas empêcher d'utiliser l'app.
  Future<void> activer({required String uid, required void Function(MessagePush) surAppui}) async {
    if (!_estAndroid) return;
    if (_uid == uid) return;
    if (_uid != null) await desactiver();
    _uid = uid;
    try {
      _abonnementOuvertures = _passerelle.ouvertures.listen(surAppui, onError: (_) {});
      final initial = await _passerelle.messageInitial();
      if (initial != null && _uid == uid) surAppui(initial);

      if (!await _passerelle.demanderAutorisation()) return;
      if (_uid != uid) return;
      await _enregistrer(uid, await _passerelle.jeton());
      _abonnementRenouvellement = _passerelle.jetonRenouvele.listen(
        (jeton) => unawaited(_enregistrer(uid, jeton)),
        onError: (_) {},
      );
    } catch (e) {
      debugPrint('Notifications push indisponibles : $e');
    }
  }

  Future<void> _enregistrer(String uid, String? jeton) async {
    if (jeton == null || jeton.isEmpty) return;
    try {
      await _stockage.enregistrer(uid, jeton);
      _jeton = jeton;
    } catch (e) {
      debugPrint('Jeton push non enregistré : $e');
    }
  }

  /// Coupe les notifications de ce compte (déconnexion) : supprime le jeton
  /// enregistré pour lui. Délai borné : hors connexion, la déconnexion ne
  /// doit pas rester bloquée.
  Future<void> desactiver() async {
    final uid = _uid;
    final jeton = _jeton;
    _uid = null;
    _jeton = null;
    await _abonnementRenouvellement?.cancel();
    await _abonnementOuvertures?.cancel();
    _abonnementRenouvellement = null;
    _abonnementOuvertures = null;
    if (!_estAndroid || uid == null) return;
    try {
      await Future.wait([
        if (jeton != null) _stockage.supprimer(uid, jeton),
        _passerelle.supprimerJeton(),
      ]).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('Jeton push non supprimé : $e');
    }
  }
}
