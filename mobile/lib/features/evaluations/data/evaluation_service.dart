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

/// Évaluation d'un chauffeur par le client à la fin d'une course :
/// collection `evaluations` (une par course, identifiant = courseId),
/// et mise à jour de la note moyenne du chauffeur dans la même écriture
/// atomique — les règles Firestore refusent l'une sans l'autre et
/// vérifient que la moyenne n'augmente que de la note donnée.
class EvaluationService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  static const longueurMaxCommentaire = 500;

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
