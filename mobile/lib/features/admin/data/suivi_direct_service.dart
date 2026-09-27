import 'package:cloud_firestore/cloud_firestore.dart';
import '../../conducteur/data/position_chauffeur_service.dart';
import '../../courses/data/course_service.dart';
import '../../courses/data/position_chauffeur.dart';

export '../../courses/data/position_chauffeur.dart';


/// Données en temps réel de la page Admin "Courses en direct" :
/// positions des chauffeurs en ligne, courses en cours, noms des
/// chauffeurs. Lectures réservées à l'Admin par `firestore.rules`.
class SuiviDirectService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  Stream<List<PositionChauffeurDirect>> streamPositions() {
    return _firestore.collection(PositionChauffeurService.collection).snapshots().map(
          (instantane) => [
            for (final doc in instantane.docs)
              if (PositionChauffeurDirect.depuisDocument(doc.id, doc.data()) case final position?) position,
          ],
        );
  }

  Stream<List<CourseFirestore>> streamCoursesEnCours() => CourseService().streamCoursesEnCours();

  /// uid -> nom, depuis les profils publics des chauffeurs.
  Stream<Map<String, String>> streamNomsChauffeurs() {
    return _firestore
        .collection('profils_publics')
        .where('role', isEqualTo: 'conducteur')
        .snapshots()
        .map(
          (instantane) => {
            for (final doc in instantane.docs) doc.id: (doc.data()['nom'] as String?) ?? 'Chauffeur',
          },
        );
  }
}
