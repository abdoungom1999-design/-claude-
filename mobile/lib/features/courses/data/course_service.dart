import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../../core/firebase/fonctions_cloud.dart';
import '../../../core/utils/flux_repris.dart';
import '../../conducteur/data/position_chauffeur_service.dart';
import 'position_chauffeur.dart';

/// Une course telle que stockée dans Firestore (collection `courses`).
///
/// Cycle de vie du champ [statut] : `en_attente` (créée par le serveur
/// une fois le paiement confirmé, en attente d'un chauffeur) ->
/// `acceptee` (un chauffeur a accepté, voir
/// [CourseService.accepterCourse]) -> `en_cours` -> `terminee`, ou
/// `annulee` (par le client tant qu'elle est `en_attente`, par le
/// chauffeur, ou par le serveur faute de chauffeur, toujours avec
/// remboursement). `en_cours` (client à bord) et `terminee` sont
/// déclenchés par le chauffeur attribué (voir
/// [CourseService.demarrerCourse] et [CourseService.terminerCourse]).
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
    required this.methodePaiement,
    required this.timestamp,
    this.points,
    this.annuleePar,
    this.motifAnnulation,
    this.termineeLe,
    this.commissionFcfa,
    this.commandeId,
    this.rembourseeLe,
  });

  final String id;
  final String clientId;
  final String? chauffeurId;
  final String statut;
  final String type;
  final String adresseDepart;
  final String adresseArrivee;
  final int prixFcfa;
  final String methodePaiement;
  final DateTime timestamp;

  /// Coordonnées GPS du départ et de l'arrivée ; `null` pour les courses
  /// créées avant leur enregistrement (pas de temps d'approche alors).
  final PointsCourse? points;

  /// `'client'`, `'chauffeur'` (voir [CourseService.annulerParChauffeur])
  /// ou `'systeme'` (aucun chauffeur à temps) ; `null` sinon.
  final String? annuleePar;

  /// Voir [MotifAnnulation].
  final String? motifAnnulation;

  /// Heure d'arrivée (courses terminées depuis la gestion financière).
  final DateTime? termineeLe;

  /// Commission de la plateforme figée à la fin de la course (voir
  /// `Commission`) ; `null` pour les courses terminées avant.
  final int? commissionFcfa;

  /// Commande de paiement d'origine ; `null` pour les courses créées
  /// avant le paiement par le serveur. Une course annulée qui en a une
  /// est remboursée par le serveur.
  final String? commandeId;

  bool get estRemboursable => commandeId != null;

  /// Remboursement intégral accordé par le support (voir la Cloud
  /// Function `rembourserCourseAdmin`) ; `null` sinon.
  final DateTime? rembourseeLe;

  /// Libellé du statut pour le client.
  String get libelleStatut => switch (statut) {
        StatutCourse.enAttente => "Recherche d'un chauffeur",
        StatutCourse.acceptee => 'Chauffeur en route',
        StatutCourse.enCours => 'En cours',
        StatutCourse.terminee => 'Terminée',
        StatutCourse.annulee => 'Annulée',
        _ => statut,
      };

  bool get estActive =>
      statut == StatutCourse.enAttente || statut == StatutCourse.acceptee || statut == StatutCourse.enCours;

  /// "Déjà payé par Wave" / "Déjà payé par Orange Money" : 100 % mobile
  /// money, le chauffeur n'encaisse jamais rien.
  String get libellePaiement => switch (methodePaiement) {
        'WAVE' => 'Déjà payé par Wave',
        'ORANGE_MONEY' => 'Déjà payé par Orange Money',
        _ => 'Paiement dans l\'app',
      };

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
      methodePaiement: donnees['methodePaiement'] as String? ?? '',
      // `timestamp` est un FieldValue.serverTimestamp() : encore `null`
      // côté client le temps que le serveur confirme l'écriture.
      timestamp: horodatage is Timestamp ? horodatage.toDate() : DateTime.now(),
      points: PointsCourse.depuisDocument(donnees),
      annuleePar: donnees['annuleePar'] as String?,
      motifAnnulation: donnees['motifAnnulation'] as String?,
      termineeLe: donnees['termineeLe'] is Timestamp ? (donnees['termineeLe'] as Timestamp).toDate() : null,
      commissionFcfa: (donnees['commissionFcfa'] as num?)?.toInt(),
      commandeId: donnees['commandeId'] as String?,
      rembourseeLe: donnees['rembourseeLe'] is Timestamp ? (donnees['rembourseeLe'] as Timestamp).toDate() : null,
    );
  }
}

