import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/firebase/fonctions_cloud.dart';
import '../../../firebase_options.dart';

/// Portefeuille Sprint (crédit prépayé, non retirable, utilisable pour
/// payer des courses). Mêmes limites que `functions/src/portefeuille.ts`,
/// qui les fait respecter : ce ne sont ici que des garde-fous d'affichage.
abstract final class LimitesPortefeuille {
  static const rechargeMinFcfa = 500;
  static const rechargeMaxFcfa = 100000;
  static const soldeMaxFcfa = 200000;
}

/// Solde et préférence du client (`portefeuilles/{uid}`). Le solde n'est
/// écrit que par le serveur ; la préférence, par le client.
class Portefeuille {
  const Portefeuille({this.soldeFcfa = 0, this.payerAvecSolde = false});

  final int soldeFcfa;

  /// Interrupteur « Régler mes courses avec mon solde ».
  final bool payerAvecSolde;

  /// Le solde couvre-t-il [prixFcfa] ?
  bool couvre(int prixFcfa) => soldeFcfa >= prixFcfa;

  /// Recharge encore possible avant le plafond du solde.
  int get rechargePossibleFcfa => (LimitesPortefeuille.soldeMaxFcfa - soldeFcfa).clamp(0, LimitesPortefeuille.soldeMaxFcfa);

  static Portefeuille depuisDocument(Map<String, dynamic>? donnees) {
    if (donnees == null) return const Portefeuille();
    final solde = donnees['soldeFcfa'];
    final preference = donnees['payerAvecSolde'];
    return Portefeuille(
      soldeFcfa: solde is num ? solde.toInt() : 0,
      payerAvecSolde: preference is bool ? preference : false,
    );
  }
}

/// Ligne du livre de comptes (`portefeuilles/{uid}/mouvements/{id}`).
class MouvementPortefeuille {
  const MouvementPortefeuille({
    required this.id,
    required this.type,
    required this.montantFcfa,
    required this.soldeApresFcfa,
    this.note,
    this.creeLe,
  });

  final String id;
  final String type;

  /// Positif : crédit ; négatif : débit.
  final int montantFcfa;
  final int soldeApresFcfa;
  final String? note;
  final DateTime? creeLe;

  static const recharge = 'recharge';
  static const paiementCourse = 'paiement_course';
  static const remboursement = 'remboursement';
  static const ajustementAdmin = 'ajustement_admin';

  String get libelle => switch (type) {
        recharge => 'Recharge',
        paiementCourse => 'Paiement d\'une course',
        remboursement => 'Remboursement d\'une course',
        ajustementAdmin => 'Ajustement Sprint',
        _ => 'Mouvement',
      };

  static MouvementPortefeuille depuisDocument(String id, Map<String, dynamic> donnees) {
    final creeLe = donnees['creeLe'];
    return MouvementPortefeuille(
      id: id,
      type: donnees['type'] as String? ?? '',
      montantFcfa: (donnees['montantFcfa'] as num?)?.toInt() ?? 0,
      soldeApresFcfa: (donnees['soldeApresFcfa'] as num?)?.toInt() ?? 0,
      note: donnees['note'] as String?,
      creeLe: creeLe is Timestamp ? creeLe.toDate() : null,
    );
  }
}

/// Lien de paiement d'une recharge, renvoyé par le serveur.
class RechargeDemandee {
  const RechargeDemandee({required this.rechargeId, required this.lienPaiement, required this.montantFcfa});

  final String rechargeId;
  final Uri lienPaiement;
  final int montantFcfa;
}

/// Avancement d'une recharge (`recharges/{id}`, écrite par le serveur).
class AvancementRecharge {
  const AvancementRecharge({required this.statut});

  final String statut;
}

/// Valeurs du champ `statut` d'une recharge (voir `functions/src/portefeuille.ts`).
abstract final class StatutRecharge {
  static const enAttente = 'en_attente';
  static const reussie = 'reussie';
  static const echouee = 'echouee';
  static const expiree = 'expiree';
}

