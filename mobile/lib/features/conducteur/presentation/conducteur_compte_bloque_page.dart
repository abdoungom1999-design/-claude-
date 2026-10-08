import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/statut_compte.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/ecran_statut_onyx.dart';
import '../../auth/data/auth_repository.dart';
import '../../support/presentation/contact_support.dart';

/// Écran affiché au chauffeur dont le compte a été suspendu ou banni par
/// l'Admin (`statutCompte`, voir [StatutCompte]). Il reste connecté (voir
/// le "Gardien" de `ConducteurShellPage`) pour pouvoir écrire au support
/// (ticket traité par l'Admin) ; il ne peut sinon que lire et se déconnecter.
class ConducteurCompteBloquePage extends StatelessWidget {
  const ConducteurCompteBloquePage({super.key, required this.statutCompte});

  final String statutCompte;

  Future<void> _seDeconnecter(BuildContext context) async {
    await AuthRepository().deconnecter();
    if (context.mounted) context.go(AppRoutes.espacePro);
  }

  @override
  Widget build(BuildContext context) {
    final banni = statutCompte == StatutCompte.banni;

    // Le rouge reste réservé à l'alerte critique (compte désactivé) ; une
    // suspension, réversible, garde le vert de la charte.
    return EcranStatutOnyx(
      icone: banni ? Icons.block_rounded : Icons.pause_circle_outline_rounded,
      couleurAlerte: banni ? AppColors.danger : null,
      titre: banni ? 'Compte désactivé' : 'Compte suspendu',
      texte: banni
          ? "Votre compte chauffeur a été définitivement désactivé par l'équipe du Groupe Santine. "
              "Vous ne pouvez plus accéder à l'application."
          : "Votre compte chauffeur a été suspendu par l'équipe du Groupe Santine. Vous ne pouvez "
              'plus prendre de courses pour le moment. Contactez le support pour en connaître la raison.',
      actions: [
        BoutonStatutPrincipal(
          label: 'Contacter le support',
          icone: Icons.chat_bubble_outline_rounded,
          onPressed: () => ouvrirContactSupport(context),
        ),
        LienStatut(label: 'Se déconnecter', onPressed: () => _seDeconnecter(context)),
      ],
    );
  }
}
