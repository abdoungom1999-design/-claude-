import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/statut_compte.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/widgets/ecran_statut_onyx.dart';
import '../../compte/presentation/centre_aide_page.dart';

/// Écran affiché au chauffeur dont le compte a été suspendu ou banni par
/// l'Admin (`statutCompte`, voir [StatutCompte]). Le chauffeur est déjà
/// déconnecté quand cet écran apparaît (voir le "Gardien" de
/// `ConducteurShellPage`) : il ne peut que lire le motif et quitter.
class ConducteurCompteBloquePage extends StatelessWidget {
  const ConducteurCompteBloquePage({super.key, required this.statutCompte});

  final String statutCompte;

  @override
  Widget build(BuildContext context) {
    final banni = statutCompte == StatutCompte.banni;

    // Le rouge reste réservé à l'alerte critique (compte désactivé) ; une
    // suspension, réversible, garde l'orange de la charte.
    return EcranStatutOnyx(
      icone: banni ? Icons.block_rounded : Icons.pause_circle_outline_rounded,
      couleurAlerte: banni ? Colors.red.shade700 : null,
      titre: banni ? 'Compte désactivé' : 'Compte suspendu',
      texte: banni
          ? "Votre compte chauffeur a été définitivement désactivé par l'équipe du Groupe Santine. "
              "Vous ne pouvez plus accéder à l'application."
          : "Votre compte chauffeur a été suspendu par l'équipe du Groupe Santine. Vous ne pouvez "
              'plus prendre de courses pour le moment. Contactez le support pour en connaître la raison.',
      actions: [
        BoutonStatutSecondaire(
          label: 'Contacter le support',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CentreAidePage()),
          ),
        ),
        LienStatut(label: "Retour à l'accueil", onPressed: () => context.go(AppRoutes.espacePro)),
      ],
    );
  }
}
