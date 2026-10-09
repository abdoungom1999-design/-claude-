import 'package:go_router/go_router.dart';
import '../../features/activite/presentation/activite_tab_page.dart';
import '../../features/admin/presentation/admin_dashboard_page.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/admin_login_page.dart';
import '../../features/auth/presentation/client_login_page.dart';
import '../../features/auth/presentation/conducteur_login_page.dart';
import '../../features/auth/presentation/conducteur_onboarding/conducteur_onboarding_page.dart';
import '../../features/auth/presentation/register_page.dart';
import '../../features/client/presentation/colis_page.dart';
import '../../features/client/presentation/passager_page.dart';
import '../../features/compte/presentation/compte_tab_page.dart';
import '../../features/conducteur/presentation/conducteur_shell_page.dart';
import '../../features/home/presentation/home_tab_page.dart';
import '../../features/messages/presentation/messages_tab_page.dart';
import '../../features/onboarding/presentation/espace_pro_page.dart';
import '../../features/onboarding/presentation/welcome_page.dart';
import '../navigation/home_shell_page.dart';
import 'aiguillage_demarrage.dart';
import 'app_routes.dart';

/// Démarrage avec une session conservée : relit la session Firebase puis
/// envoie le compte connecté sur son accueil (voir [AiguillageDemarrage]).
/// Les comptes Firebase ne sont touchés que s'il est relié et démarré.
final AiguillageDemarrage aiguillageDemarrage = AiguillageDemarrage(
  pret: () => AuthRepository.firebasePret,
  attendreSession: () => AuthRepository().uidDeLaSessionConservee(),
  uidConnecte: AuthRepository.uidConnecte,
  roleDe: (uid) => AuthRepository().roleDe(uid),
);

final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.welcome,
  // Avant toute page : attend la session conservée, puis envoie un compte
  // déjà connecté directement sur son accueil (jamais d'écran de Bienvenue).
  redirect: (context, state) => aiguillageDemarrage.destination(state.matchedLocation),
  routes: [
    GoRoute(
      path: AppRoutes.welcome,
      builder: (context, state) => const WelcomePage(),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          HomeShellPage(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.home,
              builder: (context, state) => const HomeTabPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.activiteTab,
              builder: (context, state) => const ActiviteTabPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.messagesTab,
              builder: (context, state) => const MessagesTabPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.compteTab,
              builder: (context, state) => const CompteTabPage(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.clientPassager,
      builder: (context, state) => const PassagerPage(),
    ),
    GoRoute(
      path: AppRoutes.clientColis,
      builder: (context, state) => const ColisPage(),
    ),
    GoRoute(
      path: AppRoutes.clientLogin,
      builder: (context, state) => const ClientLoginPage(),
    ),
    GoRoute(
      path: AppRoutes.clientRegister,
      builder: (context, state) => const RegisterPage(),
    ),
    GoRoute(
      path: AppRoutes.espacePro,
      builder: (context, state) => const EspaceProPage(),
    ),
    GoRoute(
      path: AppRoutes.conducteur,
      builder: (context, state) => const ConducteurShellPage(),
    ),
    GoRoute(
      path: AppRoutes.conducteurLogin,
      builder: (context, state) => const ConducteurLoginPage(),
    ),
    GoRoute(
      path: AppRoutes.conducteurRegister,
      builder: (context, state) => const ConducteurOnboardingPage(),
    ),
    GoRoute(
      path: AppRoutes.admin,
      // Réservé au rôle Admin (voir AuthRepository.estAdmin). Garde
      // d'interface uniquement : même sans elle, firestore.rules refuse
      // toute lecture ou décision Admin à un compte sans ce rôle.
      redirect: (context, state) async =>
          await AuthRepository().estAdmin() ? null : AppRoutes.adminLogin,
      builder: (context, state) => const AdminDashboardPage(),
    ),
    GoRoute(
      path: AppRoutes.adminLogin,
      builder: (context, state) => const AdminLoginPage(),
    ),
  ],
);
