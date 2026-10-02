import 'package:flutter/material.dart';
import '../../../core/widgets/ecran_statut_onyx.dart';

/// Salle d'attente obligatoire du chauffeur dont le dossier KYC a été
/// soumis (voir [ConducteurKYCPage]) mais pas encore validé par un
/// administrateur (`statutValidation == 'en_attente'` dans le document
/// Firestore de l'utilisateur, voir le "Gardien" dans
/// [ConducteurShellPage]). Volontairement minimaliste et sans aucune
/// navigation (pas de barre du bas, pas de menu) : tant que le compte
/// n'est pas validé, il n'y a rien d'autre à faire ici qu'attendre.
class ConducteurEnAttentePage extends StatelessWidget {
  const ConducteurEnAttentePage({super.key, required this.onDeconnexion});

  final VoidCallback onDeconnexion;

  @override
  Widget build(BuildContext context) {
    return EcranStatutOnyx(
      icone: Icons.fact_check_rounded,
      titre: 'Dossier en cours de vérification',
      texte: "Vos documents sont en cours d'examen par l'équipe du Groupe "
          'Santine. Vous serez notifié dès la validation de votre compte.',
      contenu: const [EtapesDossier(etapeCourante: 1)],
      actions: [LienStatut(label: 'Se déconnecter', onPressed: onDeconnexion)],
    );
  }
}
