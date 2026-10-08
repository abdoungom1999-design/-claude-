import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../core/demo/demo_data.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_fcfa.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/premium_dialog.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/stat_tile.dart';
import '../../../firebase_options.dart';
import '../../evaluations/data/evaluation_service.dart';
import '../../evaluations/presentation/evaluation_course.dart';
import '../../../core/widgets/onyx_vert.dart';

/// Courses terminées non encore notées par le client, avec notation en
/// retard. En Firebase réel : courses `terminee` du client sans entrée
/// dans `evaluations` (voir [EvaluationService.coursesANoter]). En mode
/// démo (pas de projet Firebase configuré) : historique de [DemoData].
class CoursesANoterPage extends StatelessWidget {
  const CoursesANoterPage({super.key, this.service, this.clientId});

  /// Injectables pour les tests.
  final EvaluationService? service;
  final String? clientId;

  @override
  Widget build(BuildContext context) {
    if (!DefaultFirebaseOptions.estConfigure && service == null) {
      return const _CoursesANoterDemo();
    }
    return _CoursesANoterReelles(
      service: service ?? EvaluationService(),
      clientId: clientId ?? FirebaseAuth.instance.currentUser?.uid,
    );
  }
}

class _CoursesANoterReelles extends StatefulWidget {
  const _CoursesANoterReelles({required this.service, required this.clientId});

  final EvaluationService service;
  final String? clientId;

  @override
  State<_CoursesANoterReelles> createState() => _CoursesANoterReellesState();
}

class _CoursesANoterReellesState extends State<_CoursesANoterReelles> {
  late Future<List<CourseANoter>> _courses = _charger();

  Future<List<CourseANoter>> _charger() {
    final clientId = widget.clientId;
    if (clientId == null) return Future.value(const []);
    return widget.service.coursesANoter(clientId);
  }

  Future<void> _recharger() async {
    final courses = _charger();
    setState(() {
      _courses = courses;
    });
    await _courses.catchError((_) => <CourseANoter>[]);
  }

  Future<void> _noter(CourseANoter aNoter) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (pageContext) => SousPageOnyx(child: Scaffold(
          appBar: AppBar(title: const Text('Noter la course')),
          body: EvaluationCourse(
            course: aNoter.course,
            nomChauffeur: aNoter.nomChauffeur,
            service: widget.service,
            titre: 'Noter votre course',
            libelleIgnorer: 'Plus tard',
            libelleRetour: 'Retour à la liste',
            onTerminer: () => Navigator.of(pageContext).pop(),
          ),
        )),
      ),
    );
    // Une course notée disparaît de la liste.
    if (mounted) await _recharger();
  }

  @override
  Widget build(BuildContext context) {
    return SousPageOnyx(child: Scaffold(
      appBar: AppBar(title: const Text('Courses à noter')),
      body: SafeArea(
        child: FutureBuilder<List<CourseANoter>>(
          future: _courses,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator(color: AppColors.vert));
            }
            if (snapshot.hasError) {
              return _Erreur(onReessayer: _recharger);
            }
            final courses = snapshot.data ?? const [];
            return RefreshIndicator(
              color: AppColors.vert,
              onRefresh: _recharger,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  _CompteurAvis(nombre: courses.length),
                  const SizedBox(height: 20),
                  if (courses.isEmpty)
                    const _ToutEstNote()
                  else
                    for (final aNoter in courses)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _CarteCourseANoter(
                          depart: aNoter.course.adresseDepart,
                          arrivee: aNoter.course.adresseArrivee,
                          detail: [
                            formaterFcfa(aNoter.course.prixFcfa),
                            _date(aNoter.course.timestamp),
                            if (aNoter.nomChauffeur?.trim().isNotEmpty == true) 'avec ${aNoter.nomChauffeur!.trim()}',
                          ].join(' · '),
                          onNoter: () => _noter(aNoter),
                        ),
                      ),
                ],
              ),
            );
          },
        ),
      ),
    ));
  }
}

