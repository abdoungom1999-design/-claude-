import 'package:cloud_firestore/cloud_firestore.dart';
import '../../courses/data/course_service.dart';

/// Note moyenne d'un chauffeur, lue dans son profil public
/// (`noteSomme` / `noteNombre`, tenus à jour par [EvaluationService]).
class NoteChauffeur {
  const NoteChauffeur({required this.somme, required this.nombre});

  final int somme;
  final int nombre;

  static NoteChauffeur depuisProfil(Map<String, dynamic>? profil) => NoteChauffeur(
        somme: (profil?['noteSomme'] as num?)?.toInt() ?? 0,
        nombre: (profil?['noteNombre'] as num?)?.toInt() ?? 0,
      );

  bool get aDesAvis => nombre > 0;

  double? get moyenne => aDesAvis ? somme / nombre : null;

  /// "4,8" (une décimale, virgule française).
  String get moyenneTexte => (moyenne ?? 0).toStringAsFixed(1).replaceAll('.', ',');

  String get nombreTexte => nombre == 1 ? '1 avis' : '$nombre avis';
}

/// Avis reçu par un chauffeur (collection `evaluations`). Anonyme : le
/// chauffeur ne voit ni le nom ni l'identité du client.
class EvaluationRecue {
  const EvaluationRecue({required this.courseId, required this.note, this.commentaire, this.creeLe});

  final String courseId;
  final int note;
  final String? commentaire;
  final DateTime? creeLe;

  static EvaluationRecue? depuisDocument(String id, Map<String, dynamic> donnees) {
    final note = donnees['note'];
    if (note is! num) return null;
    final commentaire = (donnees['commentaire'] as String?)?.trim();
    final creeLe = donnees['creeLe'];
    return EvaluationRecue(
      courseId: id,
      note: note.toInt().clamp(1, 5),
      commentaire: commentaire == null || commentaire.isEmpty ? null : commentaire,
      creeLe: creeLe is Timestamp ? creeLe.toDate() : null,
    );
  }
}

/// Course terminée que le client n'a pas encore notée.
class CourseANoter {
  const CourseANoter({required this.course, this.nomChauffeur});

  final CourseFirestore course;
  final String? nomChauffeur;
}

/// Évaluation d'un chauffeur par le client à la fin d'une course :
/// collection `evaluations` (une par course, identifiant = courseId),
/// et mise à jour de la note moyenne du chauffeur dans la même écriture
/// atomique — les règles Firestore refusent l'une sans l'autre et
/// vérifient que la moyenne n'augmente que de la note donnée.
class EvaluationService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  static const longueurMaxCommentaire = 500;

  /// Courses terminées du client sans évaluation, de la plus récente à
  /// la plus ancienne, avec le nom du chauffeur. Deux requêtes à simple
  /// égalité (aucun index composite requis), croisées ici.
  Future<List<CourseANoter>> coursesANoter(String clientId) async {
    final (courses, evaluations) = await (
      _firestore
          .collection('courses')
          .where('clientId', isEqualTo: clientId)
          .where('statut', isEqualTo: StatutCourse.terminee)
          .get(),
      _firestore.collection('evaluations').where('clientId', isEqualTo: clientId).get(),
    ).wait;
    final dejaNotees = {for (final doc in evaluations.docs) doc.id};
    final aNoter = [
      for (final doc in courses.docs)
        if (!dejaNotees.contains(doc.id)) CourseFirestore.depuisDocument(doc.id, doc.data()),
    ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final noms = <String, String?>{};
    for (final chauffeurId in {for (final c in aNoter) c.chauffeurId}.whereType<String>()) {
      try {
        final profil = await _firestore.collection('profils_publics').doc(chauffeurId).get();
        noms[chauffeurId] = profil.data()?['nom'] as String?;
      } on FirebaseException {
        noms[chauffeurId] = null;
      }
    }
    return [for (final c in aNoter) CourseANoter(course: c, nomChauffeur: noms[c.chauffeurId])];
  }

  /// Avis reçus par le chauffeur, du plus récent au plus ancien (tri
  /// local : pas d'index composite à créer).
  Stream<List<EvaluationRecue>> streamEvaluationsRecues(String chauffeurId) {
    return _firestore.collection('evaluations').where('chauffeurId', isEqualTo: chauffeurId).snapshots().map(
      (instantane) {
        final avis = [
          for (final doc in instantane.docs)
            if (EvaluationRecue.depuisDocument(doc.id, doc.data()) case final evaluation?) evaluation,
        ];
        // Sans date = tout juste envoyé (horodatage serveur en attente).
        DateTime date(EvaluationRecue e) => e.creeLe ?? DateTime(9999);
        return avis..sort((a, b) => date(b).compareTo(date(a)));
      },
    );
  }

  /// Note moyenne officielle du chauffeur (celle que voient les clients).
  Stream<NoteChauffeur> streamNoteChauffeur(String chauffeurId) {
    return _firestore
        .collection('profils_publics')
        .doc(chauffeurId)
        .snapshots()
        .map((doc) => NoteChauffeur.depuisProfil(doc.data()));
  }

  Future<bool> dejaEvaluee(String courseId) async {
    final doc = await _firestore.collection('evaluations').doc(courseId).get();
    return doc.exists;
  }

  Future<void> evaluer({
    required CourseFirestore course,
    required int note,
    String? commentaire,
  }) async {
    final chauffeurId = course.chauffeurId;
    if (chauffeurId == null) throw StateError('Course sans chauffeur');
    if (note < 1 || note > 5) throw ArgumentError.value(note, 'note');
    final texte = commentaire?.trim() ?? '';

    final lot = _firestore.batch()
      ..set(_firestore.collection('evaluations').doc(course.id), {
        'courseId': course.id,
        'chauffeurId': chauffeurId,
        'clientId': course.clientId,
        'note': note,
        if (texte.isNotEmpty)
          'commentaire': texte.length > longueurMaxCommentaire ? texte.substring(0, longueurMaxCommentaire) : texte,
        'creeLe': FieldValue.serverTimestamp(),
      })
      ..update(_firestore.collection('profils_publics').doc(chauffeurId), {
        'noteSomme': FieldValue.increment(note),
        'noteNombre': FieldValue.increment(1),
        'derniereEvaluation': course.id,
      });
    await lot.commit();
  }
}
