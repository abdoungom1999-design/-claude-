import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../core/demo/demo_data.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/format_fcfa.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../firebase_options.dart';
import '../../../courses/data/course_service.dart';
import '../../../finances/data/comptabilite.dart';
import '../../../finances/data/finance_service.dart';
import '../widgets/gains_barres_chart.dart';

/// Onglet Gains du chauffeur. En Firebase réel : ce que Sprint lui doit
/// (100 % mobile money : la plateforme encaisse chaque course et reverse
/// au chauffeur sa part de 85 %, moins les versements déjà reçus), ses
/// gains du jour et de la semaine, ses courses et son temps en ligne. Le
/// chauffeur ne doit jamais rien à Sprint. En mode démo : [DemoData].
class ConducteurGainsTab extends StatelessWidget {
  const ConducteurGainsTab({super.key, this.service, this.chauffeurId, this.maintenant});

  /// Injectables pour les tests.
  final FinanceService? service;
  final String? chauffeurId;
  final DateTime? maintenant;

  @override
  Widget build(BuildContext context) {
    if (!DefaultFirebaseOptions.estConfigure && service == null) return const _GainsDemo();
    final uid = chauffeurId ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    return _GainsReels(service: service ?? FinanceService(), chauffeurId: uid, maintenant: maintenant);
  }
}

class _GainsReels extends StatefulWidget {
  const _GainsReels({required this.service, required this.chauffeurId, this.maintenant});

  final FinanceService service;
  final String chauffeurId;
  final DateTime? maintenant;

  @override
  State<_GainsReels> createState() => _GainsReelsState();
}

class _GainsReelsState extends State<_GainsReels> {
  late final _courses = widget.service.streamCoursesChauffeur(widget.chauffeurId);
  late final _reglements = widget.service.streamReglementsChauffeur(widget.chauffeurId);
  late final _temps = widget.service.streamTempsEnLigne(widget.chauffeurId);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: StreamBuilder<List<LigneCourse>>(
          stream: _courses,
          builder: (context, courses) => StreamBuilder<List<Reglement>>(
            stream: _reglements,
            builder: (context, reglements) => StreamBuilder<Map<String, int>>(
              stream: _temps,
              builder: (context, temps) {
                if (courses.hasError || reglements.hasError) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Impossible de charger vos gains pour le moment.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.grey),
                      ),
                    ),
                  );
                }
                if (!courses.hasData || !reglements.hasData) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.orange));
                }
                return _VueGains(
                  compte: Compte(courses: courses.data!, reglements: reglements.data!),
                  tempsParJour: temps.data ?? const {},
                  maintenant: widget.maintenant ?? DateTime.now(),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _VueGains extends StatelessWidget {
  const _VueGains({required this.compte, required this.tempsParJour, required this.maintenant});

  final Compte compte;
  final Map<String, int> tempsParJour;
  final DateTime maintenant;

  static const _jours = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

  @override
  Widget build(BuildContext context) {
    final debutJour = Periodes.debutJour(maintenant);
    final debutSemaine = Periodes.debutSemaine(maintenant);
    final jour = compte.depuis(debutJour);
    final semaine = compte.depuis(debutSemaine);
    final joursSemaine = [for (var i = 0; i < 7; i++) debutSemaine.add(Duration(days: i))];
    final secondesJour = tempsParJour[Periodes.cleJour(debutJour)] ?? 0;
    final secondesSemaine = joursSemaine.fold(0, (total, j) => total + (tempsParJour[Periodes.cleJour(j)] ?? 0));
    final gainsParJour = [
      for (final j in joursSemaine)
        compte.courses
            .where((c) => !c.date.isBefore(j) && c.date.isBefore(j.add(const Duration(days: 1))))
            .fold(0, (total, c) => total + c.partChauffeurFcfa),
    ];
    final dernieres = [...compte.courses]..sort((a, b) => b.date.compareTo(a.date));

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Gains', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _CarteDu(soldeFcfa: compte.soldeFcfa),
        const SizedBox(height: 16),
        AppCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Aujourd'hui", style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                '${_courses(jour.nombreCourses)} · ${dureeEnLigne(secondesJour)} en ligne',
                style: const TextStyle(fontSize: 12, color: AppColors.grey),
              ),
              const SizedBox(height: 8),
              _LigneMontant(libelle: 'Vos gains', montant: jour.gainsNetsFcfa, fort: true),
              const Divider(height: 24, color: AppColors.greyBorder),
              const Text('Cette semaine', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                '${_courses(semaine.nombreCourses)} · ${dureeEnLigne(secondesSemaine)} en ligne',
                style: const TextStyle(fontSize: 12, color: AppColors.grey),
              ),
              const SizedBox(height: 8),
              _LigneMontant(libelle: 'Payé par vos clients', montant: semaine.chiffreAffairesFcfa),
              _LigneMontant(
                libelle: 'Commission Sprint (${Commission.pourcentage} %)',
                montant: -semaine.commissionsFcfa,
              ),
              const Divider(height: 20, color: AppColors.greyBorder),
              _LigneMontant(
                libelle: 'Vos gains (${100 - Commission.pourcentage} %)',
                montant: semaine.gainsNetsFcfa,
                fort: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Vos gains par jour', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 18),
              GainsBarresChart(valeurs: gainsParJour, labels: _jours),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text('Dernières courses', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        if (dernieres.isEmpty)
          const AppCard(
            child: Text(
              'Vos courses terminées apparaîtront ici.',
              style: TextStyle(fontSize: 13, color: AppColors.grey),
            ),
          )
        else
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < dernieres.length && i < 10; i++) ...[
                  _LigneCourseReelle(ligne: dernieres[i]),
                  if (i != dernieres.length - 1 && i != 9) const Divider(height: 1, color: AppColors.greyBorder),
                ],
              ],
            ),
          ),
        if (compte.reglements.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text('Versements reçus', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              children: [
                for (final r in [...compte.reglements]..sort((a, b) => b.date.compareTo(a.date)))
                  _LigneMontant(libelle: '${_date(r.date)} · Reçu de Sprint', montant: r.montantFcfa),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static String _courses(int nombre) => nombre <= 1 ? '$nombre course' : '$nombre courses';
}

/// "2 h 05", "45 min".
String dureeEnLigne(int secondes) {
  final minutes = secondes ~/ 60;
  if (minutes < 60) return '$minutes min';
  return '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')}';
}

