import 'package:cloud_firestore/cloud_firestore.dart';
import '../../conducteur/data/position_chauffeur_service.dart';
import '../../courses/data/course_service.dart';

/// Dernière position connue d'un chauffeur en ligne
/// (`positions_chauffeurs/{uid}`, voir [PositionChauffeurService]).
class PositionChauffeurDirect {
  const PositionChauffeurDirect({
    required this.uid,
    required this.latitude,
    required this.longitude,
    required this.majLe,
  });

  final String uid;
  final double latitude;
  final double longitude;

  /// `null` le temps que le serveur horodate le tout premier envoi.
  final DateTime? majLe;

  static PositionChauffeurDirect? depuisDocument(String uid, Map<String, dynamic> donnees) {
    final latitude = donnees['latitude'];
    final longitude = donnees['longitude'];
    if (latitude is! num || longitude is! num) return null;
    final majLe = donnees['majLe'];
    return PositionChauffeurDirect(
      uid: uid,
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      majLe: majLe is Timestamp ? majLe.toDate() : null,
    );
  }
}

/// Fraîcheur du signal GPS d'un chauffeur. Le téléphone envoie sa
/// position au moins toutes les 30 s, même à l'arrêt.
enum EtatSignal {
  /// Position reçue il y a moins de 2 minutes.
  actif,

  /// Plus de nouvelles depuis 2 à 30 minutes (écran verrouillé, onglet
  /// fermé, réseau coupé…) : affiché en gris, dernière position connue.
  perdu,

  /// Plus de 30 minutes : le chauffeur n'est plus affiché.
  expire;

  static const delaiPerdu = Duration(minutes: 2);
  static const delaiExpire = Duration(minutes: 30);

  static EtatSignal pour(DateTime? majLe, DateTime maintenant) {
    // Tout premier envoi, pas encore horodaté par le serveur.
    if (majLe == null) return EtatSignal.actif;
    final age = maintenant.difference(majLe);
    if (age >= delaiExpire) return EtatSignal.expire;
    if (age >= delaiPerdu) return EtatSignal.perdu;
    return EtatSignal.actif;
  }
}

/// "à l'instant", "il y a 45 s", "il y a 3 min".
String ilYA(DateTime? instant, DateTime maintenant) {
  if (instant == null) return "à l'instant";
  final age = maintenant.difference(instant);
  if (age.inSeconds < 5) return "à l'instant";
  if (age.inMinutes < 1) return 'il y a ${age.inSeconds} s';
  if (age.inHours < 1) return 'il y a ${age.inMinutes} min';
  return 'il y a ${age.inHours} h';
}

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
