import 'dart:math';

import '../../features/admin/data/admin_repository.dart';
import '../../features/conducteur/data/conducteur_repository.dart';
import '../../features/courses/data/pricing_repository.dart';

/// Jeu de données factices utilisé uniquement en [ApiConfig.modeDemo],
/// pour permettre de naviguer et d'interagir avec l'application sans
/// aucun appel réseau tant qu'aucun backend public n'est configuré.
///
/// L'algorithme de tarification est une réplique exacte de celui du
/// backend (voir `backend/src/pricing/pricing.service.ts`) : même
/// formule, mêmes tarifs par défaut, pour que les prix affichés en mode
/// démo restent cohérents avec ceux que produirait le vrai serveur.
class DemoData {
  DemoData._();

  static final _random = Random();

  // --- Conducteurs (espace Admin) --------------------------------------
  //
  // Store mutable en mémoire : Valider/Rejeter dans l'espace Admin
  // modifient réellement cette liste, pour une démo interactive plutôt
  // qu'un simple affichage figé. Réinitialisé au rechargement complet de
  // la page (comportement normal d'un état en mémoire, pas de backend
  // pour le persister).
  static final List<ConducteurAdmin> _conducteurs = [
    ConducteurAdmin(
      id: 'demo-1',
      nom: 'Moussa Diallo',
      telephone: '+221 77 123 45 01',
      vehiculeId: 'Bajaj Boxer',
      statut: 'EN_LIGNE',
      estValide: true,
      note: 4.8,
    ),
    ConducteurAdmin(
      id: 'demo-2',
      nom: 'Awa Ndiaye',
      telephone: '+221 76 234 56 02',
      vehiculeId: 'TVS Ntorq',
      statut: 'HORS_LIGNE',
      estValide: true,
      note: 4.9,
    ),
    ConducteurAdmin(
      id: 'demo-3',
      nom: 'Ibrahima Fall',
      telephone: '+221 78 345 67 03',
      vehiculeId: 'Sanya 125',
      statut: 'HORS_LIGNE',
      estValide: false,
      note: 0.0,
    ),
    ConducteurAdmin(
      id: 'demo-4',
      nom: 'Fatou Sarr',
      telephone: '+221 70 456 78 04',
      vehiculeId: 'Bajaj RE',
      statut: 'EN_LIGNE',
      estValide: true,
      note: 4.6,
    ),
    ConducteurAdmin(
      id: 'demo-5',
      nom: 'Cheikh Ba',
      telephone: '+221 77 567 89 05',
      vehiculeId: 'Haojue DK150',
      statut: 'HORS_LIGNE',
      estValide: false,
      note: 0.0,
    ),
    ConducteurAdmin(
      id: 'demo-6',
      nom: 'Mamadou Sy',
      telephone: '+221 76 678 90 06',
      vehiculeId: 'TVS King Deluxe',
      statut: 'HORS_LIGNE',
      estValide: true,
      note: 3.9,
      suspendu: true,
    ),
  ];

  static List<ConducteurAdmin> listerConducteurs() => List.unmodifiable(_conducteurs);

  static void validerConducteur(String id) {
    final index = _conducteurs.indexWhere((c) => c.id == id);
    if (index == -1) return;
    final c = _conducteurs[index];
    _conducteurs[index] = ConducteurAdmin(
      id: c.id,
      nom: c.nom,
      telephone: c.telephone,
      vehiculeId: c.vehiculeId,
      statut: c.statut,
      estValide: true,
      note: c.note,
      suspendu: c.suspendu,
    );
  }

  static void rejeterConducteur(String id) {
    _conducteurs.removeWhere((c) => c.id == id);
  }

  static void bloquerConducteur(String id) {
    final index = _conducteurs.indexWhere((c) => c.id == id);
    if (index == -1) return;
    final c = _conducteurs[index];
    _conducteurs[index] = ConducteurAdmin(
      id: c.id,
      nom: c.nom,
      telephone: c.telephone,
      vehiculeId: c.vehiculeId,
      statut: 'HORS_LIGNE',
      estValide: c.estValide,
      note: c.note,
      suspendu: true,
    );
  }