/// Coordonnées GPS du trajet, enregistrées à la création de la course
/// pour le suivi d'approche côté client.
class PointsCourse {
  const PointsCourse({
    required this.latitudeDepart,
    required this.longitudeDepart,
    required this.latitudeArrivee,
    required this.longitudeArrivee,
  });

  final double latitudeDepart;
  final double longitudeDepart;
  final double latitudeArrivee;
  final double longitudeArrivee;

  /// Départ et arrivée au format attendu par les Cloud Functions.
  Map<String, dynamic> versServeur() => {
        'depart': {'latitude': latitudeDepart, 'longitude': longitudeDepart},
        'arrivee': {'latitude': latitudeArrivee, 'longitude': longitudeArrivee},
      };

  Map<String, double> versDocument() => {
        'latitudeDepart': latitudeDepart,
        'longitudeDepart': longitudeDepart,
        'latitudeArrivee': latitudeArrivee,
        'longitudeArrivee': longitudeArrivee,
      };

  static PointsCourse? depuisDocument(Map<String, dynamic> donnees) {
    final valeurs = [
      donnees['latitudeDepart'],
      donnees['longitudeDepart'],
      donnees['latitudeArrivee'],
      donnees['longitudeArrivee'],
    ];
    if (valeurs.any((v) => v is! num)) return null;
    return PointsCourse(
      latitudeDepart: (valeurs[0] as num).toDouble(),
      longitudeDepart: (valeurs[1] as num).toDouble(),
      latitudeArrivee: (valeurs[2] as num).toDouble(),
      longitudeArrivee: (valeurs[3] as num).toDouble(),
    );
  }
}

/// Valeurs du champ `statut` d'une course (voir [CourseFirestore]).
abstract final class StatutCourse {
  static const enAttente = 'en_attente';
  static const acceptee = 'acceptee';
  static const enCours = 'en_cours';
  static const terminee = 'terminee';
  static const annulee = 'annulee';

  /// Un chauffeur est attribué et la course n'est pas finie.
  static const actifs = [acceptee, enCours];
}

/// Le serveur a refusé la commande : le prix du trajet a changé depuis
/// son affichage (passage en heure de pointe ou en tarif de nuit).
class PrixModifie implements Exception {
  const PrixModifie(this.nouveauPrixFcfa);

  final int nouveauPrixFcfa;
}

/// Lien de paiement renvoyé par le serveur ([CourseService.creerPaiement]).
class DemandePaiement {
  const DemandePaiement({required this.commandeId, required this.lienPaiement, required this.prixFcfa});

  final String commandeId;
  final Uri lienPaiement;
  final int prixFcfa;
}

/// Commande de paiement (collection `commandes`, écrite par le serveur).
class CommandePaiement {
  const CommandePaiement({required this.statut, this.courseId});

  final String statut;

  /// Course créée par le serveur, une fois le paiement confirmé.
  final String? courseId;
}

/// Valeurs du champ `statut` d'une commande (voir `functions/src/paiements.ts`).
abstract final class StatutCommande {
  static const enAttente = 'en_attente_paiement';
  static const payee = 'payee';
  static const echouee = 'echouee';
  static const expiree = 'expiree';
}

/// Commission de la plateforme sur chaque course terminée : 15 % du
/// prix, arrondi à l'inférieur. Même formule que `firestore.rules`
/// (`math.floor(prixFcfa * 15 / 100)`), qui la fait respecter.
abstract final class Commission {
  static const pourcentage = 15;

  static int de(int prixFcfa) => (prixFcfa * pourcentage) ~/ 100;
}

/// Liaison chauffeur <-> client (`liaisons/{clientId}_{chauffeurId}`) :
/// écrite par le chauffeur dans la même transaction que l'acceptation, et
/// vérifiée contre la course par `firestore.rules`. Elle seule ouvre, tant
/// que la course est en cours, la lecture du profil de l'autre partie
/// (nom, véhicule, plaque, téléphone) et la messagerie : personne n'a
/// accès à la liste des chauffeurs ni des clients.
abstract final class Liaison {
  static String id({required String clientId, required String chauffeurId}) => '${clientId}_$chauffeurId';

  static Map<String, Object?> donnees({
    required String clientId,
    required String chauffeurId,
    required String courseId,
  }) =>
      {
        'clientId': clientId,
        'chauffeurId': chauffeurId,
        'courseId': courseId,
        'creeLe': FieldValue.serverTimestamp(),
      };
}

