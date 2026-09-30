import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'capacites_navigateur.dart';

/// Ce que contient une notification push quand on appuie dessus
/// (`type` : `message`, `course`, `acceptee` ou `annulee` ; voir
/// `functions/src/notifications.ts`).
/// Autorisation d'afficher des notifications.
enum EtatAutorisation { accordee, refusee, aDemander }

class MessagePush {
  const MessagePush(this.donnees);

  final Map<String, String> donnees;

  String? get type => donnees['type'];
  String? get courseId => donnees['courseId'];
}

/// Accès à Firebase Cloud Messaging, isolé pour pouvoir être remplacé dans
/// les tests.
abstract class PasserellePush {
  /// Le navigateur sait recevoir des notifications push (toujours vrai sur
  /// Android).
  Future<bool> supporte();

  /// Où en est l'autorisation, sans rien demander à l'utilisateur.
  Future<EtatAutorisation> etatAutorisation();

  /// Demande l'autorisation d'afficher des notifications (Android 13+ :
  /// boîte de dialogue du système ; navigateur : fenêtre du navigateur, qui
  /// exige un appui de l'utilisateur) ; `true` si elle est accordée.
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
  Future<bool> supporte() => kIsWeb ? _fcm.isSupported() : Future.value(true);

  @override
  Future<EtatAutorisation> etatAutorisation() async {
    final r = await _fcm.getNotificationSettings();
    return switch (r.authorizationStatus) {
      AuthorizationStatus.authorized || AuthorizationStatus.provisional => EtatAutorisation.accordee,
      AuthorizationStatus.denied => EtatAutorisation.refusee,
      AuthorizationStatus.notDetermined => EtatAutorisation.aDemander,
    };
  }

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
  StockageJetonsFirestore({this.plateforme = 'android'});

  /// `android` (APK) ou `web` (navigateur, iPhone) : voir firestore.rules.
  final String plateforme;

  DocumentReference<Map<String, dynamic>> _doc(String uid, String jeton) =>
      FirebaseFirestore.instance.collection('appareils').doc(uid).collection('jetons').doc(jeton);

  @override
  Future<void> enregistrer(String uid, String jeton) =>
      _doc(uid, jeton).set({'plateforme': plateforme, 'majLe': FieldValue.serverTimestamp()});

  @override
  Future<void> supprimer(String uid, String jeton) => _doc(uid, jeton).delete();
}

/// Où en sont les notifications sur cet appareil (voir [CarteNotifications]).
enum EtatNotifications {
  /// Pas encore vérifié (ou pas de compte connecté).
  inconnu,

  /// Ce navigateur ne sait pas recevoir de notifications.
  nonSupportees,

  /// iPhone : les notifications n'existent que pour le site installé sur
  /// l'écran d'accueil (iOS 16.4 minimum), pas dans un onglet Safari.
  iphoneHorsEcranAccueil,

  /// Pas encore autorisées : un appui de l'utilisateur est nécessaire.
  aActiver,

  activees,

  /// Refusées par l'utilisateur : il doit les rouvrir dans les réglages.
  bloquees,
}

/// Où tournent les notifications : APK Android ou site (navigateur, iPhone).
enum PlateformePush { android, web, aucune }

/// Notifications push : elles arrivent même app fermée (APK Android) ou site
/// fermé (navigateur, site installé sur l'iPhone).
///
/// À la connexion, l'app enregistre le jeton du téléphone ; à la
/// déconnexion, elle le supprime (le téléphone ne doit pas continuer à
/// recevoir les notifications d'un autre compte). Quand l'app est ouverte,
/// rien n'est affiché par le système : l'app a ses propres alertes (son,
/// vibration, pastille).
///
/// Android : l'autorisation est demandée tout de suite. Site : les
/// navigateurs (et surtout iOS) n'acceptent de la demander qu'après un appui
/// de l'utilisateur : [activer] enregistre le jeton si l'autorisation est
/// déjà donnée, sinon [etat] passe à `aActiver` et un bouton
/// ([CarteNotifications]) appelle [demander].
class NotificationsPush {
  NotificationsPush({
    PasserellePush? passerelle,
    StockageJetons? stockage,
    PlateformePush? plateforme,
    CapacitesNavigateur Function()? capacites,
  })  : plateforme = plateforme ?? _plateformeCourante(),
        _passerelle = passerelle ?? PasserelleFirebase(),
        _stockage = stockage ??
            StockageJetonsFirestore(
              plateforme: (plateforme ?? _plateformeCourante()) == PlateformePush.web ? 'web' : 'android',
            ),
        _capacites = capacites ?? lireCapacitesNavigateur;

