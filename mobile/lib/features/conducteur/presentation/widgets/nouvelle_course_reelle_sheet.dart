import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/format_fcfa.dart';
import '../../../courses/data/course_service.dart';
import '../../../courses/data/position_chauffeur.dart';

/// Affiche la bottom sheet "Nouvelle course disponible !" pour une
/// vraie course Firestore en attente (voir
/// [CourseService.streamCoursesEnAttente]). Contrairement à la version
/// démo ([afficherNouvelleCourseSheet]), "Accepter" écrit réellement
/// dans Firestore via [CourseService.accepterCourse] (transaction) :
/// retourne `true` si ce chauffeur a remporté la course, `false`
/// sinon (refusée, délai écoulé, ou déjà prise par un autre
/// chauffeur pendant la transaction).
///
/// [positionChauffeur] (dernier relevé GPS du chauffeur, s'il en a un) sert à
/// afficher à quelle distance il est du client : sans adresse écrite (départ
/// pris sur le GPS du client), c'est ce qui lui permet de juger la course.
Future<bool> afficherNouvelleCourseReelleSheet(
  BuildContext context, {
  required CourseFirestore course,
  required CourseService courseService,
  required String chauffeurId,
  LatLng? positionChauffeur,
}) async {
  final resultat = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (_) => _NouvelleCourseReelleSheet(
      course: course,
      courseService: courseService,
      chauffeurId: chauffeurId,
      positionChauffeur: positionChauffeur,
    ),
  );
  return resultat ?? false;
}

class _NouvelleCourseReelleSheet extends StatefulWidget {
  const _NouvelleCourseReelleSheet({
    required this.course,
    required this.courseService,
    required this.chauffeurId,
    this.positionChauffeur,
  });

  final CourseFirestore course;
  final CourseService courseService;
  final String chauffeurId;
  final LatLng? positionChauffeur;

  @override
  State<_NouvelleCourseReelleSheet> createState() =>
      _NouvelleCourseReelleSheetState();
}

class _NouvelleCourseReelleSheetState extends State<_NouvelleCourseReelleSheet>
    with SingleTickerProviderStateMixin {
  static const int _dureeTotaleSecondes = 15;
  int _secondesRestantes = _dureeTotaleSecondes;
  Timer? _minuteur;
  bool _enCours = false;

  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _minuteur = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondesRestantes <= 1) {
        _minuteur?.cancel();
        if (mounted) Navigator.of(context).pop(false);
        return;
      }
      setState(() => _secondesRestantes--);
    });
  }

  @override
  void dispose() {
    _minuteur?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _accepter() async {
    _minuteur?.cancel();
    setState(() => _enCours = true);
    final gagnee = await widget.courseService.accepterCourse(
      courseId: widget.course.id,
      chauffeurId: widget.chauffeurId,
    );
    if (!mounted) return;
    if (!gagnee) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cette course vient d\'être prise par un autre chauffeur.'),
        ),
      );
    }
    Navigator.of(context).pop(gagnee);
  }

  /// Distance et temps jusqu'au client, d'après la position du chauffeur ;
  /// `null` si l'une des deux positions manque.
  Approche? get _approche {
    final moi = widget.positionChauffeur;
    final points = widget.course.points;
    if (moi == null || points == null) return null;
    return Approche.estimer(
      latChauffeur: moi.latitude,
      lngChauffeur: moi.longitude,
      latCible: points.latitudeDepart,
      lngCible: points.longitudeDepart,
    );
  }

  @override
  Widget build(BuildContext context) {
    final estColis = widget.course.type == 'COLIS';
    final approche = _approche;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      decoration: const BoxDecoration(
        color: AppColors.carte,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        border: Border(top: BorderSide(color: AppColors.bordVerre)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.bord,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.vertTeinte,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  estColis ? Icons.inventory_2_outlined : Icons.two_wheeler_rounded,
                  color: AppColors.vert,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                estColis ? 'Nouvelle livraison !' : 'Nouvelle course !',
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formaterFcfa(widget.course.prixFcfa),
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        color: AppColors.texte,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.course.libellePaiement,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.texteDiscret),
                    ),
                  ],
                ),
              ),
              _CompteARebours(
                secondesRestantes: _secondesRestantes,
                dureeTotale: _dureeTotaleSecondes,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.carteHaute,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LigneInfo(
                  icon: Icons.my_location,
                  texte: widget.course.adresseDepart,
                  detail: approche == null ? null : _libelleApproche(approche),
                ),
                const SizedBox(height: 10),
                _LigneInfo(
                  icon: Icons.location_on_outlined,
                  texte: widget.course.adresseArrivee,
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _enCours ? null : () => Navigator.of(context).pop(false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    side: const BorderSide(color: AppColors.bord),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text(
                    'Refuser',
                    style: TextStyle(color: AppColors.texteDiscret, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 2,
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    final eclat = 0.25 + _pulseController.value * 0.35;
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.vert.withValues(alpha: eclat),
                            blurRadius: 22,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: child,
                    );
                  },
                  child: ElevatedButton(
                    onPressed: _enCours ? null : _accepter,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.vert,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: _enCours
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.onyx),
                            ),
                          )
                        : const Text(
                            'ACCEPTER',
                            style: TextStyle(
                              color: AppColors.onyx,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              letterSpacing: 0.5,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompteARebours extends StatelessWidget {
  const _CompteARebours({required this.secondesRestantes, required this.dureeTotale});

  final int secondesRestantes;
  final int dureeTotale;

  @override
  Widget build(BuildContext context) {
    final progression = secondesRestantes / dureeTotale;

    return SizedBox(
      width: 58,
      height: 58,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 58,
            height: 58,
            child: CircularProgressIndicator(
              value: progression,
              strokeWidth: 5,
              backgroundColor: AppColors.carteHaute,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.vert),
            ),
          ),
          Text(
            '$secondesRestantes',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

/// « À ~1,2 km de vous · ~4 min » : le chemin jusqu'au client, estimé à vol d'oiseau.
String _libelleApproche(Approche approche) {
  final distance = approche.distanceKm < 1
      ? '${(approche.distanceKm * 100).round() * 10} m'
      : '${approche.distanceKm.toStringAsFixed(1).replaceAll('.', ',')} km';
  return 'À ~$distance de vous · ~${approche.minutes} min';
}

class _LigneInfo extends StatelessWidget {
  const _LigneInfo({required this.icon, required this.texte, this.detail});

  final IconData icon;
  final String texte;

  /// Précision sous le texte (distance jusqu'au client).
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.texteDiscret),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                texte,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
              ),
              if (detail != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    detail!,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.vert),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