/// Accès de l'app au portefeuille : lectures en temps réel, préférence, et
/// demande de recharge (Cloud Function `creerRecharge`). Jamais d'écriture
/// du solde : il ne bouge que sur confirmation du serveur.
class PortefeuilleService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _portefeuille(String uid) => _firestore.collection('portefeuilles').doc(uid);

  Stream<Portefeuille> streamPortefeuille(String uid) =>
      _portefeuille(uid).snapshots().map((doc) => Portefeuille.depuisDocument(doc.data()));

  /// Lecture unique (choix du mode de paiement d'une commande).
  Future<Portefeuille> lire(String uid) async => Portefeuille.depuisDocument((await _portefeuille(uid).get()).data());

  /// Portefeuille du client connecté pour le choix du mode de paiement d'une
  /// commande. `null` en mode démo, hors connexion ou si la lecture tarde
  /// (4 s) : la commande se fait alors par mobile money, comme avant.
  Future<Portefeuille?> lirePourCommande() async {
    if (!DefaultFirebaseOptions.estConfigure) return null;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    try {
      return await lire(uid).timeout(const Duration(seconds: 4));
    } on Object {
      return null;
    }
  }

  Future<void> definirPayerAvecSolde(String uid, bool valeur) =>
      _portefeuille(uid).set({'payerAvecSolde': valeur}, SetOptions(merge: true));

  /// Livre de comptes, du plus récent au plus ancien.
  Stream<List<MouvementPortefeuille>> streamMouvements(String uid) {
    return _portefeuille(uid).collection('mouvements').snapshots().map(
          (instantane) => [
            for (final doc in instantane.docs) MouvementPortefeuille.depuisDocument(doc.id, doc.data()),
          ]..sort((a, b) {
              final da = a.creeLe;
              final db = b.creeLe;
              if (da == null) return db == null ? 0 : -1;
              if (db == null) return 1;
              return db.compareTo(da);
            }),
        );
  }

  /// Demande de recharge : le serveur vérifie montant, plafond et compte,
  /// puis renvoie le lien de paiement de l'opérateur. Le solde n'est crédité
  /// qu'à la confirmation signée de l'opérateur.
  Future<RechargeDemandee> creerRecharge({required int montantFcfa, required String methodePaiement}) async {
    try {
      final resultat = await FonctionsCloud.appeler('creerRecharge', {
        'montantFcfa': montantFcfa,
        'methodePaiement': methodePaiement,
      });
      return RechargeDemandee(
        rechargeId: resultat['rechargeId'] as String,
        lienPaiement: Uri.parse(resultat['lienPaiement'] as String),
        montantFcfa: (resultat['montantFcfa'] as num).toInt(),
      );
    } on FirebaseFunctionsException catch (e) {
      throw FonctionsCloud.versApiException(e);
    }
  }

  Stream<AvancementRecharge?> streamRecharge(String rechargeId) {
    return _firestore.collection('recharges').doc(rechargeId).snapshots().map((doc) {
      final donnees = doc.data();
      if (!doc.exists || donnees == null) return null;
      return AvancementRecharge(statut: donnees['statut'] as String? ?? StatutRecharge.enAttente);
    });
  }

  /// Admin : crédit ou débit manuel, motivé et journalisé (Cloud Function
  /// `ajusterPortefeuille`). Renvoie le nouveau solde.
  Future<int> ajuster({required String clientId, required int montantFcfa, required String motif}) async {
    try {
      final resultat = await FonctionsCloud.appeler('ajusterPortefeuille', {
        'clientId': clientId,
        'montantFcfa': montantFcfa,
        'motif': motif,
      });
      return (resultat['soldeFcfa'] as num).toInt();
    } on FirebaseFunctionsException catch (e) {
      throw FonctionsCloud.versApiException(e);
    }
  }
}
