import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/widgets/ecran_statut_onyx.dart';
import '../../auth/data/auth_repository.dart';
import '../../compte/presentation/centre_aide_page.dart';

/// Écran de blocage affiché tant que le dossier du chauffeur (documents
/// + véhicule soumis via [ConducteurOnboardingPage]) n'a pas été
/// validé : il ne doit pas pouvoir accéder au tableau de bord (la
/// carte, la bascule En ligne) avant cette étape. Voir
/// [ConducteurShellPage], qui affiche cette page à la place du tableau
/// de bord tant que `ProfilConducteur.estValide` est faux.
class ValidationPendingPage extends StatelessWidget {
  const ValidationPendingPage({super.key});

  Future<void> _seDeconnecter(BuildContext context) async {
    await AuthRepository().deconnecter();
    if (context.mounted) context.go(AppRoutes.espacePro);
  }

  @override
  Widget build(BuildContext context) {
    return EcranStatutOnyx(
      icone: Icons.hourglass_top_rounded,
      titre: "Dossier en cours d'examen",
      texte: "Votre dossier a bien été reçu. L'équipe du Groupe Santine "
          'procède actuellement à la vérification de vos documents et '
          'de votre véhicule. Cette étape prend généralement 24 à 48h. '
          'Vous recevrez une notification dès que votre compte sera '
          'activé.',
      contenu: const [PastilleStatut(icone: Icons.verified_user_outlined, label: 'Vérification en cours')],
      actions: [
        BoutonStatutSecondaire(
          label: 'Contacter le support',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CentreAidePage()),
          ),
        ),
        LienStatut(label: 'Se déconnecter', onPressed: () => _seDeconnecter(context)),
      ],
    );
  }
}