  static void debloquerConducteur(String id) {
    final index = _conducteurs.indexWhere((c) => c.id == id);
    if (index == -1) return;
    final c = _conducteurs[index];
    _conducteurs[index] = ConducteurAdmin(
      id: c.id,
      nom: c.nom,
      telephone: c.telephone,
      vehiculeId: c.vehiculeId,
      statut: c.statut,
      estValide: c.estValide,
      note: c.note,
      suspendu: false,
    );
  }

  // --- Profil du conducteur connecté (espace Conducteur) ----------------

  static ProfilConducteur _monProfil = ProfilConducteur(
    id: 'demo-moi',
    nom: 'Vous (compte démo)',
    telephone: '+221 77 000 00 00',
    vehiculeId: 'Bajaj Boxer 125 Noir',
    statut: 'HORS_LIGNE',
    estValide: true,
    plaqueImmatriculation: 'DK-1234-AB',
  );

  static ProfilConducteur monProfil() => _monProfil;

  static String mettreAJourStatutConducteur(String statut) {
    _monProfil = ProfilConducteur(
      id: _monProfil.id,
      nom: _monProfil.nom,
      telephone: _monProfil.telephone,
      vehiculeId: _monProfil.vehiculeId,
      statut: statut,
      estValide: _monProfil.estValide,
      plaqueImmatriculation: _monProfil.plaqueImmatriculation,
    );
    return _monProfil.statut;
  }

  // Statistiques factices du tableau de bord Conducteur, pour ne plus
  // afficher des "0" figés en mode démo.
  static const int coursesAujourdHui = 7;
  static const int gainsEstimesFcfa = 18400;
  static const double noteMoyenneConducteur = 5.0;

  // --- Tarification (réplique exacte du backend) -------------------------

  static const double _vitesseMoyenneKmh = 22;

  static const _tarifsPassager = _Tarifs(
    prisEnCharge: 500,
    parKm: 150,
    parMinute: 50,
    prixMinimum: 500,
  );

  static const _tarifsColis = _Tarifs(
    prisEnCharge: 700,
    parKm: 200,
    parMinute: 40,
    prixMinimum: 700,
  );

  static EstimationPrix estimerPrix({
    required String type,
    required double distanceKm,
  }) {
    final distance = distanceKm < 0 ? 0.0 : distanceKm;
    final dureeEstimeeMin = ((distance / _vitesseMoyenneKmh) * 60).round();
    final tarifs = type == 'COLIS' ? _tarifsColis : _tarifsPassager;
    final multiplicateurTrafic = _multiplicateurTraficActuel();

    final montantBrut =
        (tarifs.prisEnCharge +
            distance * tarifs.parKm +
            dureeEstimeeMin * tarifs.parMinute) *
        multiplicateurTrafic;

    final prixArrondi = (montantBrut / 100).round() * 100;
    final prixFcfa = max(prixArrondi, tarifs.prixMinimum);

    return EstimationPrix(
      distanceKm: distance,
      dureeEstimeeMin: dureeEstimeeMin,
      multiplicateurTrafic: multiplicateurTrafic,
      prixFcfa: prixFcfa,
    );
  }

  static double _multiplicateurTraficActuel() {
    final heure = DateTime.now().toUtc().hour;
    final heurePointe = (heure >= 7 && heure < 10) || (heure >= 17 && heure < 20);
    final heureNuit = heure >= 22 || heure < 5;
    if (heurePointe) return 1.4;
    if (heureNuit) return 1.2;
    return 1.0;
  }

  static String nouvelIdCourse() {
    return 'demo-course-${_random.nextInt(900000) + 100000}';
  }

  // --- Simulation d'arrivée de course (écran Accueil Conducteur) --------

  static const List<String> _adressesSimulation = [
    'Plateau, Dakar',
    'Almadies, Dakar',
    'Médina, Dakar',
    'Ouakam, Dakar',
    'Point E, Dakar',
    'Yoff, Dakar',
    'Liberté 6, Dakar',
    'Sacré-Cœur, Dakar',
  ];

