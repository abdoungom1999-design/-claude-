import '../../courses/data/course_service.dart';

/// Écriture comptable d'une course terminée.
///
/// 100 % mobile money : la plateforme encaisse chaque course (Wave /
/// Orange Money) et doit au chauffeur sa part, le prix moins la
/// commission.
///
/// Une course remboursée au client (support Admin) ne rapporte rien : ni
/// chiffre d'affaires, ni commission, ni part pour le chauffeur. Si cette
/// part lui avait déjà été versée, son solde devient négatif : elle est
/// déduite de ses prochains gains.
class LigneCourse {
  const LigneCourse({
    required this.courseId,
    required this.chauffeurId,
    required this.prixFcfa,
    required this.commissionFcfa,
    required this.date,
    this.methodePaiement,
    this.clientId = '',
    this.remboursee = false,
  });

  factory LigneCourse.depuisCourse(CourseFirestore course) => LigneCourse(
        courseId: course.id,
        chauffeurId: course.chauffeurId ?? '',
        prixFcfa: course.prixFcfa,
        // Courses terminées avant la gestion financière : même formule.
        commissionFcfa: course.commissionFcfa ?? Commission.de(course.prixFcfa),
        methodePaiement: course.methodePaiement,
        clientId: course.clientId,
        date: course.termineeLe ?? course.timestamp,
        remboursee: course.rembourseeLe != null,
      );

  /// Part du chauffeur sur [course] (celle qu'un remboursement lui
  /// retirerait) : 0 si la course n'est pas terminée.
  static int partChauffeurDe(CourseFirestore course) =>
      course.statut == StatutCourse.terminee && course.chauffeurId != null
          ? course.prixFcfa - (course.commissionFcfa ?? Commission.de(course.prixFcfa))
          : 0;

  final String courseId;
  final String chauffeurId;
  final String clientId;
  /// Prix payé par le client (affichage, même si remboursé).
  final int prixFcfa;

  /// Commission figée à l'arrivée (affichage, même si remboursé).
  final int commissionFcfa;
  final DateTime date;

  /// Remboursée intégralement au client : ne compte plus dans les comptes.
  final bool remboursee;

  /// Ce que Sprint garde du paiement du client (0 si remboursé).
  int get encaisseFcfa => remboursee ? 0 : prixFcfa;

  /// Commission de Sprint effectivement gagnée (0 si remboursé).
  int get commissionGagneeFcfa => remboursee ? 0 : commissionFcfa;

  /// Part du chauffeur qui lui a été retirée par le remboursement.
  int get partRetireeFcfa => remboursee ? prixFcfa - commissionFcfa : 0;

  /// "WAVE" / "ORANGE_MONEY" (affichage seulement).
  final String? methodePaiement;

  /// Ce que Sprint doit au chauffeur pour cette course (0 si remboursée :
  /// le chauffeur n'est pas payé pour une course remboursée).
  int get partChauffeurFcfa => remboursee ? 0 : prixFcfa - commissionFcfa;

  String get libelleMethode => switch (methodePaiement) {
        'WAVE' => 'Wave',
        'ORANGE_MONEY' => 'Orange Money',
        _ => 'Mobile money',
      };
}

/// Versement de Sprint au chauffeur, saisi par l'Admin.
class Reglement {
  const Reglement({
    required this.id,
    required this.chauffeurId,
    required this.montantFcfa,
    required this.date,
    this.note,
  });

  /// Seul sens accepté par `firestore.rules`.
  static const sensVersement = 'plateforme_vers_chauffeur';

  final String id;
  final String chauffeurId;
  final int montantFcfa;
  final DateTime date;
  final String? note;
}

/// Compte d'un chauffeur (ou de toute la plateforme) sur une période.
class Compte {
  Compte({required this.courses, this.reglements = const []});

  final List<LigneCourse> courses;
  final List<Reglement> reglements;

  /// Courses payées (hors courses remboursées).
  int get nombreCourses => courses.where((c) => !c.remboursee).length;
  int get nombreRemboursees => courses.where((c) => c.remboursee).length;
  int get chiffreAffairesFcfa => _somme(courses.map((c) => c.encaisseFcfa));
  int get commissionsFcfa => _somme(courses.map((c) => c.commissionGagneeFcfa));

  /// Parts des chauffeurs retirées après remboursement des clients.
  int get partsRetireesFcfa => _somme(courses.map((c) => c.partRetireeFcfa));

  /// Part des chauffeurs (85 %) : ce que Sprint leur doit sur ces courses.
  int get gainsNetsFcfa => chiffreAffairesFcfa - commissionsFcfa;

  /// Déjà versé par Sprint.
  int get versementsFcfa => _somme(reglements.map((r) => r.montantFcfa));

  /// Reste à verser par Sprint au chauffeur. Négatif seulement si une
  /// course déjà versée a été remboursée au client depuis : ce montant
  /// sera déduit de ses prochains gains (Sprint ne lui réclame rien).
  int get soldeFcfa => gainsNetsFcfa - versementsFcfa;

  /// Lignes à partir de [debut] (les règlements ne sont pas filtrés :
  /// utiliser [soldeFcfa] sur le compte complet).
  Compte depuis(DateTime debut) =>
      Compte(courses: [for (final c in courses) if (!c.date.isBefore(debut)) c], reglements: reglements);

  Compte duChauffeur(String chauffeurId) => Compte(
        courses: [for (final c in courses) if (c.chauffeurId == chauffeurId) c],
        reglements: [for (final r in reglements) if (r.chauffeurId == chauffeurId) r],
      );

  static int _somme(Iterable<int> valeurs) => valeurs.fold(0, (a, b) => a + b);
}

/// Débuts de période, à l'heure de Dakar (UTC+0 toute l'année).
abstract final class Periodes {
  static DateTime debutJour(DateTime maintenant) {
    final utc = maintenant.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day);
  }

  /// Lundi 00:00.
  static DateTime debutSemaine(DateTime maintenant) {
    final jour = debutJour(maintenant);
    return jour.subtract(Duration(days: jour.weekday - DateTime.monday));
  }

  /// Clé "AAAA-MM-JJ" (documents `temps_en_ligne`).
  static String cleJour(DateTime instant) {
    final utc = instant.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-${utc.month.toString().padLeft(2, '0')}-${utc.day.toString().padLeft(2, '0')}';
  }
}
