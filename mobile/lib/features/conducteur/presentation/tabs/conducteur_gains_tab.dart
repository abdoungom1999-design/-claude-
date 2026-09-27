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

/// Onglet Gains du chauffeur. En Firebase réel : chiffre d'affaires du
/// jour et de la semaine, courses terminées, temps en ligne, et surtout
/// le solde avec la plateforme (commission de 15 % due sur les courses
/// en espèces, part de 85 % due par la plateforme sur les courses Wave /
/// Orange Money, règlements déjà faits). En mode démo : [DemoData].
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
    final recettesParJour = [
      for (final j in joursSemaine)
        compte.courses
            .where((c) => !c.date.isBefore(j) && c.date.isBefore(j.add(const Duration(days: 1))))
            .fold(0, (total, c) => total + c.prixFcfa),
    ];
    final dernieres = [...compte.courses]..sort((a, b) => b.date.compareTo(a.date));

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Gains', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
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
              Text("Chiffre d'affaires aujourd'hui", style: TextStyle(color: Colors.white.withValues(alpha: 0.75))),
              const SizedBox(height: 8),
              Text(
                formaterFcfa(jour.chiffreAffairesFcfa),
                style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                '${_courses(jour.nombreCourses)} · ${dureeEnLigne(secondesJour)} en ligne',
                style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 16),
              Divider(height: 1, color: Colors.white.withValues(alpha: 0.12)),
              const SizedBox(height: 14),
              Text('Cette semaine', style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.75))),
              const SizedBox(height: 4),
              Text(
                '${formaterFcfa(semaine.chiffreAffairesFcfa)} · ${_courses(semaine.nombreCourses)} · '
                '${dureeEnLigne(secondesSemaine)} en ligne',
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _CarteSolde(soldeFcfa: compte.soldeFcfa),
        const SizedBox(height: 16),
        AppCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Détail de la semaine', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              _LigneMontant(libelle: 'Encaissé en espèces', montant: semaine.especesFcfa),
              _LigneMontant(libelle: 'Payé par Wave / Orange Money', montant: semaine.mobileMoneyFcfa),
              _LigneMontant(
                libelle: 'Commission Sprint (${Commission.pourcentage} %)',
                montant: -semaine.commissionsFcfa,
              ),
              const Divider(height: 20, color: AppColors.greyBorder),
              _LigneMontant(libelle: 'Vos gains nets', montant: semaine.gainsNetsFcfa, fort: true),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Recettes par jour', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 18),
              GainsBarresChart(valeurs: recettesParJour, labels: _jours),
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
          const Text('Règlements', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              children: [
                for (final r in [...compte.reglements]..sort((a, b) => b.date.compareTo(a.date)))
                  _LigneMontant(
                    libelle: '${_date(r.date)} · ${r.versPlateforme ? 'Versé à Sprint' : 'Reçu de Sprint'}',
                    montant: r.montantFcfa,
                  ),
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

class _CarteSolde extends StatelessWidget {
  const _CarteSolde({required this.soldeFcfa});

  final int soldeFcfa;

  @override
  Widget build(BuildContext context) {
    final (Color couleur, IconData icone, String titre, String detail) = switch (sensDuSolde(soldeFcfa)) {
      SensSolde.chauffeurDoit => (
          Colors.red.shade700,
          Icons.account_balance_wallet_outlined,
          'Vous devez ${formaterFcfa(-soldeFcfa)} à Sprint',
          'Commission de ${Commission.pourcentage} % sur vos courses payées en espèces, '
              'après déduction de ce que Sprint vous doit.',
        ),
      SensSolde.plateformeDoit => (
          AppColors.vert,
          Icons.savings_outlined,
          'Sprint vous doit ${formaterFcfa(soldeFcfa)}',
          'Votre part (${100 - Commission.pourcentage} %) des courses payées par Wave ou Orange Money, '
              'après déduction de vos commissions.',
        ),
      SensSolde.equilibre => (
          AppColors.grey,
          Icons.check_circle_outline_rounded,
          'Compte à jour',
          'Aucune somme due entre vous et Sprint.',
        ),
    };
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: couleur.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: couleur),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: couleur)),
                const SizedBox(height: 4),
                Text(detail, style: const TextStyle(fontSize: 12.5, color: AppColors.grey, height: 1.4)),
              ],
            ),
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
            child: Icon(
              ligne.especes ? Icons.payments_outlined : Icons.phone_android_rounded,
              color: AppColors.grey,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ligne.especes ? 'Espèces' : 'Wave / Orange Money',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                ),
                Text(
                  '${_date(ligne.date)} · commission ${formaterFcfa(ligne.commissionFcfa)}',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.grey),
                ),
              ],
            ),
          ),
          Text(
            formaterFcfa(ligne.prixFcfa),
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
