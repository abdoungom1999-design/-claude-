import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/demo/admin_demo_data.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../firebase_options.dart';
import '../../../courses/data/course_service.dart';
import '../../data/suivi_direct_service.dart';

/// Page "Courses en direct" : carte (OpenStreetMap, sans clé API) avec
/// les chauffeurs en ligne positionnés en temps réel, et la liste des
/// courses en cours sur le côté.
///
/// En Firebase réel, tout vient de Firestore (voir [SuiviDirectService]) :
/// positions publiées par les téléphones des chauffeurs en ligne,
/// courses `acceptee` / `en_cours`. En mode démo (pas de projet Firebase
/// configuré), affiche les données factices d'[AdminDemoData].
class AdminCoursesDirectSection extends StatelessWidget {
  const AdminCoursesDirectSection({super.key, this.service});

  /// Injectable pour les tests ; par défaut, lecture Firestore.
  final SuiviDirectService? service;

  @override
  Widget build(BuildContext context) {
    if (!DefaultFirebaseOptions.estConfigure && service == null) {
      return _VueCoursesEnDirect.demo();
    }
    return _SuiviTempsReel(service: service ?? SuiviDirectService());
  }
}

class _SuiviTempsReel extends StatefulWidget {
  const _SuiviTempsReel({required this.service});

  final SuiviDirectService service;

  @override
  State<_SuiviTempsReel> createState() => _SuiviTempsReelState();
}

class _SuiviTempsReelState extends State<_SuiviTempsReel> {
  late final Stream<List<PositionChauffeurDirect>> _positions = widget.service.streamPositions();
  late final Stream<List<CourseFirestore>> _courses = widget.service.streamCoursesEnCours();
  late final Stream<Map<String, String>> _noms = widget.service.streamNomsChauffeurs();

  /// Rafraîchit "il y a X s" et bascule en gris les signaux perdus, même
  /// quand Firestore n'envoie rien de neuf (chauffeur qui a fermé l'app).
  late final Timer _horloge;

  @override
  void initState() {
    super.initState();
    _horloge = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _horloge.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PositionChauffeurDirect>>(
      stream: _positions,
      builder: (context, positions) => StreamBuilder<List<CourseFirestore>>(
        stream: _courses,
        builder: (context, courses) => StreamBuilder<Map<String, String>>(
          stream: _noms,
          builder: (context, noms) => _VueCoursesEnDirect(
            positions: positions.data ?? const [],
            courses: courses.data ?? const [],
            noms: noms.data ?? const {},
            maintenant: DateTime.now(),
            chargement: !positions.hasData || !courses.hasData,
            erreur: positions.hasError || courses.hasError,
          ),
        ),
      ),
    );
  }
}

class _VueCoursesEnDirect extends StatefulWidget {
  const _VueCoursesEnDirect({
    required this.positions,
    required this.courses,
    required this.noms,
    required this.maintenant,
    this.chargement = false,
    this.erreur = false,
  });

  /// Données factices d'[AdminDemoData], présentées comme des données
  /// réelles (chaque course a son chauffeur positionné).
  factory _VueCoursesEnDirect.demo() {
    final maintenant = DateTime.now();
    final demo = AdminDemoData.coursesEnDirect();
    return _VueCoursesEnDirect(
      maintenant: maintenant,
      positions: [
        for (final (i, c) in demo.indexed)
          PositionChauffeurDirect(uid: 'demo-$i', latitude: c.latitude, longitude: c.longitude, majLe: maintenant),
      ],
      courses: [
        for (final (i, c) in demo.indexed)
          CourseFirestore(
            id: c.id,
            clientId: '',
            chauffeurId: 'demo-$i',
            statut: StatutCourse.enCours,
            type: 'PASSAGER',
            adresseDepart: c.description.split(' -> ').first,
            adresseArrivee: c.description.split(' -> ').last,
            prixFcfa: 0,
            methodePaiement: '',
            timestamp: maintenant,
          ),
      ],
      noms: {for (final (i, c) in demo.indexed) 'demo-$i': c.chauffeur},
    );
  }

  final List<PositionChauffeurDirect> positions;
  final List<CourseFirestore> courses;
  final Map<String, String> noms;
  final DateTime maintenant;
  final bool chargement;
  final bool erreur;

  @override
  State<_VueCoursesEnDirect> createState() => _VueCoursesEnDirectState();
}

class _VueCoursesEnDirectState extends State<_VueCoursesEnDirect> {
  static const _centreDakar = LatLng(14.6928, -17.4467);

  final _carte = MapController();

  String _nom(String? uid) => widget.noms[uid] ?? 'Chauffeur';

