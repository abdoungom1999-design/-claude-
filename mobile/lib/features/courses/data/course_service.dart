import 'package:cloud_firestore/cloud_firestore.dart';

/// Une course telle que stockée dans Firestore (collection `courses`).
///
/// Cycle de vie du champ [statut] : `en_attente` (créée par le client,
/// en attente d'un chauffeur) -> `acceptee` (un chauffeur a accepté,
/// voir [CourseService.accepterCourse]) -> `en_cours` -> `terminee`,
/// ou `annulee` à tout moment avant `terminee`. Seules `en_attente`,
/// `acceptee` et `annulee` sont pilotées par le code actuel ; `en_cours`
/// et `terminee` sont prévus pour la suite du parcours (prise en
/// charge, fin de course), pas encore déclenchés automatiquement.
class CourseFirestore {
  const CourseFirestore({
    required this.id,
    required this.clientId,
    required this.chauffeurId,
    required this.statut,
    required this.type,
    required this.adresseDepart,
    required this.adresseArrivee,
    required this.prixFcfa,
    required this.timestamp,
  });

  final String id;
  final String clientId;
  final String? chauffeurId;
  final String statut;
  final String type;
  final String adresseDepart;
  final String adresseArrivee;
  final int prixFcfa;
  final DateTime timestamp;

  factory CourseFirestore.depuisDocument(String id, Map<String, dynamic> donnees) {
    final horodatage = donnees['timestamp'];
    return CourseFirestore(
      id: id,
      clientId: donnees['clientId'] as String? ?? '',
      chauffeurId: donnees['chauffeurId'] as String?,
      statut: donnees['statut'] as String? ?? 'en_attente',
      type: donnees['type'] as String? ?? 'PASSAGER',
      adresseDepart: donnees['adresseDepart'] as String? ?? '',
      adresseArrivee: donnees['adresseArrivee'] as String? ?? '',
      prixFcfa: (donnees['prixFcfa'] as num?)?.toInt() ?? 0,
      // `timestamp` est un FieldValue.serverTimestamp() : encore `null`
      // côté client le temps que le serveur confirme l'écriture.
      timestamp: horodatage is Timestamp ? horodatage.toDate() : DateTime.now(),
    );
  }
}

/// Matchmaking Client <-> Conducteur en temps réel, basé sur Firestore :
/// une collection `courses` à plat (pas de sous-collection), chaque
/// document représentant une demande de course. Le client en crée une
/// et écoute son évolution ([streamCourse]) ; tout chauffeur en ligne
/// écoute la collection filtrée sur `statut == 'en_attente'`
/// ([streamCoursesEnAttente]) et peut l'accepter ([accepterCourse]),
/// sous transaction pour qu'un seul des chauffeurs qui tentent
/// d'accepter en même temps gagne la course.
class CourseService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _courses => _firestore.collection('courses');

  /// Crée une nouvelle demande de course (`statut: en_attente`,
  /// `chauffeurId: null`) et retourne son id.
  Future<String> creerCourse({
    required String clientId,
    required String type,
    required String adresseDepart,
    required String adresseArrivee,
    required int prixFcfa,
  }) async {
    final doc = await _courses.add({
      'clientId': clientId,
      'chauffeurId': null,
      'statut': 'en_attente',
      'type': type,
      'adresseDepart': adresseDepart,
      'adresseArrivee': adresseArrivee,
      'prixFcfa': prixFcfa,
      'timestamp': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  /// Flux temps réel d'une course précise (écran client "Recherche
  /// d'un chauffeur" / "Votre chauffeur arrive") — `null` si le
  /// document n'existe pas ou plus.
  Stream<CourseFirestore?> streamCourse(String courseId) {
    return _courses.doc(courseId).snapshots().map((doc) {
      final donnees = doc.data();
      if (!doc.exists || donnees == null) return null;
      return CourseFirestore.depuisDocument(doc.id, donnees);
    });
  }

  /// Flux temps réel de toutes les courses en attente d'un chauffeur,
  /// de la plus ancienne à la plus récente — écouté en continu par
  /// chaque chauffeur en ligne (le "radar").
  ///
  /// Important : ce filtre (égalité sur `statut` + tri sur
  /// `timestamp`) nécessite un index composite Firestore. Au premier
  /// lancement, Firestore refuse la requête avec une erreur
  /// `failed-precondition` contenant un lien direct pour créer cet
  /// index en un clic dans la Console Firebase — il faut le créer une
  /// fois (quelques minutes de construction), après quoi la requête
  /// fonctionne normalement.
  Stream<List<CourseFirestore>> streamCoursesEnAttente() {
    return _courses
        .where('statut', isEqualTo: 'en_attente')
        .orderBy('timestamp')
        .snapshots()
        .map(
          (instantane) => instantane.docs
              .map((doc) => CourseFirestore.depuisDocument(doc.id, doc.data()))
              .toList(),
        );
  }

  /// Un chauffeur accepte une course. Passe par une transaction pour
  /// garantir qu'un seul chauffeur gagne si plusieurs tentent
  /// d'accepter la même course au même instant : la transaction relit
  /// le document, et n'écrit que si `statut` est toujours
  /// `en_attente` — sinon elle échoue et cette méthode retourne
  /// `false` (course déjà prise par quelqu'un d'autre).
  Future<bool> accepterCourse({required String courseId, required String chauffeurId}) async {
    final courseRef = _courses.doc(courseId);
    try {
      return await _firestore.runTransaction<bool>((transaction) async {
        final instantane = await transaction.get(courseRef);
        final donnees = instantane.data();
        if (!instantane.exists || donnees == null || donnees['statut'] != 'en_attente') {
          return false;
        }
        transaction.update(courseRef, {'chauffeurId': chauffeurId, 'statut': 'acceptee'});
        return true;
      });
    } catch (_) {
      return false;
    }
  }

  /// Annule une course encore en attente (bouton "Annuler la demande"
  /// côté client).
  Future<void> annulerCourse(String courseId) {
    return _courses.doc(courseId).update({'statut': 'annulee'});
  }
}
