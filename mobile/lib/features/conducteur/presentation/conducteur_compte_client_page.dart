import 'package:flutter/material.dart';
import '../../../core/widgets/ecran_statut_onyx.dart';
import '../../../core/widgets/numero_version.dart';

/// Écran affiché quand un compte CLIENT se connecte dans l'espace chauffeur
/// (voir `etapeDossierChauffeur`). Avant, il arrivait sur « Complétez votre
/// dossier », et l'envoi de ses pièces était refusé par les règles Firestore
/// (« firestore/permission-denied ») sans explication : un même compte ne peut
/// pas être à la fois Client et Chauffeur.
class ConducteurCompteClientPage extends StatelessWidget {
  const ConducteurCompteClientPage({
    super.key,
    required this.onCreerCompteChauffeur,
    required this.onDeconnexion,
  });

  /// Déconnexion, puis inscription chauffeur.
  final VoidCallback onCreerCompteChauffeur;
  final VoidCallback onDeconnexion;

  @override
  Widget build(BuildContext context) {
    return EcranStatutOnyx(
      icone: Icons.person_outline_rounded,
      titre: 'Ce compte est un compte Client',
      texte: 'Vous êtes connecté avec un compte Client Sprint. Un même compte ne peut pas être à la fois '
          'Client et Chauffeur : pour conduire avec Sprint, créez un compte chauffeur avec une autre '
          'adresse e-mail.',
      actions: [
        BoutonStatutPrincipal(
          label: 'Créer un compte chauffeur',
          icone: Icons.two_wheeler_rounded,
          onPressed: onCreerCompteChauffeur,
        ),
        LienStatut(label: 'Se déconnecter', onPressed: onDeconnexion),
        const NumeroVersion(),
      ],
    );
  }
}
