import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/demo/demo_data.dart';
import '../../../core/location/device_location_service.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/email_verification_pending_page.dart';
import '../../../firebase_options.dart';
import '../../auth/data/auth_repository.dart';
import '../../courses/data/course_service.dart';
import '../data/conducteur_repository.dart';
import 'tabs/conducteur_accueil_tab.dart';
import 'tabs/conducteur_compte_tab.dart';
import 'tabs/conducteur_evaluations_tab.dart';
import 'tabs/conducteur_gains_tab.dart';
import 'tabs/conducteur_messages_tab.dart';
import 'validation_pending_page.dart';
import 'widgets/conducteur_bottom_nav.dart';
import 'widgets/nouvelle_course_reelle_sheet.dart';
import 'widgets/nouvelle_course_sheet.dart';

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
  final _random = Random();

  int _indexSelectionne = 0;
  ProfilConducteur? _profil;
  bool _enLigne = false;
  Timer? _minuteurPosition;
  Timer? _minuteurNouvelleCourse;
  StreamSubscription<List<CourseFirestore>>? _abonnementCoursesEnAttente;
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
      if (_enLigne) {
        _demarrerEnvoiPosition();
        _demarrerRadarCourses();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _basculerStatut(bool vouloirEnLigne) async {
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
        _arreterEnvoiPosition();
        _arreterRadarCourses();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _demarrerEnvoiPosition() {
    _minuteurPosition?.cancel();
    _envoyerPositionReelle();
    _minuteurPosition = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _envoyerPositionReelle(),
    );
  }

  void _arreterEnvoiPosition() {
    _minuteurPosition?.cancel();
    _minuteurPosition = null;
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
    if (!mounted || !_enLigne || _sheetCourseOuverte) return;
    final proposables = courses.where((c) => !_idsCoursesIgnorees.contains(c.id));
    if (proposables.isEmpty) return;
    _proposerCourseReelle(proposables.first);
  }

  Future<void> _proposerCourseReelle(CourseFirestore course) async {
    final chauffeurId = FirebaseAuth.instance.currentUser?.uid;
    if (chauffeurId == null) return;
    _sheetCourseOuverte = true;
    final gagnee = await afficherNouvelleCourseReelleSheet(
      context,
      course: course,
      courseService: _courseService,
      chauffeurId: chauffeurId,
    );
    _sheetCourseOuverte = false;
    if (!gagnee) _idsCoursesIgnorees.add(course.id);
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
    await afficherNouvelleCourseSheet(context);
    if (mounted && _enLigne) _programmerProchaineCourseDemo();
  }

  Future<void> _seDeconnecter() async {
    _arreterEnvoiPosition();
    _arreterRadarCourses();
    await _authRepository.deconnecter();
    if (mounted) context.go(AppRoutes.espacePro);
  }

  @override
  Widget build(BuildContext context) {
    if (_profil == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.orange)),
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

    // Dossier pas encore validé (KYC en attente) : bloqué avant la carte
    // et la bascule En ligne, quel que soit l'onglet visé.
    if (!_profil!.estValide) {
      return const ValidationPendingPage();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _indexSelectionne,
        children: [
          ConducteurAccueilTab(
            enLigne: _enLigne,
            onBasculerStatut: _basculerStatut,
            gainsJourFcfa: DemoData.gainsEstimesFcfa,
            onSimulerCourse: _declencherNouvelleCourseDemo,
          ),
          const ConducteurMessagesTab(),
          const ConducteurGainsTab(),
          const ConducteurEvaluationsTab(),
          ConducteurCompteTab(profil: _profil, onDeconnexion: _seDeconnecter),
        ],
      ),
      bottomNavigationBar: ConducteurBottomNav(
        indexSelectionne: _indexSelectionne,
        onSelection: (index) => setState(() => _indexSelectionne = index),
      ),
    );
  }
}
