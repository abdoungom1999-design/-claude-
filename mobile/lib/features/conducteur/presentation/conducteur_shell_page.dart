import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/alertes/alerte_sonore.dart';
import '../../../core/demo/demo_data.dart';
import '../../../core/location/device_location_service.dart';
import '../../../core/maps/navigation_gps.dart';
import '../../../core/models/statut_compte.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/notifications/notifications_push.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/email_verification_pending_page.dart';
import '../../../core/widgets/onyx_vert.dart';
import '../../../firebase_options.dart';
import '../../auth/data/auth_repository.dart';
import '../../courses/data/course_service.dart';
import '../../courses/data/depart_exact.dart';
import '../../courses/data/itineraire_service.dart';
import '../../finances/data/finance_service.dart';
import '../../messages/data/chat_service.dart';
import '../../messages/data/detecteur_nouveaux_messages.dart';
import '../../messages/presentation/messagerie_chat_page.dart';
import '../data/conducteur_repository.dart';
import '../data/position_chauffeur_service.dart';
import 'conducteur_compte_bloque_page.dart';
import 'conducteur_en_attente_page.dart';
import 'conducteur_kyc_page.dart';
import 'tabs/conducteur_accueil_tab.dart';
import 'tabs/conducteur_compte_tab.dart';
import 'tabs/conducteur_evaluations_tab.dart';
import 'tabs/conducteur_gains_tab.dart';
import 'tabs/conducteur_messages_tab.dart';
import 'validation_pending_page.dart';
import 'widgets/actions_course_active.dart';
import 'widgets/conducteur_bottom_nav.dart';
import 'widgets/course_active_bandeau.dart';
import 'widgets/guidage_course.dart';
import 'widgets/nouvelle_course_reelle_sheet.dart';
import 'widgets/nouvelle_course_sheet.dart';

/// État du "Gardien" KYC, déterminé une seule fois à l'ouverture (juste
/// après connexion) à partir du champ `statutValidation` du document
/// Firestore de l'utilisateur — jamais du booléen legacy `estValide` de
/// [ConducteurRepository] (voir [_ConducteurShellPageState._chargerProfil]).
enum _EtapeKyc { chargement, nonEnvoye, enAttente, valide }

/// Coquille de navigation de l'espace Conducteur (Sprint Conducteur) :
/// barre du bas à 5 onglets (Accueil, Messages, Gains, Évaluations,
/// Compte). Porte l'état partagé entre onglets (profil, statut En
/// ligne/Hors ligne) et le radar de courses en attente en temps réel
/// (voir [CourseService]).
class ConducteurShellPage extends StatefulWidget {
  const ConducteurShellPage({super.key});

  @override
  State<ConducteurShellPage> createState() => _ConducteurShellPageState();
}

class _ConducteurShellPageState extends State<ConducteurShellPage> {
  final _conducteurRepository = ConducteurRepository();
  final _authRepository = AuthRepository();
  final _locationService = DeviceLocationService();
  final _courseService = CourseService();
  final _positionService = PositionChauffeurService();
  final _itineraires = ItineraireCloud();
  final _tempsEnLigne = TempsEnLigneService();
  final _random = Random();

  int _indexSelectionne = 0;
  ProfilConducteur? _profil;
  bool _enLigne = false;
  _EtapeKyc _etapeKyc = _EtapeKyc.chargement;
  Timer? _minuteurPosition;
  Timer? _minuteurNouvelleCourse;
  StreamSubscription<List<CourseFirestore>>? _abonnementCoursesEnAttente;
  StreamSubscription<Map<String, dynamic>?>? _abonnementStatutCompte;
  StreamSubscription<CourseFirestore?>? _abonnementCourseActive;

  /// Course attribuée à ce chauffeur et pas encore terminée (voir
  /// [CourseActiveBandeau]). Tant qu'elle existe, le radar ne propose
  /// pas d'autre course.
  CourseFirestore? _courseActive;
  bool _avancementCourseEnCours = false;

  // Communication avec le client de la course active (voir
  // [_suivreClient]) : profil (nom, téléphone), dernier message reçu.
  final _chatService = ChatService();
  String? _clientSuivi;
  Map<String, dynamic>? _profilClient;
  DetecteurNouveauxMessages? _detecteurMessages;
  StreamSubscription<ChatMessageFirestore?>? _abonnementMessages;
  bool _chatClientOuvert = false;

