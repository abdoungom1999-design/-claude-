import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/notifications/carte_notifications.dart';
import '../../../core/theme/app_colors.dart';
import '../../courses/data/course_service.dart';
import '../../courses/data/position_chauffeur.dart';
import '../../evaluations/presentation/evaluation_course.dart';
import '../../messages/data/chat_service.dart';
import '../../messages/data/messages_non_lus.dart';
import '../../messages/presentation/messagerie_chat_page.dart';
import '../../messages/presentation/widgets/pastille_non_lus.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/maps/proximite_service.dart';
import 'widgets/carte_chauffeur.dart';
import 'widgets/carte_recherche.dart';
import 'widgets/suivi_approche.dart';

/// Suivi temps réel d'une course, depuis sa création jusqu'à
/// l'acceptation par un chauffeur : un `StreamBuilder` unique, branché
/// sur [CourseService.streamCourse], bascule automatiquement entre
/// l'écran "Recherche d'un chauffeur" (`statut: en_attente`) et l'écran
/// "Votre chauffeur arrive" (`statut: acceptee`) dès que le document
/// Firestore change — aucune action de l'utilisateur nécessaire. Une
/// fois le chauffeur attribué, sa position s'affiche en temps réel avec
/// le temps d'attente estimé (voir [SuiviApproche]), et un message du
/// chauffeur arrivé pendant que le client regarde la carte s'affiche
/// aussitôt (son + vibration, voir [MessagesNonLus]), avec une pastille
/// rouge et le nombre de messages non lus sur "Discuter" jusqu'à leur lecture.
class SuiviCoursePage extends StatefulWidget {
  const SuiviCoursePage({
    super.key,
    required this.courseId,
    this.courseService,
    this.chatService,
    this.monUid,
    this.coucheFond,
    this.proximite,
    this.messagesNonLus,
  });

  final String courseId;

  /// Injectables pour les tests.
  final CourseService? courseService;
  final ChatService? chatService;
  final String? monUid;

  /// Fond de la carte de suivi ; par défaut celui de l'app.
  final Widget? coucheFond;

  /// Motos alentour affichées pendant la recherche d'un chauffeur.
  final ProximiteService? proximite;

  /// Messages non lus du chauffeur ; par défaut celui de l'app.
  final MessagesNonLus? messagesNonLus;

  @override
  State<SuiviCoursePage> createState() => _SuiviCoursePageState();
}

class _SuiviCoursePageState extends State<SuiviCoursePage> {
  late final CourseService _courseService = widget.courseService ?? CourseService();
  late final Stream<CourseFirestore?> _course = _courseService.streamCourse(widget.courseId);
  bool _annulationEnCours = false;

  Future<void> _annuler() async {
    setState(() => _annulationEnCours = true);
    try {
      await _courseService.annulerCourse(widget.courseId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.message : "L'annulation a échoué. Réessayez.")),
        );
      }
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
          stream: _course,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: AppColors.orange));
            }
            final course = snapshot.data;
            if (course == null || course.statut == 'annulee') {
              return _EtatAnnulee(course: course, onRetour: () => Navigator.of(context).pop());
            }
            switch (course.statut) {
              case 'en_attente':
                return _EtatRecherche(
                  course: course,
                  enCours: _annulationEnCours,
                  onAnnuler: _annuler,
                  proximite: widget.proximite,
                  coucheFond: widget.coucheFond,
                );
              case 'terminee':
                // Fin de course : le client note son chauffeur.
                return _EtatTerminee(course: course, onRetour: () => Navigator.of(context).pop());
              default:
                // 'acceptee' et 'en_cours' : un chauffeur est assigné.
                return _EtatChauffeurAssigne(
                  course: course,
                  courseService: _courseService,
                  chatService: widget.chatService ?? ChatService(),
                  monUid: widget.monUid ?? FirebaseAuth.instance.currentUser?.uid,
                  messagesNonLus: widget.messagesNonLus ?? MessagesNonLus.instance,
                  coucheFond: widget.coucheFond,
                );
            }
          },
        ),
      ),
    );
  }
}