String _date(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';

class _CompteurAvis extends StatelessWidget {
  const _CompteurAvis({required this.nombre});

  final int nombre;

  @override
  Widget build(BuildContext context) {
    return StatTile(
      label: 'Avis en attente',
      valeur: '$nombre',
      icon: Icons.star_border_rounded,
      accent: nombre == 0 ? AppColors.texteDiscret : AppColors.vert,
    );
  }
}

class _ToutEstNote extends StatelessWidget {
  const _ToutEstNote();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      child: Column(
        children: [
          Text('😊', style: TextStyle(fontSize: 40)),
          SizedBox(height: 12),
          Text(
            'Tout est noté !',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 6),
          Text(
            'Merci de partager vos retours sur vos dernières courses.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: AppColors.texteDiscret),
          ),
        ],
      ),
    );
  }
}

class _CarteCourseANoter extends StatelessWidget {
  const _CarteCourseANoter({
    required this.depart,
    required this.arrivee,
    required this.detail,
    required this.onNoter,
  });

  final String depart;
  final String arrivee;
  final String detail;
  final VoidCallback onNoter;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$depart → $arrivee',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(detail, style: const TextStyle(fontSize: 12, color: AppColors.texteDiscret)),
          const SizedBox(height: 12),
          PrimaryButton(
            label: 'Noter cette course',
            icon: Icons.star_border_rounded,
            onPressed: onNoter,
          ),
        ],
      ),
    );
  }
}

class _Erreur extends StatelessWidget {
  const _Erreur({required this.onReessayer});

  final VoidCallback onReessayer;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 44, color: AppColors.texteDiscret),
            const SizedBox(height: 12),
            const Text(
              'Impossible de charger vos courses.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onReessayer, child: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}

/// Version démo (sans Firebase), inchangée.
class _CoursesANoterDemo extends StatefulWidget {
  const _CoursesANoterDemo();

  @override
  State<_CoursesANoterDemo> createState() => _CoursesANoterDemoState();
}

class _CoursesANoterDemoState extends State<_CoursesANoterDemo> {
  List<CourseHistorique> get _aNoter =>
      DemoData.historique().where((c) => c.noteDonnee == null).toList();

  Future<void> _noter(CourseHistorique course) async {
    final note = await showDialog<int>(
      context: context,
      builder: (_) => _DialogNotation(course: course),
    );
    if (note == null) return;
    setState(() => course.noteDonnee = note);
    if (!mounted) return;
    PremiumDialog.afficher(
      context,
      icon: Icons.star_rounded,
      titre: 'Merci pour votre avis !',
      message: 'Votre note a bien été transmise au conducteur.',
      succes: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final courses = _aNoter;

    return SousPageOnyx(child: Scaffold(
      appBar: AppBar(title: const Text('Courses à noter')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            StatTile(
              label: 'Avis en attente',
              valeur: '${courses.length}',
              icon: Icons.star_border_rounded,
              accent: courses.isEmpty ? AppColors.texteDiscret : AppColors.vert,
            ),
            const SizedBox(height: 20),
            if (courses.isEmpty)
              const AppCard(
                child: Column(
                  children: [
                    Text('😊', style: TextStyle(fontSize: 40)),
                    SizedBox(height: 12),
                    Text(
                      'Tout est noté !',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Merci de partager vos retours sur vos dernières courses.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: AppColors.texteDiscret),
                    ),
                  ],
                ),
              )
            else
              ...courses.map(
                (course) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${course.adresseDepart} → ${course.adresseArrivee}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${course.prixFcfa} FCFA · '
                          '${course.date.day.toString().padLeft(2, '0')}/'
                          '${course.date.month.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 12, color: AppColors.texteDiscret),
                        ),
                        const SizedBox(height: 12),
                        PrimaryButton(
                          label: 'Noter cette course',
                          icon: Icons.star_border_rounded,
                          onPressed: () => _noter(course),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ));
  }
}

class _DialogNotation extends StatefulWidget {
  const _DialogNotation({required this.course});

  final CourseHistorique course;

  @override
  State<_DialogNotation> createState() => _DialogNotationState();
}

class _DialogNotationState extends State<_DialogNotation> {
  int _note = 5;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.carte,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.bordVerre),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Comment s\'est passée votre course ?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final valeur = i + 1;
                return IconButton(
                  onPressed: () => setState(() => _note = valeur),
                  icon: Icon(
                    valeur <= _note ? Icons.star_rounded : Icons.star_border_rounded,
                    color: AppColors.etoile,
                    size: 32,
                  ),
                );
              }),
            ),
            const SizedBox(height: 18),
            PrimaryButton(
              label: 'Envoyer ma note',
              onPressed: () => Navigator.of(context).pop(_note),
            ),
          ],
        ),
      ),
    );
  }
}