  /// Génère une fausse demande de course entrante (type, prix estimé —
  /// via la même réplique de tarification que le reste de l'app —,
  /// distance d'approche et adresse de départ), pour l'animation
  /// "Nouvelle course" de l'écran Accueil Conducteur.
  static NouvelleCourseSimulee genererNouvelleCourseConducteur() {
    final type = _random.nextBool() ? 'VTC' : 'COLIS';
    final distanceKm = 1 + _random.nextDouble() * 8;
    final estimation = estimerPrix(type: type, distanceKm: distanceKm);
    final adresse = _adressesSimulation[_random.nextInt(_adressesSimulation.length)];
    final approcheMin = 2 + _random.nextInt(5);

    return NouvelleCourseSimulee(
      type: type == 'COLIS' ? 'Colis' : 'VTC',
      prixFcfa: estimation.prixFcfa,
      approcheMin: approcheMin,
      adresseDepart: adresse,
    );
  }

  // --- Historique (onglet Activité côté Client) --------------------------

  static final List<CourseHistorique> _historique = [
    CourseHistorique(
      id: 'demo-hist-1',
      type: 'PASSAGER',
      adresseDepart: 'Plateau, Dakar',
      adresseArrivee: 'Almadies, Dakar',
      prixFcfa: 2400,
      date: DateTime.now().subtract(const Duration(hours: 3)),
      statut: 'Terminée',
      noteDonnee: 5,
    ),
    CourseHistorique(
      id: 'demo-hist-2',
      type: 'COLIS',
      adresseDepart: 'Médina, Dakar',
      adresseArrivee: 'Ouakam, Dakar',
      prixFcfa: 1800,
      date: DateTime.now().subtract(const Duration(days: 1, hours: 2)),
      statut: 'Terminée',
      noteDonnee: 4,
    ),
    CourseHistorique(
      id: 'demo-hist-3',
      type: 'PASSAGER',
      adresseDepart: 'Ngor, Dakar',
      adresseArrivee: 'Point E, Dakar',
      prixFcfa: 1500,
      date: DateTime.now().subtract(const Duration(days: 2, hours: 5)),
      statut: 'Terminée',
      noteDonnee: 5,
    ),
    CourseHistorique(
      id: 'demo-hist-4',
      type: 'PASSAGER',
      adresseDepart: 'Yoff, Dakar',
      adresseArrivee: 'Mermoz, Dakar',
      prixFcfa: 2000,
      date: DateTime.now().subtract(const Duration(days: 5)),
      statut: 'Terminée',
      noteDonnee: 5,
    ),
  ];

  static List<CourseHistorique> historique({String? type}) {
    if (type == null) return List.unmodifiable(_historique);
    return List.unmodifiable(_historique.where((c) => c.type == type));
  }

  // --- Profil et statistiques Client (onglet Compte) ----------------------

  static String monPrenomClient = 'Bamba';
  static String monNomFamilleClient = 'Diallo';
  static String monTelephoneClient = '+221';
  static String monEmailClient = 'vous@exemple.com';
  static const double noteMoyenneClient = 4.8;
  static const int coursesEffectueesClient = 23;
  static const int reservationsClient = 3;

  static String get monNomClient => '$monPrenomClient $monNomFamilleClient';

  static void mettreAJourProfilClient({
    required String prenom,
    required String nom,
    required String telephone,
    required String email,
  }) {
    monPrenomClient = prenom;
    monNomFamilleClient = nom;
    monTelephoneClient = telephone;
    monEmailClient = email;
  }

  // --- Portefeuille (onglet Compte) ---------------------------------------

  static int soldePortefeuilleFcfa = 0;

  static void rechargerPortefeuille(int montantFcfa) {
    soldePortefeuilleFcfa += montantFcfa;
  }

  // --- Favoris (adresses enregistrées) ------------------------------------

  static final List<AdresseFavorite> _favoris = [
    AdresseFavorite(
      id: 'demo-fav-1',
      libelle: 'Maison',
      adresse: 'Sacré-Cœur 3, Dakar',
      icon: 'maison',
    ),
    AdresseFavorite(
      id: 'demo-fav-2',
      libelle: 'Travail',
      adresse: 'Plateau, Dakar',
      icon: 'travail',
    ),
  ];

  static List<AdresseFavorite> favoris() => List.unmodifiable(_favoris);
  static int get favorisClient => _favoris.length;

  // --- Avis reçus par le conducteur (onglet Évaluations) ------------------