  /// `'suspendu'` ou `'banni'` dès que l'Admin sanctionne le compte :
  /// le chauffeur est alors éjecté (voir [_ejecter]).
  String? _statutBloque;
  final Set<String> _idsCoursesIgnorees = {};
  bool _sheetCourseOuverte = false;

  @override
  void initState() {
    super.initState();
    _chargerProfil();
  }

  @override
  void dispose() {
    _minuteurPosition?.cancel();
    _minuteurNouvelleCourse?.cancel();
    _abonnementCoursesEnAttente?.cancel();
    _abonnementStatutCompte?.cancel();
    _abonnementCourseActive?.cancel();
    _abonnementMessages?.cancel();
    _tempsEnLigne.arreter();
    if (DefaultFirebaseOptions.estConfigure) unawaited(_positionService.arreter());
    super.dispose();
  }

  Future<void> _chargerProfil() async {
    try {
      final profil = await _conducteurRepository.monProfil();
      if (!mounted) return;
      setState(() {
        _profil = profil;
        _enLigne = profil.statut == 'EN_LIGNE';
      });
      if (DefaultFirebaseOptions.estConfigure) {
        await _chargerEtapeKyc();
      }
      if (mounted && _gateOuverte && DefaultFirebaseOptions.estConfigure) {
        _surveillerCourseActive();
        // Nouvelles courses et messages, même app fermée (APK Android).
        // Un appui sur la notification ouvre simplement l'app : le radar
        // et le bandeau de course sont déjà à l'écran.
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) unawaited(NotificationsPush.instance.activer(uid: uid, surAppui: (_) {}));
      }
      if (mounted && _gateOuverte && _enLigne) {
        _demarrerEnvoiPosition();
        _demarrerRadarCourses();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Lit une fois le document Firestore de l'utilisateur connecté pour
  /// déterminer l'étape du "Gardien" KYC — voir [_EtapeKyc]. Évaluée
  /// juste après connexion (pas en continu) : c'est au chauffeur de
  /// confirmer explicitement l'envoi de son dossier via
  /// [ConducteurKYCPage.onDossierSoumis] pour avancer d'une étape,
  /// plutôt que de basculer automatiquement dès le premier document
  /// envoyé (ce qui le ferait quitter la page KYC avant d'avoir eu le
  /// temps d'envoyer les deux autres).
  Future<void> _chargerEtapeKyc() async {
    final donnees = await _authRepository.chargerProfilUtilisateur();
    if (!mounted) return;
    final statutCompte = donnees?['statutCompte'] as String?;
    if (StatutCompte.estBloque(statutCompte)) {
      await _ejecter(statutCompte!);
      _surveillerStatutCompte();
      return;
    }
    _surveillerStatutCompte();
    final statutValidation = donnees?['statutValidation'] as String?;
    setState(() {
      _etapeKyc = switch (statutValidation) {
        'valide' => _EtapeKyc.valide,
        'en_attente' => _EtapeKyc.enAttente,
        _ => _EtapeKyc.nonEnvoye,
      };
    });
  }

  /// Contrairement au KYC, la sanction est surveillée en continu : un
  /// chauffeur suspendu ou banni pendant qu'il est en ligne est éjecté
  /// immédiatement, sans attendre sa prochaine connexion.
  void _surveillerStatutCompte() {
    _abonnementStatutCompte?.cancel();
    _abonnementStatutCompte = _authRepository.profilUtilisateurStream().listen(
      (donnees) {
        final statut = donnees?['statutCompte'] as String?;
        if (StatutCompte.estBloque(statut)) {
          if (_statutBloque == null) {
            _ejecter(statut!);
          } else if (_statutBloque != statut && mounted) {
            // Suspendu puis banni (ou l'inverse) : le texte de l'écran suit.
            setState(() => _statutBloque = statut);
          }
        } else if (_statutBloque != null) {
          _leverBlocage();
        }
      },
      onError: (_) {},
    );
  }

  /// L'Admin a réactivé le compte : le chauffeur reste connecté (voir
  /// [_ejecter]), l'app repart comme à une connexion normale.
  void _leverBlocage() {
    if (!mounted) return;
    setState(() => _statutBloque = null);
    unawaited(_chargerProfil());
  }

  /// Coupe tout (radar, position, fenêtres ouvertes) et affiche
  /// [ConducteurCompteBloquePage]. Le chauffeur reste connecté, sans
  /// notifications ni accès aux courses (les règles Firestore l'excluent
  /// déjà) : il peut écrire au support depuis cet écran et, une fois son
  /// compte réactivé, repartir sans se reconnecter.
  Future<void> _ejecter(String statut) async {
    if (_statutBloque != null || !mounted) return;
    _abonnementCourseActive?.cancel();
    _abonnementMessages?.cancel();
    _arreterRadarCourses();
    final routeShell = ModalRoute.of(context);
    if (routeShell != null) Navigator.of(context).popUntil((route) => route == routeShell);
    setState(() {
      _statutBloque = statut;
      _enLigne = false;
    });
    await _arreterEnvoiPosition();
    await NotificationsPush.instance.desactiver();
  }

  /// Vrai une fois le dossier du chauffeur validé — condition d'accès
  /// au tableau de bord (radar de courses compris). En Firebase réel,
  /// se base sur le vrai champ Firestore `statutValidation` (voir
  /// [_chargerEtapeKyc]) ; en mode démo (pas de projet Firebase
  /// configuré), conserve l'ancien repli sur
  /// `ProfilConducteur.estValide` de [ConducteurRepository].
  bool get _gateOuverte => DefaultFirebaseOptions.estConfigure
      ? _statutBloque == null && _etapeKyc == _EtapeKyc.valide
      : (_profil?.estValide ?? false);

  Future<void> _basculerStatut(bool vouloirEnLigne) async {
    // Geste de l'utilisateur : autorise le navigateur à jouer la
    // sonnerie des nouvelles courses (voir [AlerteSonore]).
    if (vouloirEnLigne) AlerteSonore.preparer();
    if (vouloirEnLigne) {
      final autorise = await _locationService.permissionAccordee();
      if (!autorise) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Autorisez la localisation pour passer en ligne')),
        );
        return;
      }
    }

    final nouveauStatut = vouloirEnLigne ? 'EN_LIGNE' : 'HORS_LIGNE';
    try {
      final statutConfirme = await _conducteurRepository.mettreAJourStatut(nouveauStatut);
      if (!mounted) return;
      setState(() => _enLigne = statutConfirme == 'EN_LIGNE');
      if (_enLigne) {
        _demarrerEnvoiPosition();
        _demarrerRadarCourses();
      } else {
        await _arreterEnvoiPosition();
        _arreterRadarCourses();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// En Firebase réel, la position part dans Firestore pour la carte
  /// "Courses en direct" de l'Admin (voir [PositionChauffeurService]).
  /// En mode démo, conserve l'ancien envoi périodique vers l'API.
  void _demarrerEnvoiPosition() {
    if (DefaultFirebaseOptions.estConfigure) {
      unawaited(_positionService.demarrer());
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) _tempsEnLigne.demarrer(uid);
      return;
    }
    _minuteurPosition?.cancel();
    _envoyerPositionReelle();
    _minuteurPosition = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _envoyerPositionReelle(),
    );
  }

  /// À attendre avant toute déconnexion : la position publiée doit être
  /// effacée tant que le chauffeur est encore authentifié.
  Future<void> _arreterEnvoiPosition() async {
    _minuteurPosition?.cancel();
    _minuteurPosition = null;
    _tempsEnLigne.arreter();
    if (DefaultFirebaseOptions.estConfigure) await _positionService.arreter();
  }

  void _surveillerCourseActive() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _abonnementCourseActive?.cancel();
    // Le départ de la course est arrondi pour les autres chauffeurs : une fois
    // la course acceptée, la position exacte du client est lue à part.
    _abonnementCourseActive = completerDepartExact(
      _courseService.streamCourseActiveChauffeur(uid),
      _courseService.streamDepartExact,
    ).listen(
      (course) {
        _positionService.definirCourse(course?.id);
        if (mounted) {
          setState(() {
            // Course acceptée : l'écran de guidage vers le client est sur l'Accueil.
            if (_courseActive == null && course != null) _indexSelectionne = 0;
            _courseActive = course;
          });
        }
        _suivreClient(course?.clientId);
      },
      onError: (_) {},
    );
  }

