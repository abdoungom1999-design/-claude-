import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../../core/firebase/fonctions_cloud.dart';
import '../../courses/data/course_service.dart';

/// Motif d'un signalement (valeurs acceptées par `firestore.rules`).
abstract final class CategorieTicket {
  static const chauffeur = 'chauffeur';
  static const prix = 'prix';
  static const objetPerdu = 'objet_perdu';
  static const securite = 'securite';
  static const autre = 'autre';

  static const toutes = [chauffeur, prix, objetPerdu, securite, autre];

  static String libelle(String categorie) => switch (categorie) {
        chauffeur => 'Problème avec le chauffeur',
        prix => 'Prix ou paiement',
        objetPerdu => 'Objet perdu',
        securite => 'Sécurité',
        _ => 'Autre problème',
      };
}

abstract final class StatutTicket {
  static const ouvert = 'ouvert';
  static const resolu = 'resolu';
}

/// Signalement d'un client sur une de ses courses (collection `tickets`,
/// identifiant = courseId : un seul ticket par course).
class TicketSupport {
  const TicketSupport({
    required this.courseId,
    required this.clientId,
    required this.chauffeurId,
    required this.categorie,
    required this.statut,
    required this.creeLe,
    required this.majLe,
    required this.dernierMessage,
    required this.nonLuAdmin,
    required this.nonLuClient,
  });

  final String courseId;
  final String clientId;
  final String? chauffeurId;
  final String categorie;
  final String statut;
  final DateTime creeLe;
  final DateTime majLe;
  final String dernierMessage;
  final bool nonLuAdmin;
  final bool nonLuClient;

  bool get estResolu => statut == StatutTicket.resolu;

  factory TicketSupport.depuisDocument(String id, Map<String, dynamic> d) => TicketSupport(
        courseId: id,
        clientId: d['clientId'] as String? ?? '',
        chauffeurId: d['chauffeurId'] as String?,
        categorie: d['categorie'] as String? ?? CategorieTicket.autre,
        statut: d['statut'] as String? ?? StatutTicket.ouvert,
        creeLe: _date(d['creeLe']),
        majLe: _date(d['majLe']),
        dernierMessage: d['dernierMessage'] as String? ?? '',
        nonLuAdmin: d['nonLuAdmin'] == true,
        nonLuClient: d['nonLuClient'] == true,
      );
}

/// Qui a écrit un message de ticket.
abstract final class AuteurMessage {
  static const client = 'client';
  static const admin = 'admin';

  /// Message automatique du serveur (ex. remboursement effectué).
  static const systeme = 'systeme';
}

class MessageTicket {
  const MessageTicket({
    required this.id,
    required this.auteurId,
    required this.auteurRole,
    required this.texte,
    required this.creeLe,
  });

  final String id;
  final String auteurId;
  final String auteurRole;
  final String texte;
  final DateTime creeLe;

  factory MessageTicket.depuisDocument(String id, Map<String, dynamic> d) => MessageTicket(
        id: id,
        auteurId: d['auteurId'] as String? ?? '',
        auteurRole: d['auteurRole'] as String? ?? AuteurMessage.client,
        texte: d['texte'] as String? ?? '',
        creeLe: _date(d['creeLe']),
      );
}

/// `serverTimestamp()` vaut `null` localement le temps que le serveur
/// confirme l'écriture : on affiche alors l'heure actuelle.
DateTime _date(Object? valeur) => valeur is Timestamp ? valeur.toDate() : DateTime.now();

/// Résultat d'un remboursement demandé par l'Admin.
class RemboursementEffectue {
  const RemboursementEffectue({required this.rembourse, required this.montantFcfa, this.partChauffeurRetireeFcfa = 0});

  final bool rembourse;
  final int montantFcfa;

  /// Part du chauffeur retirée de ce que Sprint lui doit.
  final int partChauffeurRetireeFcfa;
}