  static final List<AvisClient> _avisConducteur = [
    AvisClient(
      auteur: 'Aïssatou D.',
      note: 5,
      commentaire: 'Conducteur ponctuel et très courtois. Trajet impeccable.',
      date: DateTime.now().subtract(const Duration(days: 1)),
    ),
    AvisClient(
      auteur: 'Modou N.',
      note: 5,
      commentaire: 'Super moto, trajet rapide et sécurisé.',
      date: DateTime.now().subtract(const Duration(days: 3)),
    ),
    AvisClient(
      auteur: 'Khady S.',
      note: 4,
      commentaire: 'Bonne course, un peu d\'attente au départ.',
      date: DateTime.now().subtract(const Duration(days: 6)),
    ),
  ];

  static List<AvisClient> avisConducteur() => List.unmodifiable(_avisConducteur);

  // Récapitulatif des gains chauffeur (écran Gains).
  static const int gainsSemaineFcfa = 96500;
  static const int gainsMoisFcfa = 342000;
  static const int coursesSemaine = 34;

  /// Gains par jour, Lundi -> Dimanche (somme = [gainsSemaineFcfa]), pour
  /// le graphique à barres de l'écran Gains.
  static const List<int> gainsParJourSemaine = [
    11200,
    14800,
    9600,
    16400,
    18900,
    15100,
    10500,
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

  static const List<CourseTermineeConducteur> _coursesTermineesConducteur = [
    CourseTermineeConducteur(heure: '18:42', montantFcfa: 2200, type: 'VTC'),
    CourseTermineeConducteur(heure: '17:58', montantFcfa: 1500, type: 'VTC'),
    CourseTermineeConducteur(heure: '17:20', montantFcfa: 3400, type: 'Colis'),
    CourseTermineeConducteur(heure: '16:35', montantFcfa: 1800, type: 'VTC'),
    CourseTermineeConducteur(heure: '15:50', montantFcfa: 2600, type: 'VTC'),
    CourseTermineeConducteur(heure: '14:12', montantFcfa: 1200, type: 'VTC'),
    CourseTermineeConducteur(heure: '13:05', montantFcfa: 4100, type: 'Colis'),
    CourseTermineeConducteur(heure: '11:47', montantFcfa: 2000, type: 'VTC'),
    CourseTermineeConducteur(heure: '10:22', montantFcfa: 1700, type: 'VTC'),
    CourseTermineeConducteur(heure: '09:15', montantFcfa: 2900, type: 'VTC'),
  ];

  static List<CourseTermineeConducteur> coursesTermineesConducteur() =>
      List.unmodifiable(_coursesTermineesConducteur);

  static const List<ComplimentConducteur> _complimentsConducteur = [
    ComplimentConducteur(label: 'Excellente conduite', compte: 28),
    ComplimentConducteur(label: 'Voiture impeccable', compte: 19),
    ComplimentConducteur(label: 'Bonne conversation', compte: 14),
    ComplimentConducteur(label: 'Trajet efficace', compte: 22),
  ];

  static List<ComplimentConducteur> complimentsConducteur() =>
      List.unmodifiable(_complimentsConducteur);

  // --- Messagerie (onglet Messages + Mes échanges) ------------------------

  static final List<Conversation> _conversations = [
    Conversation(
      id: 'demo-conv-1',
      nom: 'Moussa Diallo',
      sousTitre: 'Chauffeur · Bajaj Boxer',
      messages: [
        ChatMessage(
          texte: 'Bonjour ! Je suis en route, j\'arrive dans 5 minutes.',
          envoyeParMoi: false,
          heure: DateTime.now().subtract(const Duration(minutes: 6)),
        ),
        ChatMessage(
          texte: 'Parfait, je vous attends devant l\'entrée principale.',
          envoyeParMoi: true,
          heure: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
      ],
    ),
    Conversation(
      id: 'demo-conv-2',
      nom: 'Fatou Sarr',
      sousTitre: 'Chauffeuse · Bajaj RE',
      messages: [
        ChatMessage(
          texte: 'Votre colis a bien été livré, merci !',
          envoyeParMoi: false,
          heure: DateTime.now().subtract(const Duration(days: 1)),
        ),
      ],
    ),
  ];

  static List<Conversation> conversations() => List.unmodifiable(_conversations);

  /// Exposée directement (mutable), comme [Conversation.messages] :
  /// [ChatPage] y ajoute les messages envoyés sans wrapper en lecture
  /// seule, pour que le fil support persiste tant que l'app reste ouverte.
  static final List<ChatMessage> messagesSupport = [];

  // --- Préférences (écran Préférences) ------------------------------------

  static String villeActivite = 'Dakar';
  static String theme = 'Système';
  static String uniteDistance = 'km';
  static String formatHeure = '24h';
  static String devise = 'FCFA';

  // --- Notifications (écran Notifications) --------------------------------

  static bool notifCourses = true;
  static bool notifPromotions = true;
  static bool notifActualites = false;

  // --- Parrainage (écran Inviter des amis) ---------------------------------

  static const String codeParrainage = '7ZMXZJ';
  static const int parrainageInvites = 0;
  static const int parrainageQualifies = 0;
  static const int parrainageGainsFcfa = 0;
}

/// Un message dans une conversation (voir [Conversation]) ou dans le fil
/// support (voir [DemoData.messagesSupport]).
class ChatMessage {
  ChatMessage({required this.texte, required this.envoyeParMoi, required this.heure});

  final String texte;
  final bool envoyeParMoi;
  final DateTime heure;
}

/// Fil de discussion avec un chauffeur (écran Messages).
class Conversation {
  Conversation({
    required this.id,
    required this.nom,
    required this.sousTitre,
    required this.messages,
  });

  final String id;
  final String nom;
  final String sousTitre;

  /// Mutable : envoyer un message depuis [ChatPage] l'ajoute directement
  /// ici, pour que la conversation garde son historique tant que l'app
  /// reste ouverte.
  final List<ChatMessage> messages;
}

/// Adresse enregistrée par le client (écran Favoris).
class AdresseFavorite {
  AdresseFavorite({
    required this.id,
    required this.libelle,
    required this.adresse,
    required this.icon,
  });

  final String id;
  final String libelle;
  final String adresse;
  final String icon; // 'maison' | 'travail' | 'autre'
}

/// Avis client factice affiché à un conducteur (écran Évaluations).
class AvisClient {
  AvisClient({
    required this.auteur,
    required this.note,
    required this.commentaire,
    required this.date,
  });

  final String auteur;
  final int note;
  final String commentaire;
  final DateTime date;
}

/// Demande de course entrante simulée (écran Accueil Conducteur).
class NouvelleCourseSimulee {
  const NouvelleCourseSimulee({
    required this.type,
    required this.prixFcfa,
    required this.approcheMin,
    required this.adresseDepart,
  });

  final String type; // 'VTC' | 'Colis'
  final int prixFcfa;
  final int approcheMin;
  final String adresseDepart;
}

/// Course terminée factice affichée dans l'écran Gains (Conducteur).
class CourseTermineeConducteur {
  const CourseTermineeConducteur({
    required this.heure,
    required this.montantFcfa,
    required this.type,
  });

  final String heure;
  final int montantFcfa;
  final String type; // 'VTC' | 'Colis'
}

/// Badge de compliment reçu des clients (écran Évaluations, Conducteur).
class ComplimentConducteur {
  const ComplimentConducteur({required this.label, required this.compte});

  final String label;
  final int compte;
}

/// Course passée factice affichée dans l'onglet Activité > Historique.
class CourseHistorique {
  CourseHistorique({
    required this.id,
    required this.type,
    required this.adresseDepart,
    required this.adresseArrivee,
    required this.prixFcfa,
    required this.date,
    required this.statut,
    this.noteDonnee,
  });

  final String id;
  final String type; // 'PASSAGER' | 'COLIS'
  final String adresseDepart;
  final String adresseArrivee;
  final int prixFcfa;
  final DateTime date;
  final String statut;

  /// null tant que le client n'a pas noté la course (écran "Courses à
  /// noter"), sinon la note (1 à 5) donnée.
  int? noteDonnee;
}

class _Tarifs {
  const _Tarifs({
    required this.prisEnCharge,
    required this.parKm,
    required this.parMinute,
    required this.prixMinimum,
  });

  final int prisEnCharge;
  final int parKm;
  final int parMinute;
  final int prixMinimum;
}