class _EtatRecherche extends StatelessWidget {
  const _EtatRecherche({
    required this.course,
    required this.enCours,
    required this.onAnnuler,
    this.proximite,
    this.coucheFond,
  });

  final CourseFirestore course;
  final bool enCours;
  final VoidCallback onAnnuler;
  final ProximiteService? proximite;
  final Widget? coucheFond;

  @override
  Widget build(BuildContext context) {
    final points = course.points;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Les motos disponibles autour du point de prise en charge
          // gardent la carte vivante pendant l'attente.
          CarteRecherche(
            priseEnCharge: points == null ? null : LatLng(points.latitudeDepart, points.longitudeDepart),
            proximite: proximite,
            coucheFond: coucheFond,
          ),
          const SizedBox(height: 20),
          // Le bon moment pour proposer les alertes : on attend un chauffeur.
          const CarteNotifications(enBandeau: true, raison: 'une alerte dès qu\'un chauffeur accepte votre course'),
          const SizedBox(height: 8),
          const SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.orange),
          ),
          const SizedBox(height: 20),
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
          const SizedBox(height: 24),
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
  const _EtatChauffeurAssigne({
    required this.course,
    required this.courseService,
    required this.chatService,
    required this.monUid,
    required this.messagesNonLus,
    this.coucheFond,
  });

  final CourseFirestore course;
  final CourseService courseService;
  final ChatService chatService;
  final String? monUid;
  final MessagesNonLus messagesNonLus;
  final Widget? coucheFond;

  @override
  State<_EtatChauffeurAssigne> createState() => _EtatChauffeurAssigneState();
}

class _EtatChauffeurAssigneState extends State<_EtatChauffeurAssigne> {
  ChatService get _chatService => widget.chatService;
  CourseService get _courseService => widget.courseService;
  Map<String, dynamic>? _profilChauffeur;
  bool _profilEnErreur = false;
  late Stream<PositionChauffeurDirect?> _positions;

  // Messages du chauffeur reçus pendant que le client regarde la carte.
  MessagesNonLus get _nonLus => widget.messagesNonLus;
  StreamSubscription<ChatMessageFirestore>? _abonnementMessages;
  bool _chatOuvert = false;

  @override
  void initState() {
    super.initState();
    _positions = _streamPositions();
    _chargerChauffeur();
    _suivreMessages();
  }

  @override
  void dispose() {
    _abonnementMessages?.cancel();
    super.dispose();
  }