String _date(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';

/// Ce que Sprint doit au chauffeur : sa part de toutes ses courses, moins
/// les versements déjà reçus.
class _CarteDu extends StatelessWidget {
  const _CarteDu({required this.soldeFcfa});

  final int soldeFcfa;

  @override
  Widget build(BuildContext context) {
    final enAttente = soldeFcfa > 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.noirProfond, AppColors.noirProfondClair],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sprint vous doit', style: TextStyle(color: Colors.white.withValues(alpha: 0.75))),
          const SizedBox(height: 8),
          Text(
            formaterFcfa(enAttente ? soldeFcfa : 0),
            style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            enAttente
                ? 'Votre part (${100 - Commission.pourcentage} %) de vos courses payées par Wave ou '
                    'Orange Money, moins les versements déjà reçus.'
                : 'Aucune somme en attente : tout vous a été versé.',
            style: TextStyle(fontSize: 12.5, height: 1.4, color: Colors.white.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}

class _LigneMontant extends StatelessWidget {
  const _LigneMontant({required this.libelle, required this.montant, this.fort = false});

  final String libelle;
  final int montant;
  final bool fort;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: fort ? 14.5 : 13, fontWeight: fort ? FontWeight.w800 : FontWeight.w500);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(libelle, style: style.copyWith(color: fort ? AppColors.text : AppColors.grey))),
          Text(montant < 0 ? '− ${formaterFcfa(-montant)}' : formaterFcfa(montant), style: style),
        ],
      ),
    );
  }
}

class _LigneCourseReelle extends StatelessWidget {
  const _LigneCourseReelle({required this.ligne});

  final LigneCourse ligne;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: AppColors.greyLight, borderRadius: BorderRadius.circular(11)),
            child: const Icon(Icons.phone_android_rounded, color: AppColors.grey, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Payée par ${ligne.libelleMethode}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                ),
                Text(
                  '${_date(ligne.date)} · prix ${formaterFcfa(ligne.prixFcfa)}',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.grey),
                ),
              ],
            ),
          ),
          Text(
            '+${formaterFcfa(ligne.partChauffeurFcfa)}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.vert),
          ),
        ],
      ),
    );
  }
}

/// Version démo (sans Firebase), inchangée.
class _GainsDemo extends StatelessWidget {
  const _GainsDemo();

  @override
  Widget build(BuildContext context) {
    final courses = DemoData.coursesTermineesConducteur();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Gains',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.noirProfond, AppColors.noirProfondClair],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gains cette semaine',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '${DemoData.gainsSemaineFcfa} FCFA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${DemoData.coursesSemaine} courses effectuées',
                    style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const AppCard(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Revenus par jour',
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 18),
                  GainsBarresChart(
                    valeurs: DemoData.gainsParJourSemaine,
                    labels: DemoData.joursSemaineCourts,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '10 dernières courses',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (var i = 0; i < courses.length; i++) ...[
                    _LigneCourseGains(course: courses[i]),
                    if (i != courses.length - 1)
                      const Divider(height: 1, color: AppColors.greyBorder),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LigneCourseGains extends StatelessWidget {
  const _LigneCourseGains({required this.course});

  final CourseTermineeConducteur course;

  @override
  Widget build(BuildContext context) {
    final estColis = course.type == 'Colis';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.greyLight,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              estColis ? Icons.inventory_2_outlined : Icons.two_wheeler_rounded,
              color: AppColors.grey,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(course.type, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                Text(
                  course.heure,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.grey),
                ),
              ],
            ),
          ),
          Text(
            '+${course.montantFcfa} FCFA',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
              color: AppColors.vert,
            ),
          ),
        ],
      ),
    );
  }
}
