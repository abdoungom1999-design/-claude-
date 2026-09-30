import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/demo/demo_data.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/onyx_light.dart';
import '../../../core/widgets/premium_dialog.dart';
import '../../../core/utils/format_fcfa.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../firebase_options.dart';
import '../../client/presentation/suivi_course_page.dart';
import '../../courses/data/course_service.dart';
import '../../support/data/support_service.dart';
import 'detail_course_page.dart';
import 'receipts_page.dart';

/// Onglet Activité : bascule Course immédiate / Livraison / Réservations,
/// course en cours (à suivre), historique et accès au support.
///
/// En Firebase réel : les vraies courses du client (collection
/// `courses`), chacune ouvrant son détail ([DetailCoursePage] : reçu et
/// "Signaler un problème"). En mode démo : l'historique de [DemoData].
class ActiviteTabPage extends StatefulWidget {
  const ActiviteTabPage({super.key, this.courseService, this.clientId, this.supportService});

  /// Injectables pour les tests (courses réelles sans Firebase).
  final CourseService? courseService;
  final String? clientId;
  final SupportService? supportService;

  @override
  State<ActiviteTabPage> createState() => _ActiviteTabPageState();
}

class _ActiviteTabPageState extends State<ActiviteTabPage> {
  late final String? _clientId = widget.clientId ??
      (DefaultFirebaseOptions.estConfigure ? FirebaseAuth.instance.currentUser?.uid : null);
  late final Stream<List<CourseFirestore>>? _courses = _clientId == null
      ? null
      : (widget.courseService ?? CourseService()).streamCoursesClient(_clientId);

  @override
  Widget build(BuildContext context) {
    final courses = _courses;
    final onglets = courses == null
        ? TabBarView(
            children: [
              _OngletActivite(
                typeFiltre: 'PASSAGER',
                labelCta: 'Commander une course',
                onCta: () => context.push(AppRoutes.clientPassager),
              ),
              _OngletActivite(
                typeFiltre: 'COLIS',
                labelCta: 'Envoyer un colis',
                onCta: () => context.push(AppRoutes.clientColis),
              ),
              _OngletActivite(
                typeFiltre: null,
                labelCta: 'Découvrir les réservations',
                onCta: () => PremiumDialog.bientotDisponible(context, 'Réservations'),
                aucuneDonneePossible: true,
              ),
            ],
          )
        : StreamBuilder<List<CourseFirestore>>(
            stream: courses,
            builder: (context, instantane) {
              if (instantane.hasError) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Impossible de charger votre activité. Vérifiez votre connexion.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.grey),
                    ),
                  ),
                );
              }
              if (!instantane.hasData) {
                return const Center(child: CircularProgressIndicator(color: AppColors.orange));
              }
              final toutes = instantane.data!;
              return TabBarView(
                children: [
                  _OngletReel(
                    courses: [for (final c in toutes) if (c.type != 'COLIS') c],
                    clientId: _clientId!,
                    supportService: widget.supportService,
                    labelCta: 'Commander une course',
                    onCta: () => context.push(AppRoutes.clientPassager),
                  ),
                  _OngletReel(
                    courses: [for (final c in toutes) if (c.type == 'COLIS') c],
                    clientId: _clientId,
                    supportService: widget.supportService,
                    labelCta: 'Envoyer un colis',
                    onCta: () => context.push(AppRoutes.clientColis),
                  ),
                  _OngletActivite(
                    typeFiltre: null,
                    labelCta: 'Découvrir les réservations',
                    onCta: () => PremiumDialog.bientotDisponible(context, 'Réservations'),
                    aucuneDonneePossible: true,
                  ),
                ],
              );
            },
          );
    return ThemeOnyxLight(
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          backgroundColor: AppColors.fondClair,
          body: FondOnyxLight(
            child: SafeArea(
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Activité',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: AppColors.onyx),
                      ),
                    ),
                  ),
                  // Onglets « pilule » : la sélection en Onyx dans une carte verre.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: CarteVerre(
                      rayon: 22,
                      padding: const EdgeInsets.all(4),
                      child: TabBar(
                        dividerColor: Colors.transparent,
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicator: BoxDecoration(color: AppColors.onyx, borderRadius: BorderRadius.circular(18)),
                        labelColor: Colors.white,
                        unselectedLabelColor: AppColors.onyx,
                        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                        labelPadding: EdgeInsets.zero,
                        labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                        unselectedLabelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                        tabs: const [
                          Tab(height: 38, text: 'Course immédiate'),
                          Tab(height: 38, text: 'Livraison'),
                          Tab(height: 38, text: 'Réservations'),
                        ],
                      ),
                    ),
                  ),
                  Expanded(child: onglets),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OngletActivite extends StatelessWidget {
  const _OngletActivite({
    required this.typeFiltre,
    required this.labelCta,
    required this.onCta,
    this.aucuneDonneePossible = false,
  });

  /// null pour "Réservations" : aucune course historique ne correspond,
  /// la fonctionnalité n'existe pas encore côté modèle de données.
  final String? typeFiltre;
  final String labelCta;
  final VoidCallback onCta;
  final bool aucuneDonneePossible;

  @override
  Widget build(BuildContext context) {
    final historique = aucuneDonneePossible
        ? const <CourseHistorique>[]
        : DemoData.historique(type: typeFiltre);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      children: [
        AppCard(
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: AppColors.fondClair,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.local_taxi_outlined,
                  color: AppColors.onyx,
                  size: 26,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Aucune course en cours',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.onyx),
              ),
              const SizedBox(height: 4),
              Text(
                aucuneDonneePossible
                    ? 'Les réservations à l\'avance arrivent bientôt'
                    : 'Vos courses en cours apparaîtront ici',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, color: AppColors.texteDiscret),
              ),
              const SizedBox(height: 16),
              PrimaryButton(label: labelCta, onPressed: onCta),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Historique récent',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: AppColors.onyx),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.orange, textStyle: const TextStyle(fontWeight: FontWeight.w700)),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ReceiptsPage()),
              ),
              child: const Text('Reçus'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (historique.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text(
                'Aucun historique pour le moment',
                style: TextStyle(fontSize: 12.5, color: AppColors.texteDiscret),
              ),
            ),
          )
        else
          ...historique.map(
            (course) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CarteHistorique(course: course),
            ),
          ),
      ],
    );
  }
}