  /// La coquille du client suit déjà la conversation (son, vibration,
  /// compteur) ; ici on s'assure que c'est bien ce chauffeur (appel sans
  /// effet si c'est déjà le cas) et on affiche le message aussitôt
  /// ("Répondre" ouvre le chat).
  void _suivreMessages() {
    _abonnementMessages?.cancel();
    _abonnementMessages = null;
    final chauffeurId = widget.course.chauffeurId;
    final monUid = widget.monUid;
    if (chauffeurId == null || monUid == null) return;

    _nonLus.suivre(chatService: _chatService, monUid: monUid, interlocuteurUid: chauffeurId);
    _abonnementMessages = _nonLus.nouveauxMessages.listen((message) {
      if (!mounted || _chatOuvert) return;
      final nom = (_profilChauffeur?['nom'] as String?)?.trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${nom == null || nom.isEmpty ? 'Votre chauffeur' : nom} : ${message.text}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(label: 'Répondre', onPressed: _discuter),
        ),
      );
    });
  }

  Stream<PositionChauffeurDirect?> _streamPositions() {
    final chauffeurId = widget.course.chauffeurId;
    return chauffeurId == null ? const Stream.empty() : _courseService.streamPositionChauffeur(chauffeurId);
  }

  @override
  void didUpdateWidget(covariant _EtatChauffeurAssigne oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.course.chauffeurId != widget.course.chauffeurId) {
      _positions = _streamPositions();
      _chargerChauffeur();
      _suivreMessages();
    }
  }

  /// Identité du chauffeur (profil public). Un échec de lecture est dit
  /// au client, avec "Réessayer", au lieu de laisser un nom générique.
  Future<void> _chargerChauffeur() async {
    final chauffeurId = widget.course.chauffeurId;
    if (chauffeurId == null) return;
    if (_profilEnErreur) setState(() => _profilEnErreur = false);
    try {
      final profil = await _chatService.chargerProfil(chauffeurId);
      if (!mounted) return;
      setState(() {
        // Profil absent : on affiche ce qu'on sait (nom générique, véhicule
        // non renseigné) plutôt qu'un chargement sans fin.
        _profilChauffeur = profil ?? const {};
        _profilEnErreur = false;
      });
    } catch (_) {
      if (mounted) setState(() => _profilEnErreur = true);
    }
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

  Future<void> _discuter() async {
    final chauffeurId = widget.course.chauffeurId;
    if (chauffeurId == null || _chatOuvert) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() => _chatOuvert = true);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MessagerieChatPage(
          interlocuteurUid: chauffeurId,
          interlocuteurNom: (_profilChauffeur?['nom'] as String?) ?? 'Chauffeur Sprint',
          interlocuteurSousTitre: 'Chauffeur Sprint',
          chatService: widget.chatService,
          monUid: widget.monUid,
          messagesNonLus: _nonLus,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _chatOuvert = false);
  }

  @override
  Widget build(BuildContext context) {
    final clientABord = widget.course.statut == StatutCourse.enCours;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          SuiviApproche(
            key: ValueKey(widget.course.chauffeurId),
            course: widget.course,
            positions: _positions,
            coucheFond: widget.coucheFond,
          ),
          const SizedBox(height: 18),
          CarteChauffeur(
            profil: _profilChauffeur,
            clientABord: clientABord,
            erreur: _profilEnErreur,
            onReessayer: _chargerChauffeur,
          ),
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
                  icon: ListenableBuilder(
                    listenable: _nonLus,
                    builder: (context, _) => PastilleNonLus(
                      nombre: _nonLus.nonLus,
                      child: const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.orange),
                    ),
                  ),
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
  const _EtatAnnulee({required this.course, required this.onRetour});

  final CourseFirestore? course;
  final VoidCallback onRetour;

  /// Pourquoi la course est annulée, et si le client est remboursé.
  static String? _explication(CourseFirestore? course) {
    if (course == null) return null;
    final raison = switch (course.annuleePar) {
      'chauffeur' => '${MotifAnnulation.pourLeClient(course.motifAnnulation)} ',
      'systeme' => course.motifAnnulation == MotifAnnulation.chauffeurSuspendu
          ? "Votre chauffeur n'est plus disponible : la course a été annulée par Sprint. "
          : "Aucun chauffeur n'était disponible pour le moment. ",
      _ => '',
    };
    final remboursement = course.estRemboursable ? 'Votre paiement vous est remboursé. ' : '';
    if (raison.isEmpty && remboursement.isEmpty) return null;
    return '$raison${remboursement}Vous pouvez commander une nouvelle course.';
  }

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
            if (_explication(course) case final texte?) ...[
              const SizedBox(height: 10),
              Text(
                texte,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13.5, color: AppColors.grey, height: 1.5),
              ),
            ],
            const SizedBox(height: 20),
            OutlinedButton(onPressed: onRetour, child: const Text('Retour')),
          ],
        ),
      ),
    );
  }
}

class _EtatTerminee extends StatefulWidget {
  const _EtatTerminee({required this.course, required this.onRetour});

  final CourseFirestore course;
  final VoidCallback onRetour;

  @override
  State<_EtatTerminee> createState() => _EtatTermineeState();
}

class _EtatTermineeState extends State<_EtatTerminee> {
  String? _nomChauffeur;

  @override
  void initState() {
    super.initState();
    _chargerNom();
  }

  Future<void> _chargerNom() async {
    final chauffeurId = widget.course.chauffeurId;
    if (chauffeurId == null) return;
    try {
      final profil = await ChatService().chargerProfil(chauffeurId);
      if (mounted) setState(() => _nomChauffeur = profil?['nom'] as String?);
    } catch (_) {
      // Le nom n'est qu'un confort d'affichage.
    }
  }

  @override
  Widget build(BuildContext context) {
    return EvaluationCourse(
      course: widget.course,
      nomChauffeur: _nomChauffeur,
      onTerminer: widget.onRetour,
    );
  }
}
