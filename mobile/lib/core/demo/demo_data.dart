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
    ),
    ConducteurAdmin(
      id: 'demo-2',
      nom: 'Awa Ndiaye',
      telephone: '+221 76 234 56 02',
      vehiculeId: 'TVS Ntorq',
      statut: 'HORS_LIGNE',
      estValide: true,
    ),
    ConducteurAdmin(
      id: 'demo-3',
      nom: 'Ibrahima Fall',
      telephone: '+221 78 345 67 03',
      vehiculeId: 'Sanya 125',
      statut: 'HORS_LIGNE',
      estValide: false,
    ),
    ConducteurAdmin(
      id: 'demo-4',
      nom: 'Fatou Sarr',
      telephone: '+221 70 456 78 04',
      vehiculeId: 'Bajaj RE',
      statut: 'EN_LIGNE',
      estValide: true,
    ),
    ConducteurAdmin(
      id: 'demo-5',
      nom: 'Cheikh Ba',
      telephone: '+221 77 567 89 05',
      vehiculeId: 'Haojue DK150',
      statut: 'HORS_LIGNE',
      estValide: false,
    ),
    ConducteurAdmin(
      id: 'demo-6',
      nom: 'Mamadou Sy',
      telephone: '+221 76 678 90 06',
      vehiculeId: 'TVS King Deluxe',
      statut: 'HORS_LIGNE',
      estValide: true,
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
    );
  }

  static void rejeterConducteur(String id) {
    _conducteurs.removeWhere((c) => c.id == id);
  }

  // --- Profil du conducteur connecté (espace Conducteur) ----------------

  static ProfilConducteur _monProfil = ProfilConducteur(
    id: 'demo-moi',
    nom: 'Vous (compte démo)',
    telephone: '+221 77 000 00 00',
    vehiculeId: 'Bajaj Boxer',
    statut: 'HORS_LIGNE',
    estValide: true,
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
    ),
    CourseHistorique(
      id: 'demo-hist-2',
      type: 'COLIS',
      adresseDepart: 'Médina, Dakar',
      adresseArrivee: 'Ouakam, Dakar',
      prixFcfa: 1800,
      date: DateTime.now().subtract(const Duration(days: 1, hours: 2)),
      statut: 'Terminée',
    ),
    CourseHistorique(
      id: 'demo-hist-3',
      type: 'PASSAGER',
      adresseDepart: 'Ngor, Dakar',
      adresseArrivee: 'Point E, Dakar',
      prixFcfa: 1500,
      date: DateTime.now().subtract(const Duration(days: 2, hours: 5)),
      statut: 'Terminée',
    ),
    CourseHistorique(
      id: 'demo-hist-4',
      type: 'PASSAGER',
      adresseDepart: 'Yoff, Dakar',
      adresseArrivee: 'Mermoz, Dakar',
      prixFcfa: 2000,
      date: DateTime.now().subtract(const Duration(days: 5)),
      statut: 'Terminée',
    ),
  ];

  static List<CourseHistorique> historique({String? type}) {
    if (type == null) return List.unmodifiable(_historique);
    return List.unmodifiable(_historique.where((c) => c.type == type));
  }

  // --- Profil et statistiques Client (onglet Compte) ----------------------

  static String monNomClient = 'Vous (compte démo)';
  static String monTelephoneClient = '+221 77 000 00 00';
  static String monEmailClient = 'vous@exemple.com';
  static const double noteMoyenneClient = 4.8;
  static const int coursesEffectueesClient = 23;
  static const int reservationsClient = 3;

  static void mettreAJourProfilClient({
    required String nom,
    required String telephone,
    required String email,
  }) {
    monNomClient = nom;
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
