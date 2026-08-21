import 'package:go_router/go_router.dart';
import '../../features/admin/presentation/admin_home_page.dart';
import '../../features/client/presentation/colis_page.dart';
import '../../features/client/presentation/passager_page.dart';
import '../../features/conducteur/presentation/conducteur_home_page.dart';
import '../../features/onboarding/presentation/accueil_page.dart';
import '../../features/onboarding/presentation/espace_pro_page.dart';
import 'app_routes.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.accueil,
  routes: [
    GoRoute(
      path: AppRoutes.accueil,
      builder: (context, state) => const AccueilPage(),
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
      path: AppRoutes.espacePro,
      builder: (context, state) => const EspaceProPage(),
    ),
    GoRoute(
      path: AppRoutes.conducteur,
      builder: (context, state) => const ConducteurHomePage(),
    ),
    GoRoute(
      path: AppRoutes.admin,
      builder: (context, state) => const AdminHomePage(),
    ),
  ],
);
