import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../core/widgets/premium_dialog.dart';
import '../../../firebase_options.dart';
import '../../auth/data/auth_repository.dart';
import 'signalement_page.dart';

/// Compte connecté qui écrit au support.
typedef IdentiteSupport = ({String uid, String role});

Future<IdentiteSupport?> _identiteFirebase() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;
  final role = (await AuthRepository().chargerProfilUtilisateur())?['role'] as String?;
  return role == null ? null : (uid: uid, role: role);
}

/// Branchements remplaçables par les tests (Firebase n'y est pas démarré).
@visibleForTesting
bool Function() supportEnModeDemo = () => !DefaultFirebaseOptions.estConfigure;

@visibleForTesting
Future<IdentiteSupport?> Function() chargerIdentiteSupport = _identiteFirebase;

/// « Contacter le support » : ouvre la conversation avec l'équipe Sprint
/// (ticket `aide_<uid>`, lisible et traité dans l'onglet Support de
/// l'Admin). Accessible à un client, un chauffeur, et à un chauffeur
/// suspendu ou banni, qui reste connecté sur son écran de blocage.
///
/// En mode démo (aucun projet Firebase), il n'y a pas de vrai support : on
/// garde la confirmation d'exemple.
Future<void> ouvrirContactSupport(BuildContext context) async {
  if (supportEnModeDemo()) {
    return PremiumDialog.afficher(
      context,
      icon: Icons.mark_email_read_outlined,
      titre: 'Message envoyé',
      message: 'Mode démonstration : aucun message réel n’est envoyé.',
      succes: true,
    );
  }
  final identite = await chargerIdentiteSupport();
  if (!context.mounted) return;
  if (identite == null || (identite.role != 'client' && identite.role != 'conducteur')) {
    return PremiumDialog.afficher(
      context,
      icon: Icons.lock_outline_rounded,
      titre: 'Connexion nécessaire',
      message: 'Connectez-vous à votre compte pour écrire au support, ou appelez-nous au +221 33 800 00 00.',
    );
  }
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => SignalementPage.aide(clientId: identite.uid, role: identite.role)),
  );
}
