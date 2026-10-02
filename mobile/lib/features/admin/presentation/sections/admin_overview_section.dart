import 'dart:async';

import 'package:flutter/material.dart';
import '../../../../core/demo/admin_demo_data.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/format_fcfa.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../firebase_options.dart';
import '../../../courses/data/course_service.dart';
import '../../../finances/data/comptabilite.dart';
import '../../data/pilotage_service.dart';
import '../widgets/admin_courbe_courses.dart';
import '../widgets/admin_kpi_card.dart';

/// Page "Dashboard" (vue d'ensemble) de la Tour de Contrôle. En Firebase
/// réel, uniquement des données Firestore, en temps réel : CA et courses
/// terminées du jour, chauffeurs en ligne (signal GPS de moins de
/// 2 minutes), nouveaux inscrits, courses terminées sur 7 jours et
/// dernières courses créées. En mode démo : [AdminDemoData].
class AdminOverviewSection extends StatelessWidget {
  const AdminOverviewSection({super.key, this.service, this.maintenant});

  /// Injectables pour les tests.
  final PilotageService? service;
  final DateTime? maintenant;

  @override
  Widget build(BuildContext context) {
    if (!DefaultFirebaseOptions.estConfigure && service == null) return const _OverviewDemo();
    return _OverviewReel(service: service ?? PilotageService(), maintenant: maintenant);
  }
}

class _OverviewReel extends StatefulWidget {
  const _OverviewReel({required this.service, this.maintenant});

  final PilotageService service;
  final DateTime? maintenant;

  @override
  State<_OverviewReel> createState() => _OverviewReelState();
}

class _OverviewReelState extends State<_OverviewReel> {
  final _abonnements = <StreamSubscription<Object?>>[];
  Timer? _horloge;
  List<LigneCourse>? _terminees;
  List<CourseFirestore>? _dernieres;
  List<PositionChauffeurDirect> _positions = const [];
  List<UtilisateurAdmin> _clients = const [];
  List<UtilisateurAdmin> _chauffeurs = const [];
  Object? _erreur;

  @override
  void initState() {
    super.initState();
    final service = widget.service;
    _suivre(service.streamCoursesTerminees(), (v) => _terminees = v);
    _suivre(service.streamDernieresCourses(), (v) => _dernieres = v);
    _suivre(service.streamPositions(), (v) => _positions = v);
    _suivre(service.streamUtilisateurs('client'), (v) => _clients = v);
    _suivre(service.streamUtilisateurs('conducteur'), (v) => _chauffeurs = v);
    // "Aujourd'hui" et la fraîcheur des signaux GPS avancent seuls.
    if (widget.maintenant == null) {
      _horloge = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
    }
  }

  void _suivre<T>(Stream<T> flux, void Function(T valeur) maj) {
    _abonnements.add(flux.listen(
      (valeur) {
        if (mounted) setState(() => maj(valeur));
      },
      onError: (Object e) {
        if (mounted) setState(() => _erreur = e);
      },
    ));
  }

