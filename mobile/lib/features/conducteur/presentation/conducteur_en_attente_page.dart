import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/widgets/confettis_celebration.dart';
import '../../../core/widgets/ecran_statut_onyx.dart';
import '../../auth/data/auth_repository.dart';

/// Salle d'attente obligatoire du chauffeur dont le dossier KYC a été
/// soumis (voir [ConducteurKYCPage]) mais pas encore validé par un
/// administrateur (`statutValidation == 'en_attente'` dans le document
/// Firestore de l'utilisateur, voir le "Gardien" dans
/// [ConducteurShellPage]). Volontairement minimaliste et sans aucune
/// navigation (pas de barre du bas, pas de menu) : tant que le compte
/// n'est pas validé, il n'y a rien d'autre à faire ici qu'attendre.
///
/// L'écran ÉCOUTE le profil en temps réel : dès que l'Admin approuve le
/// dossier (`statutValidation == 'valide'`), il se transforme en écran de
/// célébration (étapes illuminées, halo autour du logo, confettis, message
/// « Félicitations ! »), puis appelle [onActive] — à la fin de la célébration
/// (environ 2,5 secondes) ou au clic sur « Commencer » — pour ouvrir l'espace
/// chauffeur, sans déconnexion ni fermeture de l'application.
///
/// Aucun rafraîchissement de jeton n'est nécessaire : les droits d'un chauffeur
/// validé ne passent pas par des « custom claims » mais par son document
/// Firestore, que les règles relisent à chaque requête.
class ConducteurEnAttentePage extends StatefulWidget {
  const ConducteurEnAttentePage({
    super.key,
    required this.onDeconnexion,
    this.fluxProfil,
    this.onActive,
    this.dureeCelebration = const Duration(milliseconds: 2500),
  });

  final VoidCallback onDeconnexion;

  /// Profil Firestore du chauffeur, suivi en direct. `null` : flux réel du
  /// compte connecté (rien n'est suivi si Firebase n'est pas disponible).
  final Stream<Map<String, dynamic>?>? fluxProfil;

  /// Appelé UNE seule fois, quand la célébration est finie ou que le chauffeur
  /// appuie sur « Commencer » : c'est là que l'espace chauffeur s'ouvre.
  final VoidCallback? onActive;

  /// Durée de la célébration avant l'ouverture automatique de l'espace chauffeur.
  final Duration dureeCelebration;

  @override
  State<ConducteurEnAttentePage> createState() => _ConducteurEnAttentePageState();
}

class _ConducteurEnAttentePageState extends State<ConducteurEnAttentePage> {
  StreamSubscription<Map<String, dynamic>?>? _abonnement;
  Timer? _minuteur;
  bool _approuve = false;
  bool _termine = false;

  @override
  void initState() {
    super.initState();
    try {
      final flux = widget.fluxProfil ?? AuthRepository().profilUtilisateurStream();
      // Une erreur de lecture ne change rien : l'écran d'attente reste affiché,
      // et le chauffeur retrouvera son espace à sa prochaine ouverture.
      _abonnement = flux.listen(_surProfil, onError: (Object _) {});
    } on Object {
      // Firebase indisponible (démo, test) : pas de suivi en direct.
      _abonnement = null;
    }
  }

  @override
  void dispose() {
    _abonnement?.cancel();
    _minuteur?.cancel();
    super.dispose();
  }

  void _surProfil(Map<String, dynamic>? profil) {
    if (_approuve || !mounted) return;
    if (profil?['statutValidation'] == 'valide') _celebrer();
  }

  void _celebrer() {
    setState(() => _approuve = true);
    // Petit retour au toucher sur les téléphones qui le permettent.
    unawaited(HapticFeedback.mediumImpact().catchError((Object _) {}));
    _minuteur = Timer(widget.dureeCelebration, _commencer);
  }

  /// Ouvre l'espace chauffeur, une seule fois (fin du minuteur ou appui).
  void _commencer() {
    if (_termine) return;
    _termine = true;
    _minuteur?.cancel();
    widget.onActive?.call();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: _approuve ? _celebration() : _attente(),
    );
  }

  Widget _attente() {
    return EcranStatutOnyx(
      key: const ValueKey('attente'),
      icone: Icons.fact_check_rounded,
      titre: 'Dossier en cours de vérification',
      texte: "Vos documents sont en cours d'examen par l'équipe du Groupe "
          'Santine. Vous serez notifié dès la validation de votre compte.',
      contenu: const [EtapesDossier(etapeCourante: 1)],
      actions: [LienStatut(label: 'Se déconnecter', onPressed: widget.onDeconnexion)],
    );
  }

  Widget _celebration() {
    return Stack(
      key: const ValueKey('celebration'),
      children: [
        EcranStatutOnyx(
          icone: Icons.verified_rounded,
          titre: 'Félicitations ! Votre compte chauffeur Sprint est activé',
          texte: 'Vous pouvez maintenant passer en ligne et recevoir des courses.',
          haloLogo: true,
          contenu: const [EtapesDossier(etapeCourante: 3, eclat: true)],
          actions: [
            BoutonStatutPrincipal(label: 'Commencer', icone: Icons.arrow_forward_rounded, onPressed: _commencer),
          ],
        ),
        const Positioned.fill(child: ConfettisCelebration()),
      ],
    );
  }
}
