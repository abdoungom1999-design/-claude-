import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Un message de chat tel que stocké dans Firestore
/// (`chats/{chatId}/messages/{messageId}`).
class ChatMessageFirestore {
  const ChatMessageFirestore({
    required this.senderId,
    required this.text,
    required this.timestamp,
    this.id = '',
  });

  final String id;
  final String senderId;
  final String text;
  final DateTime timestamp;

  factory ChatMessageFirestore.depuisDocument(Map<String, dynamic> donnees, {String id = ''}) {
    final horodatage = donnees['timestamp'];
    return ChatMessageFirestore(
      id: id,
      senderId: donnees['senderId'] as String? ?? '',
      text: donnees['text'] as String? ?? '',
      // `timestamp` est un FieldValue.serverTimestamp() : encore `null`
      // côté client le temps que le serveur confirme l'écriture (juste
      // après l'envoi, avant la synchronisation). On retombe sur
      // l'heure locale actuelle pour ce court instant.
      timestamp: horodatage is Timestamp ? horodatage.toDate() : DateTime.now(),
    );
  }
}

/// Messagerie instantanée Client <-> Conducteur, basée sur Firestore.
///
/// Architecture : une collection `chats`, un document par paire
/// d'utilisateurs (identifiant déterministe, voir [chatIdEntre]),
/// chacun portant une sous-collection `messages` (`senderId`, `text`,
/// `timestamp`) écoutée en temps réel par [streamMessages]. Pas de
/// dépendance à une course particulière : le fil de discussion entre
/// deux utilisateurs reste le même d'une course à l'autre, comme sur
/// WhatsApp.
class ChatService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;

  /// Identifiant déterministe du chat entre deux utilisateurs : les
  /// deux UID triés puis joints, pour que les deux participants
  /// retrouvent toujours le même document quel que soit celui qui
  /// écrit en premier.
  String chatIdEntre(String uid1, String uid2) {
    final tries = [uid1, uid2]..sort();
    return '${tries[0]}_${tries[1]}';
  }

  /// Flux temps réel des messages d'un chat, du plus ancien au plus
  /// récent.
  Stream<List<ChatMessageFirestore>> streamMessages(String chatId) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp')
        .snapshots()
        .map(
          (instantane) => instantane.docs
              .map((doc) => ChatMessageFirestore.depuisDocument(doc.data(), id: doc.id))
              .toList(),
        );
  }

  /// Dernier message d'un chat (`null` s'il est vide), pour prévenir le
  /// chauffeur qu'un message du client est arrivé alors que la
  /// conversation n'est pas ouverte. Tri sur un seul champ : index
  /// automatique, rien à créer.
  Stream<ChatMessageFirestore?> streamDernierMessage(String chatId) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .map((instantane) {
      if (instantane.docs.isEmpty) return null;
      final doc = instantane.docs.first;
      return ChatMessageFirestore.depuisDocument(doc.data(), id: doc.id);
    });
  }

  /// Envoie un message : ajoute le document dans la sous-collection
  /// `messages`, et tient à jour les métadonnées du document `chats`
  /// parent (participants, dernier message) pour une future liste de
  /// conversations basée sur de vrais échanges.
  Future<void> envoyerMessage({
    required String chatId,
    required List<String> participants,
    required String texte,
  }) async {
    final expediteurId = _auth.currentUser?.uid;
    final contenu = texte.trim();
    if (expediteurId == null || contenu.isEmpty) return;

    final chatRef = _firestore.collection('chats').doc(chatId);
    await chatRef.set({
      'participants': participants,
      'dernierMessage': contenu,
      'misAJourLe': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await chatRef.collection('messages').add({
      'senderId': expediteurId,
      'text': contenu,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Charge le profil public (nom, téléphone, rôle) d'un utilisateur —
  /// utilisé pour l'en-tête du chat et pour récupérer le vrai numéro
  /// de téléphone de l'interlocuteur avant de lancer un appel. Lit
  /// `profils_publics` : le document `users` d'un autre utilisateur
  /// est privé (voir `firestore.rules`).
  Future<Map<String, dynamic>?> chargerProfil(String uid) async {
    final doc = await _firestore.collection('profils_publics').doc(uid).get();
    return doc.data();
  }

  /// Chauffeurs validés et non sanctionnés (`disponible`, tenu à jour
  /// par l'Admin, voir `AdminKycService`), pour peupler l'onglet
  /// Messages avec de vrais interlocuteurs (au lieu d'une liste de
  /// conversations simulées).
  Stream<List<Map<String, dynamic>>> streamConducteursDisponibles() {
    return _firestore
        .collection('profils_publics')
        .where('role', isEqualTo: 'conducteur')
        .where('disponible', isEqualTo: true)
        .snapshots()
        .map(
          (instantane) =>
              instantane.docs.map((doc) => {'uid': doc.id, ...doc.data()}).toList(),
        );
  }

  /// Flux des conversations réelles auxquelles [monUid] participe déjà
  /// (au moins un message échangé), du plus récemment actif au plus
  /// ancien — utilisé par l'onglet Messages du Conducteur pour lister
  /// les clients avec qui discuter, à la façon d'une boîte de réception
  /// WhatsApp plutôt que d'un simple annuaire.
  ///
  /// Tri fait ici plutôt que par Firestore : un `orderBy` combiné au
  /// filtre `participants` exigeait un index composite qui, tant qu'il
  /// n'était pas créé dans la Console, faisait échouer la requête — et
  /// la boîte de réception du chauffeur restait vide.
  Stream<List<Map<String, dynamic>>> streamMesChats(String monUid) {
    return _firestore
        .collection('chats')
        .where('participants', arrayContains: monUid)
        .snapshots()
        .map((instantane) => trierParActivite([
              for (final doc in instantane.docs) {'id': doc.id, ...doc.data()},
            ]));
  }

  /// Conversation la plus récemment active en premier ; celle dont
  /// l'horodatage serveur est encore en attente (message tout juste
  /// envoyé) passe devant.
  static List<Map<String, dynamic>> trierParActivite(List<Map<String, dynamic>> chats) {
    DateTime date(Map<String, dynamic> chat) {
      final valeur = chat['misAJourLe'];
      return valeur is Timestamp ? valeur.toDate() : DateTime(9999);
    }

    return chats..sort((a, b) => date(b).compareTo(date(a)));
  }
}