  /// Pendant une course, écoute la conversation avec le client : un
  /// message reçu alors que le chat n'est pas ouvert allume le badge du
  /// bouton "Message" et s'affiche aussitôt ("Répondre" ouvre le chat).
  void _suivreClient(String? clientId) {
    final id = (clientId?.isEmpty ?? true) ? null : clientId;
    if (id == _clientSuivi) return;
    _clientSuivi = id;
    _abonnementMessages?.cancel();
    _abonnementMessages = null;
    _profilClient = null;
    _detecteurMessages = null;
    final monUid = FirebaseAuth.instance.currentUser?.uid;
    if (id == null || monUid == null) return;

    _chatService.chargerProfil(id).then((profil) {
      if (mounted && _clientSuivi == id) setState(() => _profilClient = profil);
    }).catchError((_) {});

    final detecteur = DetecteurNouveauxMessages(interlocuteurUid: id);
    _detecteurMessages = detecteur;
    _abonnementMessages = _chatService.streamDernierMessage(_chatService.chatIdEntre(monUid, id)).listen(
      (message) {
        final alerter = detecteur.recevoir(message);
        if (_chatClientOuvert) detecteur.marquerLu();
        if (!mounted) return;
        setState(() {});
        if (alerter && !_chatClientOuvert && message != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$_nomClient : ${message.text}', maxLines: 2, overflow: TextOverflow.ellipsis),
              duration: const Duration(seconds: 6),
              action: SnackBarAction(label: 'Répondre', onPressed: _ouvrirChatClient),
            ),
          );
        }
      },
      onError: (_) {},
    );
  }

  String get _nomClient {
    final nom = (_profilClient?['nom'] as String?)?.trim();
    return nom == null || nom.isEmpty ? 'Votre client' : nom;
  }

  Future<void> _ouvrirChatClient() async {
    final clientId = _clientSuivi;
    if (clientId == null || _chatClientOuvert) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() {
      _chatClientOuvert = true;
      _detecteurMessages?.marquerLu();
    });
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MessagerieChatPage(
          interlocuteurUid: clientId,
          interlocuteurNom: _nomClient,
          interlocuteurSousTitre: 'Client Sprint',
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _chatClientOuvert = false;
      _detecteurMessages?.marquerLu();
    });
  }

  Future<void> _appelerClient() async {
    final telephone = (_profilClient?['telephone'] as String?)?.trim();
    if (telephone == null || telephone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Numéro du client indisponible. Écrivez-lui un message.')),
      );
      return;
    }
    final lance = await launchUrl(Uri(scheme: 'tel', path: telephone));
    if (!lance && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Impossible de lancer l'appel.")),
      );
    }
  }

  /// Guidage vers le client (course acceptée), puis vers la destination
  /// (client à bord), dans Google Maps ou Waze.
  Future<void> _naviguer() async {
    final course = _courseActive;
    if (course == null) return;
    final versDestination = course.statut == StatutCourse.enCours;
    final points = course.points;
    final adresse = versDestination ? course.adresseArrivee : course.adresseDepart;
    final app = await choisirAppNavigation(context, destination: adresse);
    if (app == null || !mounted) return;
    // La position exacte du client n'est pas encore arrivée : la navigation
    // ne vise que sa zone (~150 m), le chauffeur le sait.
    if (!versDestination && course.departArrondi) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Position exacte du client en cours de chargement : le point indiqué est approximatif (à une centaine de mètres près).'),
        ),
      );
    }
    final lien = NavigationGps.lien(
      app,
      latitude: points == null ? null : (versDestination ? points.latitudeArrivee : points.latitudeDepart),
      longitude: points == null ? null : (versDestination ? points.longitudeArrivee : points.longitudeDepart),
      adresse: adresse,
    );
    final ouvert = await NavigationGps.ouvrir(lien);
    if (!ouvert && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Impossible d'ouvrir l'application de navigation.")),
      );
    }
  }

  Future<void> _annulerCourseActive() async {
    final course = _courseActive;
    if (course == null) return;
    final motif = await demanderMotifAnnulation(context);
    if (motif == null || !mounted) return;
    setState(() => _avancementCourseEnCours = true);
    try {
      await _courseService.annulerParChauffeur(course.id, motif);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Course annulée. Vous pouvez recevoir de nouvelles demandes.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.message : "L'annulation a échoué. Vérifiez votre connexion.")),
        );
      }
    } finally {
      if (mounted) setState(() => _avancementCourseEnCours = false);
    }
  }

  Future<void> _avancerCourseActive() async {
    final course = _courseActive;
    if (course == null) return;
    setState(() => _avancementCourseEnCours = true);
    try {
      if (course.statut == StatutCourse.enCours) {
        await _courseService.terminerCourse(course);
      } else {
        await _courseService.demarrerCourse(course.id);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mise à jour impossible. Vérifiez votre connexion.')),
        );
      }
    } finally {
      if (mounted) setState(() => _avancementCourseEnCours = false);
    }
  }

  Future<void> _envoyerPositionReelle() async {
    try {
      final position = await _locationService.positionActuelle();
      await _conducteurRepository.mettreAJourPosition(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (_) {
      // Échec silencieux (API ou GPS momentanément indisponible) : la
      // prochaine tentative aura lieu au tick suivant.
    }
  }

  /// Bascule entre le vrai radar Firestore (courses réelles en attente,
  /// voir [CourseService.streamCoursesEnAttente]) et l'ancienne
  /// simulation par minuteur, selon que Firebase est configuré ou non
  /// — même repli défensif qu'ailleurs dans l'app si jamais Firebase
  /// devait être désactivé.
  void _demarrerRadarCourses() {
    if (DefaultFirebaseOptions.estConfigure) {
      _abonnementCoursesEnAttente?.cancel();
      _abonnementCoursesEnAttente =
          _courseService.streamCoursesEnAttente().listen(_traiterCoursesEnAttente);
    } else {
      _programmerProchaineCourseDemo();
    }
  }

  void _arreterRadarCourses() {
    _abonnementCoursesEnAttente?.cancel();
    _abonnementCoursesEnAttente = null;
    _minuteurNouvelleCourse?.cancel();
  }

  /// Dès qu'une course en attente apparaît (et qu'aucune bottom sheet
  /// n'est déjà affichée), propose la plus ancienne non encore refusée
  /// par ce chauffeur pendant cette session En ligne.
  void _traiterCoursesEnAttente(List<CourseFirestore> courses) {
    if (!mounted || !_enLigne || _sheetCourseOuverte || _courseActive != null) return;
    final proposables = courses.where((c) => !_idsCoursesIgnorees.contains(c.id));
    if (proposables.isEmpty) return;
    _proposerCourseReelle(proposables.first);
  }

  Future<void> _proposerCourseReelle(CourseFirestore course) async {
    final chauffeurId = FirebaseAuth.instance.currentUser?.uid;
    if (chauffeurId == null) return;
    _sheetCourseOuverte = true;
    final sonnerie = _sonner();
    final position = _positionService.dernierePosition;
    final gagnee = await afficherNouvelleCourseReelleSheet(
      context,
      course: course,
      courseService: _courseService,
      chauffeurId: chauffeurId,
      positionChauffeur: position == null ? null : LatLng(position.latitude, position.longitude),
    );
    sonnerie.cancel();
    _sheetCourseOuverte = false;
    if (!gagnee) _idsCoursesIgnorees.add(course.id);
  }

  /// Sonnerie "Nouvelle course" : tout de suite, puis toutes les 4 s tant
  /// que la proposition est affichée (le chauffeur regarde la route).
  Timer _sonner() {
    AlerteSonore.nouvelleCourse();
    return Timer.periodic(const Duration(seconds: 4), (_) => AlerteSonore.nouvelleCourse());
  }

  /// Programme l'apparition simulée d'une prochaine course, à un délai
  /// aléatoire (pour ne pas paraître mécanique), tant que le conducteur
  /// reste en ligne. Utilisé uniquement en mode démo (pas de Firebase
  /// configuré) — voir [_demarrerRadarCourses].
  void _programmerProchaineCourseDemo() {
    _minuteurNouvelleCourse?.cancel();
    final delai = Duration(seconds: 20 + _random.nextInt(20));
    _minuteurNouvelleCourse = Timer(delai, () {
      if (!mounted || !_enLigne) return;
      _declencherNouvelleCourseDemo();
    });
  }

  Future<void> _declencherNouvelleCourseDemo() async {
    final sonnerie = _sonner();
    await afficherNouvelleCourseSheet(context);
    sonnerie.cancel();
    if (mounted && _enLigne) _programmerProchaineCourseDemo();
  }

  Future<void> _seDeconnecter() async {
    _abonnementStatutCompte?.cancel();
    _abonnementCourseActive?.cancel();
    _abonnementMessages?.cancel();
    await _arreterEnvoiPosition();
    _arreterRadarCourses();
    await _authRepository.deconnecter();
    if (mounted) context.go(AppRoutes.espacePro);
  }

  @override
  Widget build(BuildContext context) {
    if (_statutBloque != null) {
      return ConducteurCompteBloquePage(statutCompte: _statutBloque!);
    }

    if (_profil == null) {
      return const Scaffold(
        backgroundColor: AppColors.fond,
        body: Center(child: CircularProgressIndicator(color: AppColors.vert)),
      );
    }

    // Email pas encore vérifié : bloqué avant même l'examen du dossier
    // KYC, quel que soit l'onglet visé.
    if (DefaultFirebaseOptions.estConfigure) {
      final utilisateur = FirebaseAuth.instance.currentUser;
      if (utilisateur != null && !utilisateur.emailVerified) {
        return const EmailVerificationPendingPage(
          destinationApresVerification: AppRoutes.conducteur,
        );
      }
    }

    // Le "Gardien" KYC : bloqué avant la carte et la bascule En ligne,
    // quel que soit l'onglet visé, tant que le dossier n'est pas validé.
    if (DefaultFirebaseOptions.estConfigure) {
      switch (_etapeKyc) {
        case _EtapeKyc.chargement:
          return const Scaffold(
            backgroundColor: AppColors.fond,
            body: Center(child: CircularProgressIndicator(color: AppColors.vert)),
          );
        case _EtapeKyc.nonEnvoye:
          return ConducteurKYCPage(
            onDossierSoumis: () => setState(() => _etapeKyc = _EtapeKyc.enAttente),
            onDeconnexion: _seDeconnecter,
          );
        case _EtapeKyc.enAttente:
          return ConducteurEnAttentePage(onDeconnexion: _seDeconnecter);
        case _EtapeKyc.valide:
          break;
      }
    } else if (!_profil!.estValide) {
      // Mode démo (pas de projet Firebase configuré) : conserve
      // l'ancien repli, `statutValidation` n'existant pas côté
      // [DemoData].
      return const ValidationPendingPage();
    }

    // Tout appui débloque le son du navigateur pour la sonnerie des
    // nouvelles courses (le chauffeur peut être déjà "En ligne" au
    // rechargement de la page, sans repasser par le bouton).
    return Listener(
      onPointerDown: (_) => AlerteSonore.preparer(),
      child: _tableauDeBord(),
    );
  }

  Widget _tableauDeBord() {
    return Scaffold(
      backgroundColor: AppColors.fond,
      body: IndexedStack(
        index: _indexSelectionne,
        children: [
          // Accueil : carte plein écran (charte Onyx & Vert dans l'onglet).
          ThemeOnyxVert(
            child: ConducteurAccueilTab(
              enLigne: _enLigne,
              onBasculerStatut: _basculerStatut,
              gainsJourFcfa: DemoData.gainsEstimesFcfa,
              onSimulerCourse: _declencherNouvelleCourseDemo,
              guidage: _courseActive == null
                  ? null
                  : GuidageCourse(
                      // Une autre course : nouveau guidage, itinéraire recalculé.
                      key: ValueKey(_courseActive!.id),
                      course: _courseActive!,
                      positions: _positionService.positions,
                      positionInitiale: _positionService.dernierePosition,
                      service: _itineraires,
                    ),
            ),
          ),
          const EcranOnyxVert(child: ConducteurMessagesTab()),
          const EcranOnyxVert(child: ConducteurGainsTab()),
          const EcranOnyxVert(child: ConducteurEvaluationsTab()),
          EcranOnyxVert(child: ConducteurCompteTab(profil: _profil, onDeconnexion: _seDeconnecter)),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_courseActive != null)
            CourseActiveBandeau(
              course: _courseActive!,
              enCours: _avancementCourseEnCours,
              onAvancer: _avancerCourseActive,
              onAppeler: _appelerClient,
              onMessage: _ouvrirChatClient,
              onNaviguer: _naviguer,
              onAnnuler: _annulerCourseActive,
              messageNonLu: _detecteurMessages?.nonLu ?? false,
            ),
          ConducteurBottomNav(
            indexSelectionne: _indexSelectionne,
            onSelection: (index) => setState(() => _indexSelectionne = index),
          ),
        ],
      ),
    );
  }
}