  /// Instance de l'application ; les tests créent la leur.
  static final instance = NotificationsPush();

  static PlateformePush _plateformeCourante() {
    if (kIsWeb) return PlateformePush.web;
    return defaultTargetPlatform == TargetPlatform.android ? PlateformePush.android : PlateformePush.aucune;
  }

  final PlateformePush plateforme;
  final PasserellePush _passerelle;
  final StockageJetons _stockage;
  final CapacitesNavigateur Function() _capacites;

  String? _uid;
  String? _jeton;
  StreamSubscription<String>? _abonnementRenouvellement;
  StreamSubscription<MessagePush>? _abonnementOuvertures;
  final _etat = ValueNotifier(EtatNotifications.inconnu);

  /// Compte pour lequel les notifications sont actives, `null` sinon.
  String? get uid => _uid;

  /// État des notifications sur cet appareil, pour l'affichage.
  ValueListenable<EtatNotifications> get etat => _etat;

  /// Active les notifications pour [uid]. [surAppui] est appelé quand
  /// l'utilisateur appuie sur une notification (app ou site en arrière-plan
  /// ou fermé). Ne lève jamais d'erreur : un problème de notification ne
  /// doit pas empêcher d'utiliser l'app.
  Future<void> activer({required String uid, required void Function(MessagePush) surAppui}) async {
    if (plateforme == PlateformePush.aucune) return;
    if (_uid == uid) return;
    if (_uid != null) await desactiver();
    _uid = uid;
    try {
      _abonnementOuvertures = _passerelle.ouvertures.listen(surAppui, onError: (_) {});
      final initial = await _passerelle.messageInitial();
      if (initial != null && _uid == uid) surAppui(initial);

      if (plateforme == PlateformePush.android) {
        // Android : la boîte de dialogue du système s'affiche tout de suite.
        final accordee = await _passerelle.demanderAutorisation();
        if (_uid != uid) return;
        _etat.value = accordee ? EtatNotifications.activees : EtatNotifications.bloquees;
        if (accordee) await _enregistrerJeton(uid);
        return;
      }

      // Site : jamais de demande sans appui de l'utilisateur.
      final etat = await _etatSite();
      if (_uid != uid) return;
      _etat.value = etat;
      if (etat == EtatNotifications.activees) await _enregistrerJeton(uid);
    } catch (e) {
      debugPrint('Notifications push indisponibles : $e');
    }
  }

  /// Le site demande l'autorisation puis enregistre le jeton. À appeler
  /// UNIQUEMENT à l'appui sur un bouton (les navigateurs refusent sinon,
  /// iOS y compris).
  Future<void> demander() async {
    final uid = _uid;
    if (uid == null || plateforme == PlateformePush.aucune) return;
    try {
      if (plateforme == PlateformePush.web) {
        final avant = await _etatSite();
        if (avant == EtatNotifications.nonSupportees || avant == EtatNotifications.iphoneHorsEcranAccueil) {
          _etat.value = avant;
          return;
        }
      }
      final accordee = await _passerelle.demanderAutorisation();
      if (_uid != uid) return;
      _etat.value = accordee ? EtatNotifications.activees : EtatNotifications.bloquees;
      if (accordee) await _enregistrerJeton(uid);
    } catch (e) {
      debugPrint('Autorisation des notifications impossible : $e');
    }
  }

  Future<EtatNotifications> _etatSite() async {
    final navigateur = _capacites();
    if (navigateur.iphone && !navigateur.ecranAccueil) return EtatNotifications.iphoneHorsEcranAccueil;
    if (!await _passerelle.supporte()) return EtatNotifications.nonSupportees;
    return switch (await _passerelle.etatAutorisation()) {
      EtatAutorisation.accordee => EtatNotifications.activees,
      EtatAutorisation.refusee => EtatNotifications.bloquees,
      EtatAutorisation.aDemander => EtatNotifications.aActiver,
    };
  }

  Future<void> _enregistrerJeton(String uid) async {
    await _enregistrer(uid, await _passerelle.jeton());
    _abonnementRenouvellement ??= _passerelle.jetonRenouvele.listen(
      (jeton) => unawaited(_enregistrer(uid, jeton)),
      onError: (_) {},
    );
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
    _etat.value = EtatNotifications.inconnu;
    await _abonnementRenouvellement?.cancel();
    await _abonnementOuvertures?.cancel();
    _abonnementRenouvellement = null;
    _abonnementOuvertures = null;
    if (plateforme == PlateformePush.aucune || uid == null) return;
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
