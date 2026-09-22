import 'demo_data.dart';

/// Jeu de données factices pour la "Tour de Contrôle" (Tableau de bord
/// Administrateur, `/admin`) : KPIs, courbe hebdomadaire, dernières
/// courses, suivi en direct, clients, support et configuration
/// financière. Distinct de [DemoData] (qui couvre les espaces Client et
/// Conducteur) car il s'agit d'un domaine métier séparé, mais reste
/// cohérent avec lui : le nombre de "Chauffeurs en ligne" est calculé à
/// partir des mêmes conducteurs que la page Chauffeurs, pas d'un chiffre
/// indépendant.
class AdminDemoData {
  AdminDemoData._();

  // --- KPIs (Dashboard) ---------------------------------------------------

  static const int caJourFcfa = 1284500;
  static const int coursesTermineesJour = 342;
  static const int nouveauxInscritsJour = 18;

  static int get chauffeursEnLigne =>
      DemoData.listerConducteurs().where((c) => c.statut == 'EN_LIGNE').length;

  /// Courses terminées par jour, Lundi -> Dimanche, pour le graphique
  /// d'évolution hebdomadaire.
  static const List<int> courbeCoursesSemaine = [
    210,
    265,
    240,
    298,
    320,
    410,
    342,
  ];

  static const List<String> joursSemaineCourts = [
    'Lun',
    'Mar',
    'Mer',
    'Jeu',
    'Ven',
    'Sam',
    'Dim',
  ];

  // --- Dernières courses (Dashboard) --------------------------------------

  static const List<CourseAdminRecap> _dernieresCourses = [
    CourseAdminRecap(
      id: '#1042',
      client: 'Bamba Diallo',
      chauffeur: 'Moussa Diallo',
      trajet: 'Plateau -> Almadies',
      montantFcfa: 3200,
      statut: StatutCourseAdmin.terminee,
    ),
    CourseAdminRecap(
      id: '#1041',
      client: 'Astou Gueye',
      chauffeur: 'Fatou Sarr',
      trajet: 'Médina -> Ouakam',
      montantFcfa: 2100,
      statut: StatutCourseAdmin.terminee,
    ),
    CourseAdminRecap(
      id: '#1040',
      client: 'Ousmane Kane',
      chauffeur: 'Awa Ndiaye',
      trajet: 'Yoff -> Aéroport AIBD',
      montantFcfa: 8900,
      statut: StatutCourseAdmin.enCours,
    ),
    CourseAdminRecap(
      id: '#1039',
      client: 'Khady Faye',
      chauffeur: 'Moussa Diallo',
      trajet: 'Sacré-Cœur -> Point E',
      montantFcfa: 1800,
      statut: StatutCourseAdmin.annulee,
    ),
    CourseAdminRecap(
      id: '#1038',
      client: 'Serigne Mbaye',
      chauffeur: 'Fatou Sarr',
      trajet: 'Liberté 6 -> Ngor',
      montantFcfa: 2600,
      statut: StatutCourseAdmin.terminee,
    ),
  ];

  static List<CourseAdminRecap> dernieresCourses() =>
      List.unmodifiable(_dernieresCourses);

  // --- Courses en direct (Live Tracking) ----------------------------------

  static const List<CourseEnDirect> _coursesEnDirect = [
    CourseEnDirect(
      id: '#1024',
      description: 'Dakar centre -> Aéroport AIBD',
      chauffeur: 'Moussa Diallo',
      latitude: 14.6937,
      longitude: -17.4441,
    ),
    CourseEnDirect(
      id: '#1025',
      description: 'Médina -> Almadies',
      chauffeur: 'Awa Ndiaye',
      latitude: 14.7089,
      longitude: -17.4795,
    ),
    CourseEnDirect(
      id: '#1026',
      description: 'Ouakam -> Plateau',
      chauffeur: 'Fatou Sarr',
      latitude: 14.7247,
      longitude: -17.4884,
    ),
  ];

  static List<CourseEnDirect> coursesEnDirect() =>
      List.unmodifiable(_coursesEnDirect);

  // --- Clients (page Clients) ---------------------------------------------