  @override
  void dispose() {
    for (final a in _abonnements) {
      a.cancel();
    }
    _horloge?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_erreur != null) {
      return const AppCard(
        child: Text(
          'Lecture impossible. Vérifiez que vous êtes connecté avec le compte Admin '
          'et que les règles Firestore sont publiées.',
          style: TextStyle(color: AppColors.grey),
        ),
      );
    }
    final terminees = _terminees;
    final dernieres = _dernieres;
    if (terminees == null || dernieres == null) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator(color: AppColors.orange)),
      );
    }

    final maintenant = widget.maintenant ?? DateTime.now();
    final debutJour = Periodes.debutJour(maintenant);
    final compte = Compte(courses: terminees);
    final jour = compte.depuis(debutJour);
    final semaine = compte.depuis(Periodes.debutSemaine(maintenant));

    final etats = [for (final p in _positions) EtatSignal.pour(p.majLe, maintenant)];
    final enLigne = etats.where((e) => e == EtatSignal.actif).length;
    final signalPerdu = etats.where((e) => e == EtatSignal.perdu).length;
    final valides = _chauffeurs.where((c) => c.statutValidation == 'valide').length;

    bool inscritAujourdhui(UtilisateurAdmin u) => u.creeLe != null && !u.creeLe!.isBefore(debutJour);
    final nouveauxClients = _clients.where(inscritAujourdhui).length;
    final nouveauxChauffeurs = _chauffeurs.where(inscritAujourdhui).length;

    // 7 derniers jours, aujourd'hui compris.
    final jours = [for (var i = 6; i >= 0; i--) debutJour.subtract(Duration(days: i))];
    final coursesParJour = [
      for (final j in jours)
        terminees.where((c) => !c.date.isBefore(j) && c.date.isBefore(j.add(const Duration(days: 1)))).length,
    ];
    final total7Jours = coursesParJour.fold(0, (a, b) => a + b);

    final noms = {
      for (final u in _clients) u.id: u.nom,
      for (final u in _chauffeurs) u.id: u.nom,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AdminKpiCard(
                icon: Icons.payments_outlined,
                valeur: formaterFcfa(jour.chiffreAffairesFcfa),
                label: "Chiffre d'affaires du jour",
                detail: 'Commission Sprint : ${formaterFcfa(jour.commissionsFcfa)}',
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: AdminKpiCard(
                icon: Icons.task_alt_rounded,
                valeur: '${jour.nombreCourses}',
                label: "Courses terminées aujourd'hui",
                accent: AppColors.onyx,
                detail: '${semaine.nombreCourses} cette semaine',
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: AdminKpiCard(
                icon: Icons.two_wheeler_rounded,
                valeur: '$enLigne',
                label: 'Chauffeurs en ligne',
                accent: AppColors.orange,
                detail: signalPerdu > 0
                    ? '$signalPerdu signal perdu · $valides validés'
                    : 'sur $valides chauffeurs validés',
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: AdminKpiCard(
                icon: Icons.person_add_alt_1_rounded,
                valeur: '${nouveauxClients + nouveauxChauffeurs}',
                label: "Nouveaux inscrits aujourd'hui",
                accent: AppColors.onyx,
                detail: '${_pluriel(nouveauxClients, 'client')} · ${_pluriel(nouveauxChauffeurs, 'chauffeur')}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        AppCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Courses terminées sur 7 jours',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '${_pluriel(total7Jours, 'course')} au total, par jour.',
                style: const TextStyle(fontSize: 12.5, color: AppColors.grey),
              ),
              const SizedBox(height: 20),
              AdminCourbeCourses(
                valeurs: coursesParJour,
                labels: [for (final j in jours) _joursCourts[j.weekday - 1]],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        AppCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Dernières courses',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              if (dernieres.isEmpty)
                const Text('Aucune course pour le moment.', style: TextStyle(color: AppColors.grey))
              else ...[
                const _LigneTableau(
                  entete: true,
                  id: 'Course',
                  client: 'Client',
                  chauffeur: 'Chauffeur',
                  trajet: 'Trajet',
                  montant: 'Montant',
                  statut: null,
                ),
                const Divider(height: 20, color: AppColors.greyBorder),
                for (final c in dernieres)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: _LigneTableau(
                      id: _heure(c.timestamp),
                      client: noms[c.clientId] ?? 'Client inconnu',
                      chauffeur: c.chauffeurId == null ? '—' : noms[c.chauffeurId] ?? 'Chauffeur inconnu',
                      trajet: '${c.adresseDepart} → ${c.adresseArrivee}',
                      montant: formaterFcfa(c.prixFcfa),
                      statut: _statut(c.statut),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static const _joursCourts = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

  static String _pluriel(int n, String mot) => n > 1 ? '$n ${mot}s' : '$n $mot';

  /// "27/09 14:05" (heure de Dakar = UTC).
  static String _heure(DateTime date) {
    final d = date.toUtc();
    String deux(int v) => v.toString().padLeft(2, '0');
    return '${deux(d.day)}/${deux(d.month)} ${deux(d.hour)}:${deux(d.minute)}';
  }

  static (String, Color) _statut(String statut) => switch (statut) {
        StatutCourse.enAttente => ('En attente', AppColors.grey),
        StatutCourse.acceptee => ('Acceptée', Colors.blue),
        StatutCourse.enCours => ('En cours', AppColors.orange),
        StatutCourse.terminee => ('Terminée', AppColors.onyx),
        StatutCourse.annulee => ('Annulée', Colors.redAccent),
        _ => (statut, AppColors.grey),
      };
}

/// Version démo (sans Firebase) : chiffres de la maquette ([AdminDemoData]).
class _OverviewDemo extends StatelessWidget {
  const _OverviewDemo();

  @override
  Widget build(BuildContext context) {
    final caFormate = _formaterFcfa(AdminDemoData.caJourFcfa);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: AdminKpiCard(
                icon: Icons.payments_outlined,
                valeur: '$caFormate FCFA',
                label: 'Chiffre d\'affaires du jour',
              ),
            ),
            const SizedBox(width: 18),
            const Expanded(
              child: AdminKpiCard(
                icon: Icons.task_alt_rounded,
                valeur: '${AdminDemoData.coursesTermineesJour}',
                label: 'Courses terminées',
                accent: AppColors.onyx,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: AdminKpiCard(
                icon: Icons.two_wheeler_rounded,
                valeur: '${AdminDemoData.chauffeursEnLigne}',
                label: 'Chauffeurs en ligne',
                accent: AppColors.orange,
              ),
            ),
            const SizedBox(width: 18),
            const Expanded(
              child: AdminKpiCard(
                icon: Icons.person_add_alt_1_rounded,
                valeur: '${AdminDemoData.nouveauxInscritsJour}',
                label: 'Nouveaux inscrits',
                accent: AppColors.onyx,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const AppCard(
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Évolution des courses cette semaine',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 4),
              Text(
                'Nombre de courses terminées, par jour.',
                style: TextStyle(fontSize: 12.5, color: AppColors.grey),
              ),
              SizedBox(height: 20),
              AdminCourbeCourses(
                valeurs: AdminDemoData.courbeCoursesSemaine,
                labels: AdminDemoData.joursSemaineCourts,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        AppCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Dernières courses',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              _TableauDernieresCourses(courses: AdminDemoData.dernieresCourses()),
            ],
          ),
        ),
      ],
    );
  }

  static String _formaterFcfa(int montant) {
    final chiffres = montant.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < chiffres.length; i++) {
      if (i > 0 && (chiffres.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(chiffres[i]);
    }
    return buffer.toString();
  }
}

class _TableauDernieresCourses extends StatelessWidget {
  const _TableauDernieresCourses({required this.courses});

  final List<CourseAdminRecap> courses;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _LigneTableau(
          entete: true,
          id: 'Course',
          client: 'Client',
          chauffeur: 'Chauffeur',
          trajet: 'Trajet',
          montant: 'Montant',
          statut: null,
        ),
        const Divider(height: 20, color: AppColors.greyBorder),
        for (final course in courses)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _LigneTableau(
              id: course.id,
              client: course.client,
              chauffeur: course.chauffeur,
              trajet: course.trajet,
              montant: '${course.montantFcfa} FCFA',
              statut: switch (course.statut) {
                StatutCourseAdmin.terminee => ('Terminée', AppColors.onyx),
                StatutCourseAdmin.annulee => ('Annulée', Colors.redAccent),
                StatutCourseAdmin.enCours => ('En cours', AppColors.orange),
              },
            ),
          ),
      ],
    );
  }
}

class _LigneTableau extends StatelessWidget {
  const _LigneTableau({
    required this.id,
    required this.client,
    required this.chauffeur,
    required this.trajet,
    required this.montant,
    required this.statut,
    this.entete = false,
  });

  final String id;
  final String client;
  final String chauffeur;
  final String trajet;
  final String montant;
  /// (libellé, couleur) du badge ; `null` pour l'en-tête.
  final (String, Color)? statut;
  final bool entete;

  TextStyle get _style => TextStyle(
    fontSize: entete ? 11.5 : 13,
    fontWeight: entete ? FontWeight.w700 : FontWeight.w500,
    color: entete ? AppColors.grey : AppColors.text,
    letterSpacing: entete ? 0.4 : 0,
  );

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 100, child: Text(id, style: _style)),
        Expanded(flex: 2, child: Text(client, style: _style, maxLines: 1, overflow: TextOverflow.ellipsis)),
        Expanded(flex: 2, child: Text(chauffeur, style: _style, maxLines: 1, overflow: TextOverflow.ellipsis)),
        Expanded(flex: 3, child: Text(trajet, style: _style, maxLines: 1, overflow: TextOverflow.ellipsis)),
        SizedBox(width: 100, child: Text(montant, style: _style)),
        SizedBox(
          width: 100,
          child: entete
              ? Text('Statut', style: _style)
              : Align(alignment: Alignment.centerLeft, child: _BadgeStatutCourse(statut: statut!)),
        ),
      ],
    );
  }
}

class _BadgeStatutCourse extends StatelessWidget {
  const _BadgeStatutCourse({required this.statut});

  final (String, Color) statut;

  @override
  Widget build(BuildContext context) {
    final (label, couleur) = statut;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: couleur, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}
