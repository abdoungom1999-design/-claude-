import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/courses/data/course_service.dart';
import '../../features/messages/data/chat_service.dart';
import '../../features/messages/data/messages_non_lus.dart';
import '../../firebase_options.dart';
import '../notifications/notifications_push.dart';
import '../alertes/alerte_sonore.dart';
import '../router/app_routes.dart';
import '../theme/app_colors.dart';
import '../widgets/barre_navigation.dart';
import '../widgets/email_verification_pending_page.dart';
import '../widgets/logo_sprint.dart';
import '../widgets/premium_dialog.dart';

/// Coquille de navigation Client : barre du bas à 4 onglets (Accueil,
/// Activité, Messages, Compte) surmontée d'un bouton d'action flottant
/// central rond ('S') qui déborde légèrement au-dessus de la barre et
/// ouvre le menu d'actions rapides.
class HomeShellPage extends StatefulWidget {
  const HomeShellPage({
    super.key,
    required this.navigationShell,
    this.courseService,
    this.chatService,
    this.messagesNonLus,
    this.notificationsPush,
    this.monUid,
  });

  final StatefulNavigationShell navigationShell;

  /// Injectables pour les tests.
  final CourseService? courseService;
  final ChatService? chatService;
  final MessagesNonLus? messagesNonLus;
  final NotificationsPush? notificationsPush;
  final String? monUid;

  @override
  State<HomeShellPage> createState() => _HomeShellPageState();
}

class _HomeShellPageState extends State<HomeShellPage> {
  late final MessagesNonLus _nonLus =
      widget.messagesNonLus ?? MessagesNonLus.instance;
  StreamSubscription<List<CourseFirestore>>? _abonnementCourses;

  StatefulNavigationShell get navigationShell => widget.navigationShell;

  @override
  void initState() {
    super.initState();
    _suivreMessagesDuChauffeur();
    _activerNotificationsPush();
  }

  /// Notifications push (APK Android) : message du chauffeur, course
  /// acceptée ou annulée, même app fermée. L'appui sur l'une d'elles ouvre
  /// la conversation (message) ou l'activité (course).
  void _activerNotificationsPush() {
    final uid = widget.monUid ?? _uidConnecte();
    if (uid == null) return;
    unawaited((widget.notificationsPush ?? NotificationsPush.instance).activer(
      uid: uid,
      surAppui: (message) {
        if (!mounted) return;
        context.go(message.type == 'message' ? AppRoutes.messagesTab : AppRoutes.activiteTab);
      },
    ));
  }

  @override
  void dispose() {
    _abonnementCourses?.cancel();
    _nonLus.arreter();
    super.dispose();
  }

  static bool _emailNonVerifie() {
    if (!DefaultFirebaseOptions.estConfigure) return false;
    try {
      final utilisateur = FirebaseAuth.instance.currentUser;
      return utilisateur != null && !utilisateur.emailVerified;
    } catch (_) {
      // Firebase pas initialisé (tests) : rien à vérifier.
      return false;
    }
  }

  static String? _uidConnecte() {
    if (!DefaultFirebaseOptions.estConfigure) return null;
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  /// Tant que le client a une course en cours avec un chauffeur, on
  /// écoute sa conversation depuis n'importe quel onglet : son + vibration
  /// et pastille rouge à chaque message (voir [MessagesNonLus]).
  void _suivreMessagesDuChauffeur() {
    final uid = widget.monUid ?? _uidConnecte();
    if (uid == null) return;
    final chat = widget.chatService ?? ChatService();
    _abonnementCourses = (widget.courseService ?? CourseService())
        .streamCoursesClient(uid)
        .listen(
      (courses) {
        final active = courses
            .where((c) => c.estActive && (c.chauffeurId?.isNotEmpty ?? false));
        final chauffeurId = active.isEmpty ? null : active.first.chauffeurId;
        if (chauffeurId == null) {
          _nonLus.arreter();
        } else {
          _nonLus.suivre(
              chatService: chat, monUid: uid, interlocuteurUid: chauffeurId);
        }
      },
      onError: (_) {},
    );
  }

  void _ouvrirMenuActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _MenuActionsRapides(contextParent: context),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_emailNonVerifie()) {
      return const EmailVerificationPendingPage(
        destinationApresVerification: AppRoutes.home,
      );
    }