  @override
  Widget build(BuildContext context) {
    final visibles = [
      for (final p in widget.positions)
        if (EtatSignal.pour(p.majLe, widget.maintenant) != EtatSignal.expire) p,
    ];
    final positionsParUid = {for (final p in visibles) p.uid: p};
    final enCourse = {for (final c in widget.courses) c.chauffeurId};

    var nbEnCourse = 0, nbDisponibles = 0, nbPerdus = 0;
    for (final p in visibles) {
      if (EtatSignal.pour(p.majLe, widget.maintenant) == EtatSignal.perdu) {
        nbPerdus++;
      } else if (enCourse.contains(p.uid)) {
        nbEnCourse++;
      } else {
        nbDisponibles++;
      }
    }

    return SizedBox(
      height: 620,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: AppCard(
              padding: EdgeInsets.zero,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _carte,
                      options: const MapOptions(
                        initialCenter: _centreDakar,
                        initialZoom: 12.5,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'sn.groupesantine.sprint',
                        ),
                        MarkerLayer(
                          markers: [
                            for (final p in visibles)
                              Marker(
                                point: LatLng(p.latitude, p.longitude),
                                width: 46,
                                height: 46,
                                child: _MarqueurChauffeur(
                                  nom: _nom(p.uid),
                                  etat: EtatSignal.pour(p.majLe, widget.maintenant),
                                  enCourse: enCourse.contains(p.uid),
                                  derniereMaj: ilYA(p.majLe, widget.maintenant),
                                ),
                              ),
                          ],
                        ),
                        const RichAttributionWidget(
                          attributions: [
                            TextSourceAttribution('© OpenStreetMap contributors'),
                          ],
                        ),
                      ],
                    ),
                    Positioned(
                      top: 14,
                      left: 14,
                      child: _Legende(enCourse: nbEnCourse, disponibles: nbDisponibles, perdus: nbPerdus),
                    ),
                    if (!widget.chargement && visibles.isEmpty)
                      const Positioned(
                        bottom: 36,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: _Bulle(texte: 'Aucun chauffeur en ligne pour le moment'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            flex: 1,
            child: ListView(
              children: [
                Text(
                  widget.courses.length <= 1
                      ? '${widget.courses.length} course en cours'
                      : '${widget.courses.length} courses en cours',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                if (widget.erreur)
                  const _Bulle(
                    texte: 'Lecture impossible. Vérifiez que vous êtes connecté avec le compte Admin '
                        'et que les règles Firestore sont publiées.',
                  )
                else if (widget.chargement)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator(color: AppColors.orange)),
                  )
                else if (widget.courses.isEmpty)
                  const _Bulle(texte: 'Aucune course en cours.')
                else
                  for (final course in widget.courses)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _CarteCourseEnDirect(
                        course: course,
                        chauffeur: _nom(course.chauffeurId),
                        position: positionsParUid[course.chauffeurId],
                        maintenant: widget.maintenant,
                        onLocaliser: (p) => _carte.move(LatLng(p.latitude, p.longitude), 15),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MarqueurChauffeur extends StatelessWidget {
  const _MarqueurChauffeur({
    required this.nom,
    required this.etat,
    required this.enCourse,
    required this.derniereMaj,
  });

  final String nom;
  final EtatSignal etat;
  final bool enCourse;
  final String derniereMaj;

  @override
  Widget build(BuildContext context) {
    final perdu = etat == EtatSignal.perdu;
    final couleur = perdu ? AppColors.grey : (enCourse ? AppColors.orange : AppColors.vert);
    final libelle = perdu ? 'Signal perdu' : (enCourse ? 'En course' : 'Disponible');

    return Tooltip(
      message: '$nom · $libelle · $derniereMaj',
      child: Container(
        decoration: BoxDecoration(
          color: couleur,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: couleur.withValues(alpha: 0.4),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Icon(
          perdu ? Icons.signal_wifi_off_rounded : Icons.two_wheeler_rounded,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }
}

class _Legende extends StatelessWidget {
  const _Legende({required this.enCourse, required this.disponibles, required this.perdus});

  final int enCourse;
  final int disponibles;
  final int perdus;

  @override
  Widget build(BuildContext context) {
    Widget element(Color couleur, String texte) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: couleur, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(texte, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: AppColors.shadowSoft, blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          element(AppColors.orange, 'En course : $enCourse'),
          element(AppColors.vert, 'Disponibles : $disponibles'),
          element(AppColors.grey, 'Signal perdu : $perdus'),
        ],
      ),
    );
  }
}

class _Bulle extends StatelessWidget {
  const _Bulle({required this.texte});

  final String texte;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Text(texte, style: const TextStyle(fontSize: 12.5, color: AppColors.grey)),
    );
  }
}

class _CarteCourseEnDirect extends StatelessWidget {
  const _CarteCourseEnDirect({
    required this.course,
    required this.chauffeur,
    required this.position,
    required this.maintenant,
    required this.onLocaliser,
  });

  final CourseFirestore course;
  final String chauffeur;
  final PositionChauffeurDirect? position;
  final DateTime maintenant;
  final void Function(PositionChauffeurDirect position) onLocaliser;

  @override
  Widget build(BuildContext context) {
    final clientABord = course.statut == StatutCourse.enCours;
    final numero = course.id.length > 6 ? course.id.substring(0, 6).toUpperCase() : course.id;
    final signal = position == null ? null : EtatSignal.pour(position!.majLe, maintenant);

    return AppCard(
      padding: const EdgeInsets.all(16),
      onTap: position == null ? null : () => onLocaliser(position!),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: clientABord ? AppColors.vert : AppColors.orange,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Course $numero',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              Text(
                clientABord ? 'En course' : 'Vers le client',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: clientABord ? AppColors.vert : AppColors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${course.adresseDepart} → ${course.adresseArrivee}',
            style: const TextStyle(fontSize: 12.5, color: AppColors.text),
          ),
          const SizedBox(height: 6),
          Text(
            'Chauffeur : $chauffeur',
            style: const TextStyle(fontSize: 11.5, color: AppColors.grey),
          ),
          const SizedBox(height: 2),
          Text(
            switch (signal) {
              null => 'Aucune position reçue',
              EtatSignal.perdu => 'Signal perdu (${ilYA(position!.majLe, maintenant)})',
              _ => 'Position ${ilYA(position!.majLe, maintenant)}',
            },
            style: TextStyle(
              fontSize: 11.5,
              color: signal == EtatSignal.actif ? AppColors.vert : AppColors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (course.prixFcfa > 0) ...[
            const SizedBox(height: 2),
            Text(
              '${course.prixFcfa} FCFA',
              style: const TextStyle(fontSize: 11.5, color: AppColors.grey),
            ),
          ],
        ],
      ),
    );
  }
}
