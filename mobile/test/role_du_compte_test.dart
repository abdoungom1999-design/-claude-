import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sprint/features/auth/data/role_du_compte.dart';

class _MemoireFausse implements MemoireLocale {
  String? valeur;
  bool lectureEnPanne = false;
  bool ecritureEnPanne = false;
  bool effacementEnPanne = false;

  @override
  Future<String?> lire() async {
    if (lectureEnPanne) throw StateError('stockage illisible');
    return valeur;
  }

  @override
  Future<void> ecrire(String nouvelle) async {
    if (ecritureEnPanne) throw StateError('stockage refusé');
    valeur = nouvelle;
  }

  @override
  Future<void> effacer() async {
    if (effacementEnPanne) throw StateError('stockage refusé');
    valeur = null;
  }
}

/// Lecture en ligne factice : compte les appels, peut tarder ou échouer.
class _EnLigneFaux {
  String? role;
  Object? panne;
  Completer<void>? attente;
  final appels = <String>[];

  Future<String?> lire(String uid) async {
    appels.add(uid);
    await attente?.future;
    if (panne != null) throw panne!;
    return role;
  }
}

void main() {
  late _MemoireFausse memoire;
  late _EnLigneFaux enLigne;
  late RoleDuCompte role;

  setUp(() {
    memoire = _MemoireFausse();
    enLigne = _EnLigneFaux();
    role = RoleDuCompte(memoire: memoire, lireEnLigne: enLigne.lire);
  });

  group('première ouverture (rien de retenu)', () {
    test('le rôle est lu en ligne puis retenu pour la fois suivante', () async {
      enLigne.role = 'conducteur';
      expect(await role.pour('uid-1'), 'conducteur');
      expect(enLigne.appels, ['uid-1']);
      expect(memoire.valeur, 'uid-1|conducteur');
    });

    test('rôle introuvable : null, et rien n\'est retenu', () async {
      enLigne.role = null;
      expect(await role.pour('uid-1'), isNull);
      expect(memoire.valeur, isNull);
    });

    test('lecture en ligne en panne : null, sans erreur', () async {
      enLigne.panne = StateError('hors ligne');
      expect(await role.pour('uid-1'), isNull);
      expect(memoire.valeur, isNull);
    });

    test('réseau trop lent : on n\'attend pas plus que le délai, la réponse tardive est retenue pour la fois suivante',
        () async {
      enLigne.attente = Completer<void>();
      enLigne.role = 'conducteur';
      expect(await role.pour('uid-1', delai: const Duration(milliseconds: 30)), isNull);
      expect(memoire.valeur, isNull);

      enLigne.attente!.complete(); // le serveur finit par répondre
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(memoire.valeur, 'uid-1|conducteur');
      expect(await role.pour('uid-1'), 'conducteur');
    });

    test('réseau trop lent puis en panne : rien n\'est retenu, sans erreur', () async {
      enLigne.attente = Completer<void>();
      enLigne.panne = StateError('hors ligne');
      expect(await role.pour('uid-1', delai: const Duration(milliseconds: 30)), isNull);
      enLigne.attente!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(memoire.valeur, isNull);
    });
  });

  group('rôle déjà retenu', () {
    test('réponse immédiate, sans attendre le réseau', () async {
      memoire.valeur = 'uid-1|conducteur';
      enLigne.attente = Completer<void>(); // le serveur ne répond jamais
      expect(await role.pour('uid-1').timeout(const Duration(milliseconds: 200)), 'conducteur');
    });

    test('même sans réseau du tout, le chauffeur reste chauffeur', () async {
      memoire.valeur = 'uid-1|conducteur';
      enLigne.panne = StateError('hors ligne');
      expect(await role.pour('uid-1'), 'conducteur');
      await Future<void>.delayed(Duration.zero);
      expect(memoire.valeur, 'uid-1|conducteur'); // la panne n'efface rien
    });

    test('vérifié en arrière-plan : un rôle changé côté serveur est retenu pour l\'ouverture suivante', () async {
      memoire.valeur = 'uid-1|client';
      enLigne.role = 'conducteur';
      expect(await role.pour('uid-1'), 'client'); // cette fois-ci : le rôle retenu
      await Future<void>.delayed(Duration.zero);
      expect(enLigne.appels, ['uid-1']);
      expect(await role.pour('uid-1'), 'conducteur'); // la fois suivante : le nouveau
    });

    test('le rôle d\'un autre compte n\'est jamais repris', () async {
      memoire.valeur = 'uid-autre|admin';
      enLigne.role = 'client';
      expect(await role.pour('uid-1'), 'client');
      expect(memoire.valeur, 'uid-1|client');
    });

    test('valeur retenue illisible ou vide : lecture en ligne', () async {
      enLigne.role = 'client';
      for (final abime in ['', '|', 'uid-1', 'uid-1|', '|client']) {
        memoire.valeur = abime;
        expect(await role.pour('uid-1'), 'client', reason: '« $abime »');
      }
    });

    test('mémoire illisible (stockage refusé) : lecture en ligne', () async {
      memoire.lectureEnPanne = true;
      enLigne.role = 'admin';
      expect(await role.pour('uid-1'), 'admin');
    });

    test('mémoire en écriture refusée : le rôle est quand même rendu', () async {
      memoire.ecritureEnPanne = true;
      enLigne.role = 'conducteur';
      expect(await role.pour('uid-1'), 'conducteur');
    });
  });

  group('connexion, inscription, déconnexion', () {
    test('mémoriser retient le rôle du compte, lu ensuite sans réseau', () async {
      await role.memoriser('uid-1', 'conducteur');
      enLigne.panne = StateError('hors ligne');
      expect(await role.pour('uid-1'), 'conducteur');
    });

    test('mémoriser en écriture refusée ne lève rien', () async {
      memoire.ecritureEnPanne = true;
      await role.memoriser('uid-1', 'client');
    });

    test('actualiser lit le rôle réel du compte et le retient, même si un ancien était retenu', () async {
      memoire.valeur = 'uid-1|client';
      enLigne.role = 'admin';
      await role.actualiser('uid-1');
      expect(memoire.valeur, 'uid-1|admin');
    });

    test('actualiser sans réponse du serveur ne touche à rien', () async {
      memoire.valeur = 'uid-1|conducteur';
      enLigne.panne = StateError('hors ligne');
      await role.actualiser('uid-1');
      expect(memoire.valeur, 'uid-1|conducteur');
    });

    test('oublier efface le rôle : la personne suivante repart de zéro', () async {
      await role.memoriser('uid-1', 'conducteur');
      await role.oublier();
      expect(memoire.valeur, isNull);
      enLigne.role = 'client';
      expect(await role.pour('uid-2'), 'client');
      expect(enLigne.appels, ['uid-2']);
    });

    test('oublier avec un stockage qui refuse ne lève rien', () async {
      memoire.effacementEnPanne = true;
      await role.oublier();
    });
  });
}