/// Motif d'annulation d'une course par le chauffeur (valeurs acceptées
/// par la Cloud Function `annulerCourse`), ou par le serveur
/// ([aucunChauffeur]).
abstract final class MotifAnnulation {
  static const clientIntrouvable = 'client_introuvable';
  static const panne = 'panne';
  static const autre = 'autre';

  static const tous = [clientIntrouvable, panne, autre];

  /// Personne n'a accepté la course à temps : le serveur l'annule.
  static const aucunChauffeur = 'aucun_chauffeur';

  /// Chauffeur suspendu par l'Admin pendant la course : le serveur
  /// l'annule et rembourse le client.
  static const chauffeurSuspendu = 'chauffeur_suspendu';

  /// Libellé pour le chauffeur.
  static String libelle(String motif) => switch (motif) {
        clientIntrouvable => 'Client introuvable',
        panne => 'Panne ou problème de véhicule',
        _ => 'Autre raison',
      };

  /// Explication montrée au client.
  static String pourLeClient(String? motif) => switch (motif) {
        clientIntrouvable => 'Votre chauffeur ne vous a pas trouvé au point de départ et a annulé la course.',
        panne => 'Votre chauffeur a eu un problème avec son véhicule et a dû annuler la course.',
        _ => 'Votre chauffeur a dû annuler la course.',
      };
}

