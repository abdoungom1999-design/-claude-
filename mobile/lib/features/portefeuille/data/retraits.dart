import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../../core/firebase/fonctions_cloud.dart';

/// Retrait du solde Sprint vers Orange Money ou Wave (lot B) : le client le
/// demande, le montant est réservé aussitôt sur son solde, un Admin fait le
/// transfert puis le marque « versé », ou le refuse (montant rendu). Voir
/// `functions/src/retraits.ts`.
///
/// Réglage en service. Ne change qu'avec le go du client, en même temps que
/// son jumeau du serveur (`RETRAITS_OUVERTS`) : un test du serveur vérifie
/// qu'ils sont d'accord. Fermé : rien n'apparaît au client.
const retraitsOuverts = false;

/// Montant minimal d'un retrait (`RETRAIT_MIN_FCFA` du serveur).
const retraitMinFcfa = 500;

enum MoyenRetrait {
  orangeMoney('ORANGE_MONEY', 'Orange Money'),
  wave('WAVE', 'Wave');

  const MoyenRetrait(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static MoyenRetrait? depuis(Object? valeur) {
    for (final moyen in values) {
      if (moyen.apiValue == valeur) return moyen;
    }
    return null;
  }
}

/// Demande de retrait (`retraits/{id}`), lue par son client et l'Admin.
class Retrait {
  const Retrait({
    required this.id,
    required this.clientId,
    required this.montantFcfa,
    required this.moyen,
    required this.numero,
    this.nomClient = 'Client',
    this.numeroDuCompte = false,
    this.creeLe,
  });

  final String id;
  final String clientId;
  final int montantFcfa;
  final MoyenRetrait? moyen;

  /// Numéro de réception, 9 chiffres.
  final String numero;

  /// Nom du compte (pour l'Admin).
  final String nomClient;

  /// Le numéro de réception est celui du compte ; sinon, l'Admin vérifie
  /// avant de verser (compte peut-être utilisé par un autre).
  final bool numeroDuCompte;
  final DateTime? creeLe;

  /// « 77 123 45 67 ».
  String get numeroLisible => formaterNumero(numero);

  static Retrait depuisDocument(String id, Map<String, dynamic> donnees) {
    final creeLe = donnees['creeLe'];
    return Retrait(
      id: id,
      clientId: donnees['clientId'] as String? ?? '',
      montantFcfa: (donnees['montantFcfa'] as num?)?.toInt() ?? 0,
      moyen: MoyenRetrait.depuis(donnees['moyen']),
      numero: donnees['numero'] as String? ?? '',
      nomClient: donnees['nomClient'] as String? ?? 'Client',
      numeroDuCompte: donnees['numeroDuCompte'] == true,
      creeLe: creeLe is Timestamp ? creeLe.toDate() : null,
    );
  }
}

/// Numéro de 9 chiffres présenté par groupes : « 77 123 45 67 ».
String formaterNumero(String numero) => numero.length == 9
    ? '${numero.substring(0, 2)} ${numero.substring(2, 5)} ${numero.substring(5, 7)} ${numero.substring(7)}'
    : numero;

/// Numéro mobile sénégalais (9 chiffres : 70, 75, 76, 77, 78), sans
/// indicatif ; accepte « +221 », « 00221 », espaces, points et tirets.
/// Même règle que le serveur (`numeroSenegal`). `null` sinon.
String? numeroSenegal(String valeur) {
  var n = valeur.replaceAll(RegExp(r'[\s.\-]'), '');
  if (n.startsWith('+221')) {
    n = n.substring(4);
  } else if (n.startsWith('00221')) {
    n = n.substring(5);
  } else if (n.length == 12 && n.startsWith('221')) {
    n = n.substring(3);
  }
  return RegExp(r'^7[05678]\d{7}$').hasMatch(n) ? n : null;
}

/// Accès aux retraits : demande (client), suivi, traitement (Admin).
class RetraitService {
  RetraitService({FirebaseFirestore? firestore}) : _firestoreInjecte = firestore;

  final FirebaseFirestore? _firestoreInjecte;
  FirebaseFirestore get _firestore => _firestoreInjecte ?? FirebaseFirestore.instance;

  /// Demande de retrait ; rend le nouveau solde. Erreurs du serveur : [ApiException].
  Future<int> demander({required int montantFcfa, required MoyenRetrait moyen, required String numero}) async {
    try {
      final resultat = await FonctionsCloud.appeler('demanderRetrait', {
        'montantFcfa': montantFcfa,
        'moyen': moyen.apiValue,
        'numero': numero,
      });
      return (resultat['soldeFcfa'] as num).toInt();
    } on FirebaseFunctionsException catch (e) {
      throw FonctionsCloud.versApiException(e);
    }
  }

  /// Retrait du client en attente de versement (au plus un), `null` sinon.
  Stream<Retrait?> streamRetraitEnCours(String uid) => _firestore
      .collection('retraits')
      .where('clientId', isEqualTo: uid)
      .where('statut', isEqualTo: 'demande')
      .limit(1)
      .snapshots()
      .map((s) => s.docs.isEmpty ? null : Retrait.depuisDocument(s.docs.first.id, s.docs.first.data()));

  /// Admin : retraits à verser, les plus anciens d'abord.
  Stream<List<Retrait>> streamRetraitsATraiter() =>
      _firestore.collection('retraits').where('statut', isEqualTo: 'demande').snapshots().map((s) {
        final retraits = [for (final d in s.docs) Retrait.depuisDocument(d.id, d.data())];
        retraits.sort((a, b) => (a.creeLe ?? DateTime(0)).compareTo(b.creeLe ?? DateTime(0)));
        return retraits;
      });

  /// Admin : retrait versé ([reference] du transfert, facultative) ou refusé ([motif] obligatoire).
  Future<void> traiter({required String retraitId, required bool verse, String reference = '', String motif = ''}) async {
    try {
      await FonctionsCloud.appeler('traiterRetrait', {
        'retraitId': retraitId,
        'decision': verse ? 'verse' : 'refuse',
        if (reference.trim().isNotEmpty) 'reference': reference.trim(),
        if (motif.trim().isNotEmpty) 'motif': motif.trim(),
      });
    } on FirebaseFunctionsException catch (e) {
      throw FonctionsCloud.versApiException(e);
    }
  }
}
