import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../courses/data/course_service.dart';
import 'comptabilite.dart';

/// Lecture des flux financiers réels (courses terminées, règlements,
/// temps en ligne) et saisie des versements par l'Admin. Tout est calculé
/// dans l'app à partir de données que les règles Firestore protègent :
/// aucun solde stocké qu'un chauffeur pourrait modifier.
class FinanceService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  // --- Chauffeur -----------------------------------------------------

  Stream<List<LigneCourse>> streamCoursesChauffeur(String chauffeurId) => _courses(
        _firestore
            .collection('courses')
            .where('chauffeurId', isEqualTo: chauffeurId)
            .where('statut', isEqualTo: StatutCourse.terminee),
      );

  Stream<List<Reglement>> streamReglementsChauffeur(String chauffeurId) =>
      _reglements(_firestore.collection('reglements').where('chauffeurId', isEqualTo: chauffeurId));

  /// Secondes en ligne par jour ("AAAA-MM-JJ").
  Stream<Map<String, int>> streamTempsEnLigne(String chauffeurId) {
    return _firestore.collection('temps_en_ligne').where('chauffeurId', isEqualTo: chauffeurId).snapshots().map(
          (instantane) => {
            for (final doc in instantane.docs)
              if (doc.data()['date'] is String) doc.data()['date'] as String: (doc.data()['secondes'] as num? ?? 0).toInt(),
          },
        );
  }

  // --- Admin ---------------------------------------------------------

  Stream<List<LigneCourse>> streamToutesCourses() =>
      _courses(_firestore.collection('courses').where('statut', isEqualTo: StatutCourse.terminee));

  Stream<List<Reglement>> streamTousReglements() => _reglements(_firestore.collection('reglements'));

  Future<void> enregistrerVersement({
    required String chauffeurId,
    required int montantFcfa,
    String? note,
  }) {
    return _firestore.collection('reglements').add({
      'chauffeurId': chauffeurId,
      'montantFcfa': montantFcfa,
      'sens': Reglement.sensVersement,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      'creeLe': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<LigneCourse>> _courses(Query<Map<String, dynamic>> requete) => requete.snapshots().map(
        (instantane) => [
          for (final doc in instantane.docs) LigneCourse.depuisCourse(CourseFirestore.depuisDocument(doc.id, doc.data())),
        ],
      );

  Stream<List<Reglement>> _reglements(Query<Map<String, dynamic>> requete) => requete.snapshots().map(
        (instantane) => [
          for (final doc in instantane.docs)
            // Seuls les versements de Sprint au chauffeur comptent.
            if (doc.data()['montantFcfa'] is num &&
                (doc.data()['sens'] ?? Reglement.sensVersement) == Reglement.sensVersement)
              Reglement(
                id: doc.id,
                chauffeurId: doc.data()['chauffeurId'] as String? ?? '',
                montantFcfa: (doc.data()['montantFcfa'] as num).toInt(),
                note: doc.data()['note'] as String?,
                date: doc.data()['creeLe'] is Timestamp ? (doc.data()['creeLe'] as Timestamp).toDate() : DateTime.now(),
              ),
        ],
      );
}

/// Compte le temps passé "En ligne" : +60 s par minute dans
/// `temps_en_ligne/{uid}_{AAAA-MM-JJ}` (les règles refusent tout autre
/// incrément). Démarré et arrêté avec l'envoi de position.
class TempsEnLigneService {
  Timer? _minuteur;

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  void demarrer(String chauffeurId) {
    _minuteur?.cancel();
    _minuteur = Timer.periodic(const Duration(seconds: 60), (_) => _compterUneMinute(chauffeurId));
  }

  void arreter() {
    _minuteur?.cancel();
    _minuteur = null;
  }

  Future<void> _compterUneMinute(String chauffeurId) async {
    final date = Periodes.cleJour(DateTime.now());
    final ref = _firestore.collection('temps_en_ligne').doc('${chauffeurId}_$date');
    try {
      await ref.update({'secondes': FieldValue.increment(60), 'majLe': FieldValue.serverTimestamp()});
    } on FirebaseException catch (e) {
      if (e.code != 'not-found') return;
      try {
        await ref.set({
          'chauffeurId': chauffeurId,
          'date': date,
          'secondes': 60,
          'majLe': FieldValue.serverTimestamp(),
        });
      } on FirebaseException {
        // Hors connexion : la minute est perdue, sans conséquence.
      }
    }
  }
}