    // Les navigateurs n'autorisent le son qu'après un geste : le premier
    // appui dans l'app prépare celui de l'alerte de message.
    return Listener(
      onPointerDown: (_) => AlerteSonore.preparer(),
      child: Scaffold(
        backgroundColor: AppColors.fond,
        body: navigationShell,
        floatingActionButton: Padding(
          padding: const EdgeInsets.only(top: 28),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: AppColors.vert.withValues(alpha: 0.38), blurRadius: 26, spreadRadius: 1)],
            ),
            child: SizedBox(
              width: 64,
              height: 64,
              child: FloatingActionButton(
                onPressed: () => _ouvrirMenuActions(context),
                backgroundColor: AppColors.onyx,
                elevation: 0,
                shape: const CircleBorder(side: BorderSide(color: AppColors.vert, width: 2)),
                // Logo Sprint (marbre noir, « S » blanc et liseré vert) rogné en rond.
                child: const ClipOval(child: LogoSprint(taille: 64)),
              ),
            ),
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        // Onyx & Vert : fond Onyx, icônes grises, onglet actif vert.
        bottomNavigationBar: BarreNavigation(
          avecEncoche: true,
          onglets: [
            OngletBarre(
              icon: Icons.home_outlined,
              iconActif: Icons.home_rounded,
              label: 'Accueil',
              selectionne: navigationShell.currentIndex == 0,
              onTap: () => navigationShell.goBranch(0),
            ),
            OngletBarre(
              icon: Icons.receipt_long_outlined,
              iconActif: Icons.receipt_long_rounded,
              label: 'Activité',
              selectionne: navigationShell.currentIndex == 1,
              onTap: () => navigationShell.goBranch(1),
            ),
            const SizedBox(width: 56),
            ListenableBuilder(
              listenable: _nonLus,
              builder: (context, _) => OngletBarre(
                icon: Icons.chat_bubble_outline_rounded,
                iconActif: Icons.chat_bubble_rounded,
                label: 'Messages',
                selectionne: navigationShell.currentIndex == 2,
                nonLus: _nonLus.nonLus,
                onTap: () => navigationShell.goBranch(2),
              ),
            ),
            OngletBarre(
              icon: Icons.person_outline_rounded,
              iconActif: Icons.person_rounded,
              label: 'Compte',
              selectionne: navigationShell.currentIndex == 3,
              onTap: () => navigationShell.goBranch(3),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuActionsRapides extends StatelessWidget {
  const _MenuActionsRapides({required this.contextParent});

  /// Contexte de la page hôte (stable), utilisé pour les actions qui
  /// s'exécutent après la fermeture de ce bottom sheet — son propre
  /// [BuildContext] ne serait plus fiable une fois le sheet démonté.
  final BuildContext contextParent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      decoration: const BoxDecoration(
        color: AppColors.carte,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppColors.bordVerre)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.bord,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Que voulez-vous faire ?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.texte),
          ),
          const SizedBox(height: 20),
          _ActionRapide(
            icon: Icons.two_wheeler_rounded,
            label: 'Course immédiate',
            description: 'Réservez une moto-taxi maintenant',
            onTap: () {
              Navigator.of(context).pop();
              contextParent.push(AppRoutes.clientPassager);
            },
          ),
          _ActionRapide(
            icon: Icons.event_available_outlined,
            label: 'Réservation',
            description: 'Planifiez une course à l\'avance',
            onTap: () => _bientotDisponible(context, 'Réservation'),
          ),
          _ActionRapide(
            icon: Icons.inventory_2_outlined,
            label: 'Livraison',
            description: 'Envoyez un colis rapidement',
            onTap: () {
              Navigator.of(context).pop();
              contextParent.push(AppRoutes.clientColis);
            },
          ),
          _ActionRapide(
            icon: Icons.car_rental_outlined,
            label: 'Location',
            description: 'Louez un véhicule avec chauffeur',
            onTap: () => _bientotDisponible(context, 'Location'),
          ),
          _ActionRapide(
            icon: Icons.flight_takeoff_rounded,
            label: 'Aéroport',
            description: 'Transferts aéroport en toute sérénité',
            onTap: () => _bientotDisponible(context, 'Aéroport'),
          ),
        ],
      ),
    );
  }

  void _bientotDisponible(BuildContext context, String label) {
    Navigator.of(context).pop();
    PremiumDialog.bientotDisponible(contextParent, label);
  }
}

class _ActionRapide extends StatelessWidget {
  const _ActionRapide({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.vertTeinte,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppColors.vert, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.texte,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: const TextStyle(fontSize: 12, color: AppColors.texteDiscret),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.texteDiscret),
          ],
        ),
      ),
    );
  }
}
