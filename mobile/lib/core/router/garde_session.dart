import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import '../../firebase_options.dart';
import 'app_routes.dart';

/// Où en est la session de l'utilisateur, vue du routeur.
sealed class EtatSession {
  const EtatSession();
}

/// Impossible de le savoir (Firebase lent ou injoignable) : le routeur ne
/// déplace personne plutôt que de risquer de mettre quelqu'un dehors.
class SessionInconnue extends EtatSession {
  const SessionInconnue();
}

class SessionFermee extends EtatSession {
  const SessionFermee();
}

/// [role] : `client`, `conducteur` ou `admin` ; `null` s'il n'a pas pu être lu.
class SessionOuverte extends EtatSession {
  const SessionOuverte(this.role);

  final String? role;
}

/// Garde de session du routeur : la connexion n'est plus accessible une fois
/// connecté, et les espaces (Client, Chauffeur, Admin) ne le sont plus une
/// fois déconnecté.
///
/// Elle vaut pour TOUT chemin, d'où qu'il vienne : geste « retour » du
/// téléphone, bouton retour du navigateur, lien de notification, page
/// rechargée, historique resté d'une session précédente. Ainsi, quoi qu'il
/// reste dans l'historique, un balayage depuis l'accueil ne peut pas
/// ramener à l'écran de connexion.
///
/// Évaluée à chaque navigation, pas à chaque changement de session : ainsi
/// une inscription (compte créé puis documents envoyés) n'est jamais
/// interrompue en plein milieu.
class GardeSession {
  GardeSession({Future<EtatSession> Function({bool avecRole})? lireSession, bool? backendActif})
      : _lireSession = lireSession ?? _lireSessionFirebase,
        _backendActif = backendActif;

  /// Instance de l'application.
  static final instance = GardeSession();

  /// Lit la session ; [avecRole] : lit aussi le rôle (une lecture Firestore),
  /// nécessaire seulement pour choisir l'accueil d'un utilisateur connecté.
  final Future<EtatSession> Function({bool avecRole}) _lireSession;
  final bool? _backendActif;

  /// Écrans de connexion et d'accueil avant connexion.
  static const pagesDeConnexion = {
    AppRoutes.welcome,
    AppRoutes.clientLogin,
    AppRoutes.clientRegister,
    AppRoutes.conducteurLogin,
    AppRoutes.conducteurRegister,
    AppRoutes.adminLogin,
    AppRoutes.espacePro,
  };

  static bool estPageProtegee(String chemin) =>
      chemin == AppRoutes.home ||
      chemin.startsWith('${AppRoutes.home}/') ||
      chemin == AppRoutes.clientPassager ||
      chemin == AppRoutes.clientColis ||
      chemin == AppRoutes.conducteur ||
      chemin == AppRoutes.admin;

  /// Page d'accueil de chaque espace, celle qui devient la racine de la
  /// session.
  static String accueilPourRole(String? role) => switch (role) {
        'admin' => AppRoutes.admin,
        'conducteur' => AppRoutes.conducteur,
        _ => AppRoutes.home,
      };

  /// Où envoyer quelqu'un dont la session est [session] et qui demande
  /// [chemin] ; `null` : le laisser faire. Sans effet en mode démo (pas de
  /// projet Firebase, donc pas de vraie session).
  static String? destination({required String chemin, required EtatSession session, bool backendActif = true}) {
    if (!backendActif || session is SessionInconnue) return null;
    if (session is SessionOuverte) {
      if (!pagesDeConnexion.contains(chemin)) return null;
      // Rôle illisible : mieux vaut laisser la page que d'envoyer au mauvais espace.
      return session.role == null ? null : accueilPourRole(session.role);
    }
    if (!estPageProtegee(chemin)) return null;
    return switch (chemin) {
      AppRoutes.admin => AppRoutes.adminLogin,
      AppRoutes.conducteur => AppRoutes.conducteurLogin,
      _ => AppRoutes.welcome,
    };
  }

  /// À brancher sur `GoRouter(redirect: ...)`.
  Future<String?> rediriger(BuildContext context, GoRouterState state) async {
    final chemin = state.uri.path;
    final actif = _backendActif ?? DefaultFirebaseOptions.estConfigure;
    // Inutile de lire la session pour une page qui n'est concernée ni dans
    // un sens ni dans l'autre.
    if (!actif || (!pagesDeConnexion.contains(chemin) && !estPageProtegee(chemin))) return null;
    final session = await _lireSession(avecRole: pagesDeConnexion.contains(chemin));
    return destination(chemin: chemin, session: session, backendActif: actif);
  }

  static final _roles = <String, String?>{};

  static Future<EtatSession> _lireSessionFirebase({bool avecRole = false}) async {
    try {
      final auth = FirebaseAuth.instance;
      // Au démarrage, Firebase restaure la session avec un léger retard :
      // on attend son premier verdict plutôt que de croire à tort
      // l'utilisateur déconnecté.
      final utilisateur = auth.currentUser ?? await auth.authStateChanges().first.timeout(const Duration(seconds: 5));
      if (utilisateur == null) return const SessionFermee();
      // Le rôle n'est lu que pour choisir l'accueil : aller d'une page de
      // l'espace à une autre ne doit dépendre d'aucune lecture réseau.
      return SessionOuverte(avecRole ? await _role(utilisateur.uid) : null);
    } catch (_) {
      return const SessionInconnue();
    }
  }

  static Future<String?> _role(String uid) async {
    if (_roles.containsKey(uid)) return _roles[uid];
    try {
      final document = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 6));
      final role = document.data()?['role'];
      return _roles[uid] = role is String ? role : null;
    } catch (_) {
      return null;
    }
  }
}
