import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Un message de chat tel que stocké dans Firestore
/// (`chats/{chatId}/messages/{messageId}`).
class ChatMessageFirestore {
  const ChatMessageFirestore({
    required this.senderId,
    required this.text,
    required this.timestamp,
  });

  final String senderId;
  final String text;
  final DateTime timestamp;

  factory ChatMessageFirestore.depuisDocument(Map<String, dynamic> donnees) {
    final horodatage = donnees['timestamp'];
    return ChatMessageFirestore(
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
              .map((doc) => ChatMessageFirestore.depuisDocument(doc.data()))
              .toList(),
        );
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

  /// Charge le profil Firestore (nom, téléphone…) d'un utilisateur —
  /// utilisé pour l'en-tête du chat et pour récupérer le vrai numéro
  /// de téléphone de l'interlocuteur avant de lancer un appel.
  Future<Map<String, dynamic>?> chargerProfil(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    return doc.data();
  }

  /// Chauffeurs dont le dossier a été validé, pour peupler l'onglet
  /// Messages avec de vrais interlocuteurs (au lieu d'une liste de
  /// conversations simulées).
  Stream<List<Map<String, dynamic>>> streamConducteursDisponibles() {
    return _firestore
        .collection('users')
        .where('role', isEqualTo: 'conducteur')
        .where('estValide', isEqualTo: true)
        .snapshots()
        .map(
          (instantane) =>
              instantane.docs.map((doc) => {'uid': doc.id, ...doc.data()}).toList(),
        );
  }
}