/// Support client : signalements ("Signaler un problème" depuis
/// l'historique) et leur traitement par l'Admin. Conversation dans
/// `tickets/{courseId}/messages` ; remboursement et sanction passent par
/// les Cloud Functions (`rembourserCourseAdmin`, `sanctionnerCompte`).
class SupportService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  static const longueurMaxMessage = 1000;

  DocumentReference<Map<String, dynamic>> _ticket(String courseId) =>
      _firestore.collection('tickets').doc(courseId);

  /// Ticket de la course, ou `null` s'il n'y en a pas encore.
  Stream<TicketSupport?> streamTicket(String courseId) {
    return _ticket(courseId).snapshots().map((doc) {
      final donnees = doc.data();
      return donnees == null ? null : TicketSupport.depuisDocument(doc.id, donnees);
    });
  }

  /// Conversation, du plus ancien au plus récent message.
  Stream<List<MessageTicket>> streamMessages(String courseId) {
    return _ticket(courseId).collection('messages').orderBy('creeLe').snapshots().map(
          (instantane) => [
            for (final doc in instantane.docs) MessageTicket.depuisDocument(doc.id, doc.data()),
          ],
        );
  }

  static String _apercu(String texte) => texte.length <= 200 ? texte : '${texte.substring(0, 197)}...';

  /// Ouvre le ticket de [course] avec le premier message du client, dans
  /// la même écriture.
  Future<void> ouvrirTicket({
    required CourseFirestore course,
    required String clientId,
    required String categorie,
    required String texte,
  }) {
    final batch = _firestore.batch();
    final ticket = _ticket(course.id);
    batch.set(ticket, {
      'courseId': course.id,
      'clientId': clientId,
      'chauffeurId': course.chauffeurId,
      'categorie': categorie,
      'statut': StatutTicket.ouvert,
      'creeLe': FieldValue.serverTimestamp(),
      'majLe': FieldValue.serverTimestamp(),
      'dernierMessage': _apercu(texte),
      'nonLuAdmin': true,
      'nonLuClient': false,
    });
    batch.set(ticket.collection('messages').doc(), _message(clientId, AuteurMessage.client, texte));
    return batch.commit();
  }

  Map<String, dynamic> _message(String auteurId, String role, String texte) => {
        'auteurId': auteurId,
        'auteurRole': role,
        'texte': texte,
        'creeLe': FieldValue.serverTimestamp(),
      };

  /// Réponse du client ; rouvre le ticket s'il était résolu.
  Future<void> envoyerMessageClient(String courseId, String clientId, String texte) {
    final batch = _firestore.batch();
    final ticket = _ticket(courseId);
    batch.set(ticket.collection('messages').doc(), _message(clientId, AuteurMessage.client, texte));
    batch.update(ticket, {
      'majLe': FieldValue.serverTimestamp(),
      'dernierMessage': _apercu(texte),
      'nonLuAdmin': true,
      'nonLuClient': false,
      'statut': StatutTicket.ouvert,
    });
    return batch.commit();
  }

  Future<void> marquerLuParClient(String courseId) => _ticket(courseId).update({'nonLuClient': false});

  // --- Admin -----------------------------------------------------------

  /// File des tickets, les plus récemment actifs d'abord (tri simple :
  /// pas d'index composite).
  Stream<List<TicketSupport>> streamTickets() {
    return _firestore.collection('tickets').orderBy('majLe', descending: true).limit(300).snapshots().map(
          (instantane) => [
            for (final doc in instantane.docs) TicketSupport.depuisDocument(doc.id, doc.data()),
          ],
        );
  }

  Future<void> envoyerMessageAdmin(String courseId, String adminId, String texte) {
    final batch = _firestore.batch();
    final ticket = _ticket(courseId);
    batch.set(ticket.collection('messages').doc(), _message(adminId, AuteurMessage.admin, texte));
    batch.update(ticket, {
      'majLe': FieldValue.serverTimestamp(),
      'dernierMessage': _apercu(texte),
      'nonLuAdmin': false,
      'nonLuClient': true,
    });
    return batch.commit();
  }

  Future<void> marquerLuParAdmin(String courseId) => _ticket(courseId).update({'nonLuAdmin': false});

  Future<void> definirStatut(String courseId, String statut) =>
      _ticket(courseId).update({'statut': statut, 'nonLuAdmin': false});

  /// Remboursement intégral de la course par le serveur (fournisseur de
  /// paiement), tracé dans le journal Admin.
  Future<RemboursementEffectue> rembourser(String courseId, String motif) async {
    try {
      final r = await FonctionsCloud.appeler('rembourserCourseAdmin', {'courseId': courseId, 'motif': motif});
      return RemboursementEffectue(
        rembourse: r['rembourse'] == true,
        montantFcfa: (r['montantFcfa'] as num?)?.toInt() ?? 0,
        partChauffeurRetireeFcfa: (r['partChauffeurRetireeFcfa'] as num?)?.toInt() ?? 0,
      );
    } on FirebaseFunctionsException catch (e) {
      throw FonctionsCloud.versApiException(e);
    }
  }
}
