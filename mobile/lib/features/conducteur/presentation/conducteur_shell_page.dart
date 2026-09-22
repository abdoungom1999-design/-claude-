import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/demo/demo_data.dart';
import '../../../core/location/device_location_service.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/data/auth_repository.dart';
import '../data/conducteur_repository.dart';
import 'tabs/conducteur_accueil_tab.dart';
import 'tabs/conducteur_compte_tab.dart';
import 'tabs/conducteur_evaluations_tab.dart';
import 'tabs/conducteur_gains_tab.dart';
import 'widgets/conducteur_bottom_nav.dart';
import 'widgets/nouvelle_course_sheet.dart';

/// Coquille de navigation de l'espace Conducteur (Sprint Conducteur) :
/// barre du bas à 4 onglets (Accueil, Gains, Évaluations, Compte).
/// Porte l'état partagé entre onglets (profil, statut En ligne/Hors
/// ligne, position) et la simulation d'arrivée de nouvelles courses.
class ConducteurShellPage extends StatefulWidget {
  const ConducteurShellPage({super.key});

  @override
  State<ConducteurShellPage> createState() => _ConducteurShellPageState();
}

class _ConducteurShellPageState extends State<ConducteurShellPage> {
  final _conducteurRepository = ConducteurRepository();
  final _authRepository = AuthRepository();
  final _locationService = DeviceLocationService();
  final _random = Random();

  int _indexSelectionne = 0;
  ProfilConducteur? _profil;
  bool _enLigne = false;
  LatLng? _dernierePosition;
  Timer? _minuteurPosition;
  Timer? _minuteurNouvelleCourse;

  @override
  void initState() {
    super.initState();
    _chargerProfil();
  }

  @override
  void dispose() {
    _minuteurPosition?.cancel();
    _minuteurNouvelleCourse?.cancel();
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
        _programmerProchaineCourse();
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
        _programmerProchaineCourse();
      } else {
        _arreterEnvoiPosition();
        _minuteurNouvelleCourse?.cancel();
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
      if (!mounted) return;
      setState(() => _dernierePosition = LatLng(position.latitude, position.longitude));
    } catch (_) {
      // Échec silencieux (API ou GPS momentanément indisponible) : la
      // prochaine tentative aura lieu au tick suivant.
    }
  }

  /// Programme l'apparition simulée d'une prochaine course, à un délai
  /// aléatoire (pour ne pas paraître mécanique), tant que le conducteur
  /// reste en ligne.
  void _programmerProchaineCourse() {
    _minuteurNouvelleCourse?.cancel();
    final delai = Duration(seconds: 20 + _random.nextInt(20));
    _minuteurNouvelleCourse = Timer(delai, () {
      if (!mounted || !_enLigne) return;
      _declencherNouvelleCourse();
    });
  }

  Future<void> _declencherNouvelleCourse() async {
    await afficherNouvelleCourseSheet(context);
    if (mounted && _enLigne) _programmerProchaineCourse();
  }

  Future<void> _seDeconnecter() async {
    _arreterEnvoiPosition();
    _minuteurNouvelleCourse?.cancel();
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

    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _indexSelectionne,
        children: [
          ConducteurAccueilTab(
            enLigne: _enLigne,
            onBasculerStatut: _basculerStatut,
            gainsJourFcfa: DemoData.gainsEstimesFcfa,
            position: _dernierePosition,
            onSimulerCourse: _declencherNouvelleCourse,
          ),
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
