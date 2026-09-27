import '../../courses/data/course_service.dart';

/// Sens d'un règlement entre un chauffeur et la plateforme.
abstract final class SensReglement {
  /// Le chauffeur verse les commissions de ses courses en espèces.
  static const chauffeurVersPlateforme = 'chauffeur_vers_plateforme';

  /// La plateforme reverse au chauffeur sa part des courses mobile money.
  static const plateformeVersChauffeur = 'plateforme_vers_chauffeur';
}

/// Écriture comptable d'une course terminée.
///
/// Convention de signe du solde, partout dans l'app : positif = la
/// plateforme doit de l'argent au chauffeur ; négatif = le chauffeur doit
/// de l'argent à la plateforme.
class LigneCourse {
  const LigneCourse({
    required this.courseId,
    required this.chauffeurId,
    required this.prixFcfa,
    required this.commissionFcfa,
    required this.especes,
    required this.date,
  });

  factory LigneCourse.depuisCourse(CourseFirestore course) => LigneCourse(
        courseId: course.id,
        chauffeurId: course.chauffeurId ?? '',
        prixFcfa: course.prixFcfa,
        // Courses terminées avant la gestion financière : même formule.
        commissionFcfa: course.commissionFcfa ?? Commission.de(course.prixFcfa),
        especes: course.methodePaiement == 'ESPECES',
        date: course.termineeLe ?? course.timestamp,
      );

  final String courseId;
  final String chauffeurId;
  final int prixFcfa;
  final int commissionFcfa;

  /// Payée en espèces au chauffeur (sinon Wave / Orange Money, encaissé
  /// par la plateforme).
  final bool especes;
  final DateTime date;

  int get partChauffeurFcfa => prixFcfa - commissionFcfa;

  /// Espèces : le chauffeur a tout encaissé, il doit la commission.
  /// Mobile money : la plateforme a tout encaissé, elle doit sa part.
  int get effetSoldeFcfa => especes ? -commissionFcfa : partChauffeurFcfa;
}

class Reglement {
  const Reglement({
    required this.id,
    required this.chauffeurId,
    required this.montantFcfa,
    required this.sens,
    required this.date,
    this.note,
  });

  final String id;
  final String chauffeurId;
  final int montantFcfa;
  final String sens;
  final DateTime date;
  final String? note;

  bool get versPlateforme => sens == SensReglement.chauffeurVersPlateforme;

  /// Un versement du chauffeur réduit sa dette ; un reversement de la
  /// plateforme réduit ce qu'elle lui doit.
  int get effetSoldeFcfa => versPlateforme ? montantFcfa : -montantFcfa;
}

/// Compte d'un chauffeur (ou de toute la plateforme) sur une période.
class Compte {
  Compte({required this.courses, this.reglements = const []});

  final List<LigneCourse> courses;
  final List<Reglement> reglements;

  int get nombreCourses => courses.length;
  int get chiffreAffairesFcfa => _somme(courses.map((c) => c.prixFcfa));
  int get commissionsFcfa => _somme(courses.map((c) => c.commissionFcfa));
  int get gainsNetsFcfa => chiffreAffairesFcfa - commissionsFcfa;
  int get especesFcfa => _somme(courses.where((c) => c.especes).map((c) => c.prixFcfa));
  int get mobileMoneyFcfa => chiffreAffairesFcfa - especesFcfa;

  /// Commissions dues par le chauffeur sur ses courses en espèces.
  int get commissionsEspecesFcfa => _somme(courses.where((c) => c.especes).map((c) => c.commissionFcfa));

  /// Part du chauffeur sur les courses encaissées par la plateforme.
  int get partMobileMoneyFcfa => _somme(courses.where((c) => !c.especes).map((c) => c.partChauffeurFcfa));

  /// Solde net après compensation et règlements : positif = la plateforme
  /// doit au chauffeur, négatif = le chauffeur doit à la plateforme.
  int get soldeFcfa =>
      _somme(courses.map((c) => c.effetSoldeFcfa)) + _somme(reglements.map((r) => r.effetSoldeFcfa));

  /// Lignes à partir de [debut] (les règlements ne sont pas filtrés : le
  /// solde est toujours cumulé depuis le premier jour).
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

/// "Sprint vous doit 12 750 FCFA" / "Vous devez 450 FCFA à Sprint".
enum SensSolde { plateformeDoit, chauffeurDoit, equilibre }

SensSolde sensDuSolde(int soldeFcfa) => soldeFcfa > 0
    ? SensSolde.plateformeDoit
    : soldeFcfa < 0
        ? SensSolde.chauffeurDoit
        : SensSolde.equilibre;
