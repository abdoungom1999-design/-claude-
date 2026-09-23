import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../courses/data/course_service.dart';
import '../../messages/data/chat_service.dart';
import '../../messages/presentation/messagerie_chat_page.dart';

/// Suivi temps réel d'une course, depuis sa création jusqu'à
/// l'acceptation par un chauffeur : un `StreamBuilder` unique, branché
/// sur [CourseService.streamCourse], bascule automatiquement entre
/// l'écran "Recherche d'un chauffeur" (`statut: en_attente`) et l'écran
/// "Votre chauffeur arrive" (`statut: acceptee`) dès que le document
/// Firestore change — aucune action de l'utilisateur nécessaire.
class SuiviCoursePage extends StatefulWidget {
  const SuiviCoursePage({super.key, required this.courseId});

  final String courseId;

  @override
  State<SuiviCoursePage> createState() => _SuiviCoursePageState();
}

class _SuiviCoursePageState extends State<SuiviCoursePage> {
  final _courseService = CourseService();
  bool _annulationEnCours = false;

  Future<void> _annuler() async {
    setState(() => _annulationEnCours = true);
    try {
      await _courseService.annulerCourse(widget.courseId);
    } finally {
      if (mounted) setState(() => _annulationEnCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Votre course')),
      body: SafeArea(
        child: StreamBuilder<CourseFirestore?>(
          stream: _courseService.streamCourse(widget.courseId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: AppColors.orange));
            }
            final course = snapshot.data;
            if (course == null || course.statut == 'annulee') {
              return _EtatAnnulee(onRetour: () => Navigator.of(context).pop());
            }
            switch (course.statut) {
              case 'en_attente':
                return _EtatRecherche(
                  course: course,
                  enCours: _annulationEnCours,
                  onAnnuler: _annuler,
                );
              case 'terminee':
                return _EtatTerminee(onRetour: () => Navigator.of(context).pop());
              default:
                // 'acceptee' et 'en_cours' : un chauffeur est assigné.
                return _EtatChauffeurAssigne(course: course);
            }
          },
        ),
      ),
    );
  }
}

class _EtatRecherche extends StatelessWidget {
  const _EtatRecherche({required this.course, required this.enCours, required this.onAnnuler});

  final CourseFirestore course;
  final bool enCours;
  final VoidCallback onAnnuler;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 64,
            height: 64,
            child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.orange),
          ),
          const SizedBox(height: 28),
          const Text(
            "Recherche d'un chauffeur…",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            'Votre demande a été envoyée aux chauffeurs à proximité pour '
            '${course.prixFcfa} FCFA. Cette page se mettra à jour dès que quelqu\'un accepte.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13.5, color: AppColors.grey, height: 1.5),
          ),
          const SizedBox(height: 32),
          OutlinedButton(
            onPressed: enCours ? null : onAnnuler,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(220, 52),
              side: const BorderSide(color: AppColors.greyBorder),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: enCours
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Text(
                    'Annuler la demande',
                    style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700),
                  ),
          ),
        ],
      ),
    );
  }
}

class _EtatChauffeurAssigne extends StatefulWidget {
  const _EtatChauffeurAssigne({required this.course});

  final CourseFirestore course;

  @override
  State<_EtatChauffeurAssigne> createState() => _EtatChauffeurAssigneState();
}

class _EtatChauffeurAssigneState extends State<_EtatChauffeurAssigne> {
  final _chatService = ChatService();
  Map<String, dynamic>? _profilChauffeur;

  @override
  void initState() {
    super.initState();
    _chargerChauffeur();
  }

  @override
  void didUpdateWidget(covariant _EtatChauffeurAssigne oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.course.chauffeurId != widget.course.chauffeurId) {
      _chargerChauffeur();
    }
  }

  Future<void> _chargerChauffeur() async {
    final chauffeurId = widget.course.chauffeurId;
    if (chauffeurId == null) return;
    final profil = await _chatService.chargerProfil(chauffeurId);
    if (mounted) setState(() => _profilChauffeur = profil);
  }

  Future<void> _appeler() async {
    final telephone = (_profilChauffeur?['telephone'] as String?)?.trim();
    if (telephone == null || telephone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Numéro de téléphone indisponible.')),
      );
      return;
    }
    await launchUrl(Uri(scheme: 'tel', path: telephone));
  }

  void _discuter() {
    final chauffeurId = widget.course.chauffeurId;
    if (chauffeurId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MessagerieChatPage(
          interlocuteurUid: chauffeurId,
          interlocuteurNom: (_profilChauffeur?['nom'] as String?) ?? 'Chauffeur Sprint',
          interlocuteurSousTitre: 'Chauffeur Sprint',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nom = (_profilChauffeur?['nom'] as String?) ?? 'Chauffeur Sprint';
    final vehicule = _profilChauffeur?['vehiculeId'] as String?;
    final plaque = _profilChauffeur?['plaqueImmatriculation'] as String?;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.orange, AppColors.orangeDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              nom.isNotEmpty ? nom[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Votre chauffeur arrive',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(nom, style: const TextStyle(fontSize: 15, color: AppColors.grey)),
          if (vehicule != null && vehicule.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              plaque != null && plaque.isNotEmpty ? '$vehicule · $plaque' : vehicule,
              style: const TextStyle(fontSize: 12.5, color: AppColors.grey),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _appeler,
                  icon: const Icon(Icons.call_rounded, color: AppColors.orange),
                  label: const Text('Appeler'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    side: const BorderSide(color: AppColors.greyBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _discuter,
                  icon: const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.orange),
                  label: const Text('Discuter'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    side: const BorderSide(color: AppColors.greyBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.greyLight,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LigneAdresse(icon: Icons.my_location, texte: widget.course.adresseDepart),
                const SizedBox(height: 10),
                _LigneAdresse(icon: Icons.location_on_outlined, texte: widget.course.adresseArrivee),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LigneAdresse extends StatelessWidget {
  const _LigneAdresse({required this.icon, required this.texte});

  final IconData icon;
  final String texte;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.grey),
        const SizedBox(width: 10),
        Expanded(
          child: Text(texte, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}

class _EtatAnnulee extends StatelessWidget {
  const _EtatAnnulee({required this.onRetour});

  final VoidCallback onRetour;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cancel_outlined, size: 48, color: AppColors.grey),
            const SizedBox(height: 16),
            const Text(
              'Course annulée',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            OutlinedButton(onPressed: onRetour, child: const Text('Retour')),
          ],
        ),
      ),
    );
  }
}

class _EtatTerminee extends StatelessWidget {
  const _EtatTerminee({required this.onRetour});

  final VoidCallback onRetour;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline_rounded, size: 48, color: Colors.green),
            const SizedBox(height: 16),
            const Text(
              'Course terminée, merci !',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            OutlinedButton(onPressed: onRetour, child: const Text('Retour à l\'accueil')),
          ],
        ),
      ),
    );
  }
}