class _CarteHistorique extends StatelessWidget {
  const _CarteHistorique({required this.course});

  final CourseHistorique course;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.orangeLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              course.type == 'COLIS'
                  ? Icons.inventory_2_outlined
                  : Icons.two_wheeler_rounded,
              color: AppColors.orange,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${course.adresseDepart} → ${course.adresseArrivee}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.onyx),
                ),
                Text(
                  '${course.statut} · ${course.date.day.toString().padLeft(2, '0')}/'
                  '${course.date.month.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.texteDiscret),
                ),
              ],
            ),
          ),
          Text(
            '${course.prixFcfa} FCFA',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.onyx),
          ),
        ],
      ),
    );
  }
}

/// Onglet de l'activité réelle : course en cours à suivre (ou appel à
/// commander), puis historique ; chaque course ouvre son détail.
class _OngletReel extends StatelessWidget {
  const _OngletReel({
    required this.courses,
    required this.clientId,
    required this.labelCta,
    required this.onCta,
    this.supportService,
  });

  final List<CourseFirestore> courses;
  final String clientId;
  final SupportService? supportService;
  final String labelCta;
  final VoidCallback onCta;

  void _ouvrir(BuildContext context, CourseFirestore course) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailCoursePage(course: course, clientId: clientId, supportService: supportService),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enCours = [for (final c in courses) if (c.estActive) c];
    final historique = [for (final c in courses) if (!c.estActive) c];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      children: [
        if (enCours.isEmpty)
          AppCard(
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(color: AppColors.fondClair, shape: BoxShape.circle),
                  child: const Icon(Icons.two_wheeler_rounded, color: AppColors.onyx, size: 26),
                ),
                const SizedBox(height: 14),
                const Text('Aucune course en cours', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.onyx)),
                const SizedBox(height: 4),
                const Text(
                  'Vos courses en cours apparaîtront ici',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: AppColors.texteDiscret),
                ),
                const SizedBox(height: 16),
                PrimaryButton(label: labelCta, onPressed: onCta),
              ],
            ),
          )
        else
          for (final course in enCours)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(course.libelleStatut,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.orange)),
                    const SizedBox(height: 6),
                    Text(
                      '${course.adresseDepart} → ${course.adresseArrivee}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.onyx),
                    ),
                    const SizedBox(height: 12),
                    PrimaryButton(
                      label: 'Suivre ma course',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => SuiviCoursePage(courseId: course.id)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 28),
        const Text(
          'Historique',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: AppColors.onyx),
        ),
        const SizedBox(height: 12),
        if (historique.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text('Aucun historique pour le moment', style: TextStyle(fontSize: 12.5, color: AppColors.grey)),
            ),
          )
        else
          for (final course in historique)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CarteCourseReelle(course: course, onTap: () => _ouvrir(context, course)),
            ),
      ],
    );
  }
}

class _CarteCourseReelle extends StatelessWidget {
  const _CarteCourseReelle({required this.course, required this.onTap});

  final CourseFirestore course;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = course.timestamp;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AppCard(
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: AppColors.orangeLight, borderRadius: BorderRadius.circular(12)),
                child: Icon(
                  course.type == 'COLIS' ? Icons.inventory_2_outlined : Icons.two_wheeler_rounded,
                  color: AppColors.orange,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${course.adresseDepart} → ${course.adresseArrivee}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.onyx),
                    ),
                    Text(
                      '${course.libelleStatut} · ${d.day.toString().padLeft(2, '0')}/'
                      '${d.month.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.texteDiscret),
                    ),
                  ],
                ),
              ),
              Text(formaterFcfa(course.prixFcfa), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.onyx)),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, color: AppColors.texteDiscret),
            ],
          ),
        ),
      ),
    );
  }
}
