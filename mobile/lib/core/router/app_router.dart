import 'package:flutter/foundation.dart';
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
import '../../features/client/presentation/retour_paiement_page.dart';
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

/// Retour de paiement sur le site : Max It ouvre le VRAI chemin
/// `/paiement/retour?ref=…&etat=…`, que le routage à « # » du site ne voit
/// pas ; on en fait l'adresse de départ. `null` pour toute autre adresse.
/// (L'APK, lui, reçoit ce chemin directement : lien d'application Android.)
String? emplacementRetourPaiement(Uri adresse) {
  if (adresse.path != AppRoutes.retourPaiement) return null;
  return Uri(
    path: AppRoutes.retourPaiement,
    queryParameters: adresse.queryParameters.isEmpty ? null : adresse.queryParameters,
  ).toString();
}

final String? _retourPaiementAuDemarrage = kIsWeb ? emplacementRetourPaiement(Uri.base) : null;

/// Sur iPhone (site et app web installée sur l'écran d'accueil), les écrans
/// de Sprint ne s'empilent pas dans l'historique du navigateur : chaque
/// changement d'écran remplace l'entrée courante (l'adresse reste à jour).
///
/// Sinon, le glissement de retour d'iOS ramenait à l'écran précédent de
/// l'historique en affichant l'image qu'iOS en avait gardée : l'écran de
/// connexion, bouton encore en chargement, à côté de « Compte » (capture du
/// client, 2 novembre 2026). Le chauffeur connecté était ensuite renvoyé à
/// son accueil, qui reprenait une nouvelle entrée : le glissement suivant
/// retombait sur la même image (« le glissement plante »). Sur iPhone, le
/// retour se fait désormais dans l'app : flèches et glissement natif des
/// écrans (sur l'écran réel, jamais sur une image figée). Android (bouton
/// retour) et ordinateur gardent l'historique du navigateur ; l'APK n'en a
/// pas.
bool historiqueNavigateurNeutralise({required bool web, required TargetPlatform plateforme}) =>
    web && plateforme == TargetPlatform.iOS;

final GoRouter appRouter = GoRouter(
  initialLocation: _retourPaiementAuDemarrage ?? AppRoutes.welcome,
  overridePlatformDefaultLocation: _retourPaiementAuDemarrage != null,
  routerNeglect: historiqueNavigateurNeutralise(web: kIsWeb, plateforme: defaultTargetPlatform),
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
      // Transition commune de l'app (thème) : l'accueil, opaque, chasse
      // l'écran de connexion, sans jamais se superposer à lui.
      builder: (context, state) => const ConducteurShellPage(),
    ),
    GoRoute(
      path: AppRoutes.conducteurLogin,
      // Chauffeur déjà connecté (retour arrière depuis son accueil) : son
      // accueil, pas l'écran de connexion.
      redirect: (context, state) => aiguillageDemarrage.connexionChauffeur(),
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
    GoRoute(
      path: AppRoutes.retourPaiement,
      builder: (context, state) => RetourPaiementPage(
        reference: state.uri.queryParameters['ref'],
        etat: state.uri.queryParameters['etat'],
      ),
    ),
  ],
);