  static const List<ClientAdmin> _clients = [
    ClientAdmin(
      nom: 'Bamba Diallo',
      telephone: '+221 77 111 22 33',
      coursesTotal: 42,
      inscritLe: '12/03/2025',
    ),
    ClientAdmin(
      nom: 'Astou Gueye',
      telephone: '+221 76 222 33 44',
      coursesTotal: 17,
      inscritLe: '28/05/2025',
    ),
    ClientAdmin(
      nom: 'Ousmane Kane',
      telephone: '+221 78 333 44 55',
      coursesTotal: 63,
      inscritLe: '02/01/2025',
    ),
    ClientAdmin(
      nom: 'Khady Faye',
      telephone: '+221 70 444 55 66',
      coursesTotal: 5,
      inscritLe: '14/09/2026',
    ),
    ClientAdmin(
      nom: 'Serigne Mbaye',
      telephone: '+221 77 555 66 77',
      coursesTotal: 29,
      inscritLe: '19/07/2025',
    ),
  ];

  static List<ClientAdmin> clients() => List.unmodifiable(_clients);

  // --- Support (page Support) ---------------------------------------------

  static const List<TicketSupport> _tickets = [
    TicketSupport(
      sujet: 'Course facturée deux fois',
      client: 'Ousmane Kane',
      statut: StatutTicket.ouvert,
    ),
    TicketSupport(
      sujet: 'Chauffeur injoignable',
      client: 'Khady Faye',
      statut: StatutTicket.ouvert,
    ),
    TicketSupport(
      sujet: 'Objet oublié dans le véhicule',
      client: 'Bamba Diallo',
      statut: StatutTicket.enCours,
    ),
    TicketSupport(
      sujet: 'Remboursement Wave non reçu',
      client: 'Astou Gueye',
      statut: StatutTicket.resolu,
    ),
  ];

  static List<TicketSupport> tickets() => List.unmodifiable(_tickets);

  // --- Configuration financière (page Finances) ---------------------------
  //
  // Simulée : modifie uniquement cet état en mémoire, n'affecte pas le
  // calcul de prix réel de l'app (voir DemoData.estimerPrix), pour rester
  // fidèle à la demande ("champs de saisie simulés").

  static double commissionPourcent = 15.0;
  static int prixBaseFcfa = 500;
  static int prixParKmFcfa = 150;

  static void mettreAJourConfigFinance({
    required double commissionPourcent,
    required int prixBaseFcfa,
    required int prixParKmFcfa,
  }) {
    AdminDemoData.commissionPourcent = commissionPourcent;
    AdminDemoData.prixBaseFcfa = prixBaseFcfa;
    AdminDemoData.prixParKmFcfa = prixParKmFcfa;
  }

  // --- Paramètres plateforme (page Paramètres) ----------------------------

  static const List<String> villesDisponibles = [
    'Dakar',
    'Thiès',
    'Saint-Louis',
    'Mbour',
  ];

  static Set<String> villesActives = {'Dakar', 'Thiès'};
  static bool modeMaintenance = false;

  static void mettreAJourParametresPlateforme({
    required Set<String> villesActives,
    required bool modeMaintenance,
  }) {
    AdminDemoData.villesActives = villesActives;
    AdminDemoData.modeMaintenance = modeMaintenance;
  }
}

enum StatutCourseAdmin { terminee, annulee, enCours }

class CourseAdminRecap {
  const CourseAdminRecap({
    required this.id,
    required this.client,
    required this.chauffeur,
    required this.trajet,
    required this.montantFcfa,
    required this.statut,
  });

  final String id;
  final String client;
  final String chauffeur;
  final String trajet;
  final int montantFcfa;
  final StatutCourseAdmin statut;
}

class CourseEnDirect {
  const CourseEnDirect({
    required this.id,
    required this.description,
    required this.chauffeur,
    required this.latitude,
    required this.longitude,
  });

  final String id;
  final String description;
  final String chauffeur;
  final double latitude;
  final double longitude;
}

class ClientAdmin {
  const ClientAdmin({
    required this.nom,
    required this.telephone,
    required this.coursesTotal,
    required this.inscritLe,
  });

  final String nom;
  final String telephone;
  final int coursesTotal;
  final String inscritLe;
}

enum StatutTicket { ouvert, enCours, resolu }

class TicketSupport {
  const TicketSupport({
    required this.sujet,
    required this.client,
    required this.statut,
  });

  final String sujet;
  final String client;
  final StatutTicket statut;
}