/// Matchmaking Client <-> Conducteur en temps réel, basé sur Firestore :
/// une collection `courses` à plat (pas de sous-collection), chaque
/// document représentant une demande de course. Le client la paie (le
/// serveur la crée alors, voir [creerPaiement]) et écoute son évolution
/// ([streamCourse]) ; tout chauffeur en ligne écoute la collection
/// filtrée sur `statut == 'en_attente'`
/// ([streamCoursesEnAttente]) et peut l'accepter ([accepterCourse]),
/// sous transaction pour qu'un seul des chauffeurs qui tentent
/// d'accepter en même temps gagne la course.
class CourseService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _courses => _firestore.collection('courses');

  /// Demande de paiement : le serveur (Cloud Function `creerPaiement`)
  /// recalcule le prix, enregistre une commande en attente et renvoie le
  /// lien de paiement (Wave). La course n'existera qu'une fois le
  /// paiement confirmé au serveur par l'opérateur. [prixFcfa] (le prix
  /// montré au client) ne sert qu'à vérifier qu'il n'a pas changé
  /// entre-temps, sinon [PrixModifie].
  Future<DemandePaiement> creerPaiement({
    required String type,
    required String adresseDepart,
    required String adresseArrivee,
    required int prixFcfa,
    required String methodePaiement,
    required PointsCourse points,
  }) async {
    try {
      final resultat = await FonctionsCloud.appeler('creerPaiement', {
        'type': type,
        ...points.versServeur(),
        'adresseDepart': adresseDepart,
        'adresseArrivee': adresseArrivee,
        'methodePaiement': methodePaiement,
        'prixAttendu': prixFcfa,
      });
      return DemandePaiement(
        commandeId: resultat['commandeId'] as String,
        lienPaiement: Uri.parse(resultat['lienPaiement'] as String),
        prixFcfa: (resultat['prixFcfa'] as num).toInt(),
      );
    } on FirebaseFunctionsException catch (e) {
      final details = e.details;
      if (e.code == 'failed-precondition' && details is Map && details['raison'] == 'prix-modifie') {
        throw PrixModifie((details['prixFcfa'] as num).toInt());
      }
      throw FonctionsCloud.versApiException(e);
    }
  }

  /// Suivi temps réel d'une commande pendant que le client paie : passe à
  /// `payee` (avec l'id de la course créée) dès que l'opérateur confirme.
  Stream<CommandePaiement?> streamCommande(String commandeId) {
    return _firestore.collection('commandes').doc(commandeId).snapshots().map((doc) {
      final donnees = doc.data();
      if (!doc.exists || donnees == null) return null;
      return CommandePaiement(
        statut: donnees['statut'] as String? ?? StatutCommande.enAttente,
        courseId: donnees['courseId'] as String?,
      );
    });
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

  /// Courses du client (historique de l'onglet Activité), de la plus
  /// récente à la plus ancienne. Filtre d'égalité seul, tri local : pas
  /// d'index composite à créer.
  Stream<List<CourseFirestore>> streamCoursesClient(String clientId) {
    return _courses.where('clientId', isEqualTo: clientId).snapshots().map(
          (instantane) => instantane.docs
              .map((doc) => CourseFirestore.depuisDocument(doc.id, doc.data()))
              .toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp)),
        );
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
        final clientId = donnees['clientId'];
        if (clientId is! String) return false;
        transaction.update(courseRef, {'chauffeurId': chauffeurId, 'statut': 'acceptee'});
        // La liaison naît avec l'acceptation : sans elle, le client ne
        // pourrait ni voir son chauffeur ni lui écrire.
        transaction.set(
          _firestore.collection('liaisons').doc(Liaison.id(clientId: clientId, chauffeurId: chauffeurId)),
          Liaison.donnees(clientId: clientId, chauffeurId: chauffeurId, courseId: courseId),
        );
        return true;
      });
    } catch (_) {
      return false;
    }
  }

  /// Course attribuée à ce chauffeur et pas encore terminée (`acceptee`
  /// ou `en_cours`), la plus récente d'abord ; `null` s'il n'en a pas.
  Stream<CourseFirestore?> streamCourseActiveChauffeur(String chauffeurId) {
    return _courses
        .where('chauffeurId', isEqualTo: chauffeurId)
        .where('statut', whereIn: StatutCourse.actifs)
        .snapshots()
        .map((instantane) {
      final courses = instantane.docs
          .map((doc) => CourseFirestore.depuisDocument(doc.id, doc.data()))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return courses.isEmpty ? null : courses.first;
    });
  }

  /// Toutes les courses en cours (`acceptee` ou `en_cours`), pour la
  /// carte "Courses en direct" de l'Admin. Pas de tri côté Firestore :
  /// un filtre `in` seul ne nécessite pas d'index composite.
  Stream<List<CourseFirestore>> streamCoursesEnCours() {
    return _courses.where('statut', whereIn: StatutCourse.actifs).snapshots().map(
          (instantane) => instantane.docs
              .map((doc) => CourseFirestore.depuisDocument(doc.id, doc.data()))
              .toList()
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp)),
        );
  }

  /// Position en temps réel du chauffeur attribué, pour le client
  /// pendant sa course (suivi d'approche). `null` tant que le chauffeur
  /// n'a rien publié ou s'il est passé hors ligne. Les règles Firestore
  /// ne l'autorisent qu'au client d'une course `acceptee` ou `en_cours`
  /// avec ce chauffeur.
  ///
  /// La position est EXACTE (jamais arrondie : l'arrondi à ~150 m ne
  /// concerne que les motos anonymes de la carte des autres clients). Une
  /// lecture refusée (course pas encore visible des règles, réseau) est
  /// retentée toute seule, voir [fluxRepris].
  Stream<PositionChauffeurDirect?> streamPositionChauffeur(String chauffeurId) {
    return fluxRepris(
      () => _firestore
          .collection(PositionChauffeurService.collection)
          .doc(chauffeurId)
          .snapshots()
          .map((doc) {
        final donnees = doc.data();
        return donnees == null ? null : PositionChauffeurDirect.depuisDocument(doc.id, donnees);
      }),
    );
  }

  /// Le chauffeur a récupéré son client (ou le colis) : `acceptee` ->
  /// `en_cours`.
  Future<void> demarrerCourse(String courseId) {
    return _courses.doc(courseId).update({'statut': StatutCourse.enCours});
  }

  /// Arrivée à destination : `en_cours` -> `terminee`, avec l'heure de
  /// fin et la commission de la plateforme figée (les règles Firestore
  /// vérifient qu'elle vaut exactement [Commission.de] du prix).
  Future<void> terminerCourse(CourseFirestore course) {
    return _courses.doc(course.id).update({
      'statut': StatutCourse.terminee,
      'termineeLe': FieldValue.serverTimestamp(),
      'commissionFcfa': Commission.de(course.prixFcfa),
    });
  }

  /// Le chauffeur attribué annule sa course (client introuvable,
  /// panne…) : elle quitte son bandeau de course active et il peut de
  /// nouveau recevoir des demandes ; le client voit le motif et il est
  /// remboursé (Cloud Function `annulerCourse`).
  Future<void> annulerParChauffeur(String courseId, String motif) {
    return _annulerParLeServeur({'courseId': courseId, 'motif': motif});
  }

  /// Annule une course encore en attente (bouton "Annuler la demande"
  /// côté client) ; le client est remboursé (Cloud Function
  /// `annulerCourse`).
  Future<void> annulerCourse(String courseId) {
    return _annulerParLeServeur({'courseId': courseId});
  }

  Future<void> _annulerParLeServeur(Map<String, dynamic> donnees) async {
    try {
      await FonctionsCloud.appeler('annulerCourse', donnees);
    } on FirebaseFunctionsException catch (e) {
      throw FonctionsCloud.versApiException(e);
    }
  }
}
