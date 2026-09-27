import 'package:cloud_firestore/cloud_firestore.dart';
import '../../courses/data/course_service.dart';
import '../../finances/data/comptabilite.dart';
import '../../finances/data/finance_service.dart';
import 'suivi_direct_service.dart';

export '../../courses/data/position_chauffeur.dart';

/// Compte inscrit depuis l'application (`users/{uid}`), vu par l'Admin.
class UtilisateurAdmin {
  const UtilisateurAdmin({
    required this.id,
    required this.role,
    required this.nom,
    required this.telephone,
    required this.email,
    this.creeLe,
    this.statutValidation,
  });

  factory UtilisateurAdmin.depuisFirestore(String id, Map<String, dynamic> donnees) {
    final creeLe = donnees['creeLe'];
    final nom = (donnees['nom'] as String?)?.trim() ?? '';
    return UtilisateurAdmin(
      id: id,
      role: donnees['role'] as String? ?? '',
      nom: nom.isEmpty ? 'Sans nom' : nom,
      telephone: donnees['telephone'] as String? ?? '',
      email: donnees['email'] as String? ?? '',
      creeLe: creeLe is Timestamp ? creeLe.toDate() : null,
      statutValidation: donnees['statutValidation'] as String?,
    );
  }

  final String id;

  /// `client` ou `conducteur`.
  final String role;
  final String nom;
  final String telephone;
  final String email;

  /// Date d'inscription (`null` pour les tout premiers comptes de test).
  final DateTime? creeLe;

  /// Chauffeurs seulement : dossier KYC (`valide`, `en_attente`…).
  final String? statutValidation;
}

/// Données réelles du Dashboard et de la page Clients de l'Admin.
/// Lectures réservées à l'Admin par `firestore.rules`.
class PilotageService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  /// Même requête que la page Chauffeurs pour `conducteur` : Firestore
  /// partage alors une seule écoute entre les deux pages.
  Stream<List<UtilisateurAdmin>> streamUtilisateurs(String role) => _firestore
      .collection('users')
      .where('role', isEqualTo: role)
      .snapshots()
      .map((instantane) => [
            for (final doc in instantane.docs) UtilisateurAdmin.depuisFirestore(doc.id, doc.data()),
          ]);

  /// Dernières courses créées, tous statuts confondus.
  Stream<List<CourseFirestore>> streamDernieresCourses({int limite = 10}) => _firestore
      .collection('courses')
      .orderBy('timestamp', descending: true)
      .limit(limite)
      .snapshots()
      .map((instantane) => [
            for (final doc in instantane.docs) CourseFirestore.depuisDocument(doc.id, doc.data()),
          ]);

  Stream<List<PositionChauffeurDirect>> streamPositions() => SuiviDirectService().streamPositions();

  Stream<List<LigneCourse>> streamCoursesTerminees() => FinanceService().streamToutesCourses();
}
