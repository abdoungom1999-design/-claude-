import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/core/notifications/notifications_push.dart';

class _Passerelle implements PasserellePush {
  bool autorise = true;
  String? jetonCourant = 'jeton-1';
  var autorisationsDemandees = 0;
  var jetonsSupprimes = 0;
  Object? erreurJeton;
  MessagePush? initial;
  final renouvellements = StreamController<String>.broadcast();
  final appuis = StreamController<MessagePush>.broadcast();

  @override
  Future<bool> demanderAutorisation() async {
    autorisationsDemandees++;
    return autorise;
  }

  @override
  Future<String?> jeton() async {
    if (erreurJeton != null) throw erreurJeton!;
    return jetonCourant;
  }

  @override
  Stream<String> get jetonRenouvele => renouvellements.stream;

  @override
  Future<void> supprimerJeton() async => jetonsSupprimes++;

  @override
  Stream<MessagePush> get ouvertures => appuis.stream;

  @override
  Future<MessagePush?> messageInitial() async => initial;
}

class _Stockage implements StockageJetons {
  final enregistres = <(String, String)>[];
  final supprimes = <(String, String)>[];
  bool refuse = false;

  @override
  Future<void> enregistrer(String uid, String jeton) async {
    if (refuse) throw Exception('permission-denied');
    enregistres.add((uid, jeton));
  }

  @override
  Future<void> supprimer(String uid, String jeton) async => supprimes.add((uid, jeton));
}

Future<void> _laisser() => Future<void>.delayed(Duration.zero);

void main() {
  late _Passerelle passerelle;
  late _Stockage stockage;
  late NotificationsPush push;
  late List<MessagePush> appuis;

  setUp(() {
    passerelle = _Passerelle();
    stockage = _Stockage();
    push = NotificationsPush(passerelle: passerelle, stockage: stockage, estAndroid: true);
    appuis = [];
  });

  test('connexion : autorisation demandée, puis jeton enregistré pour ce compte', () async {
    await push.activer(uid: 'awa', surAppui: appuis.add);
    expect(passerelle.autorisationsDemandees, 1);
    expect(stockage.enregistres, [('awa', 'jeton-1')]);
    expect(push.uid, 'awa');
  });

  test('jeton renouvelé par Google : réenregistré', () async {
    await push.activer(uid: 'awa', surAppui: appuis.add);
    passerelle.renouvellements.add('jeton-2');
    await _laisser();
    expect(stockage.enregistres, [('awa', 'jeton-1'), ('awa', 'jeton-2')]);
  });

  test('autorisation refusée : rien n\'est enregistré (le téléphone ne recevrait rien)', () async {
    passerelle.autorise = false;
    await push.activer(uid: 'awa', surAppui: appuis.add);
    expect(stockage.enregistres, isEmpty);
  });

  test('activer deux fois pour le même compte : une seule demande, un seul enregistrement', () async {
    await push.activer(uid: 'awa', surAppui: appuis.add);
    await push.activer(uid: 'awa', surAppui: appuis.add);
    expect(passerelle.autorisationsDemandees, 1);
    expect(stockage.enregistres.length, 1);
  });

  test('déconnexion : jeton supprimé (base et Google), plus de renouvellement enregistré', () async {
    await push.activer(uid: 'awa', surAppui: appuis.add);
    await push.desactiver();
    expect(stockage.supprimes, [('awa', 'jeton-1')]);
    expect(passerelle.jetonsSupprimes, 1);
    expect(push.uid, isNull);

    passerelle.renouvellements.add('jeton-3');
    await _laisser();
    expect(stockage.enregistres.length, 1);
    // Rappeler la déconnexion ne fait rien de plus.
    await push.desactiver();
    expect(stockage.supprimes.length, 1);
  });

  test('changement de compte : le jeton de l\'ancien compte est supprimé avant celui du nouveau', () async {
    await push.activer(uid: 'awa', surAppui: appuis.add);
    passerelle.jetonCourant = 'jeton-2';
    await push.activer(uid: 'moussa', surAppui: appuis.add);
    expect(stockage.supprimes, [('awa', 'jeton-1')]);
    expect(stockage.enregistres, [('awa', 'jeton-1'), ('moussa', 'jeton-2')]);
  });

  test('appui sur une notification (app en arrière-plan ou fermée) : transmis avec son contenu', () async {
    passerelle.initial = const MessagePush({'type': 'acceptee', 'courseId': 'c1'});
    await push.activer(uid: 'awa', surAppui: appuis.add);
    expect(appuis.single.type, 'acceptee');
    expect(appuis.single.courseId, 'c1');

    passerelle.appuis.add(const MessagePush({'type': 'message', 'expediteurId': 'moussa'}));
    await _laisser();
    expect(appuis.length, 2);
    expect(appuis.last.type, 'message');

    await push.desactiver();
    passerelle.appuis.add(const MessagePush({'type': 'message'}));
    await _laisser();
    expect(appuis.length, 2);
  });

  test('aucun problème de notification ne fait échouer l\'app : jeton illisible, base qui refuse', () async {
    passerelle.erreurJeton = Exception('SERVICE_NOT_AVAILABLE');
    await push.activer(uid: 'awa', surAppui: appuis.add);
    expect(stockage.enregistres, isEmpty);

    final autre = NotificationsPush(passerelle: _Passerelle(), stockage: _Stockage()..refuse = true, estAndroid: true);
    await autre.activer(uid: 'awa', surAppui: appuis.add);
    await autre.desactiver(); // jeton jamais enregistré : rien à supprimer côté base
  });

  test('hors APK Android (web, iPhone, tests) : aucune demande, aucun enregistrement', () async {
    final web = NotificationsPush(passerelle: passerelle, stockage: stockage, estAndroid: false);
    await web.activer(uid: 'awa', surAppui: appuis.add);
    await web.desactiver();
    expect(passerelle.autorisationsDemandees, 0);
    expect(stockage.enregistres, isEmpty);
    expect(passerelle.jetonsSupprimes, 0);
  });
}
