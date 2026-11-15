import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/ecran_statut_onyx.dart';

/// Le texte de « Bienvenue chez SPRINT », selon le rôle. Mêmes mots que le
/// serveur (`messageBienvenue`, `functions/src/inscription.ts`), qui envoie la
/// même chose en notification et par e-mail : un test les compare.
class MessageBienvenue {
  const MessageBienvenue({required this.titre, required this.accroche, required this.points});

  final String titre;
  final String accroche;
  final List<String> points;
}

/// Premier prénom à afficher : le prénom du profil, sinon le premier mot du nom.
String prenomPour(Map<String, dynamic>? profil) {
  for (final cle in ['prenom', 'nom']) {
    final valeur = profil?[cle];
    if (valeur is String && valeur.trim().isNotEmpty) {
      final mot = valeur.trim().split(RegExp(r'\s+')).first;
      final propre = mot.replaceAll(RegExp("[<>&\"'`\\u0000-\\u001F]"), '');
      return propre.length > 40 ? propre.substring(0, 40) : propre;
    }
  }
  return '';
}

MessageBienvenue messageBienvenue(String role, String prenom) {
  final bonjour = prenom.isEmpty ? 'Bonjour,' : 'Bonjour $prenom,';
  if (role == 'conducteur') {
    return MessageBienvenue(
      titre: 'Bienvenue chez SPRINT',
      accroche: "$bonjour bienvenue dans l'équipe SPRINT.",
      points: const [
        'Complétez votre dossier (pièces et moto) : un administrateur le valide avant votre première course.',
        'Une fois validé, passez « En ligne » pour recevoir les courses autour de vous.',
        "Vos gains s'affichent course après course dans l'onglet Gains.",
      ],
    );
  }
  return MessageBienvenue(
    titre: 'Bienvenue chez SPRINT',
    accroche: '$bonjour votre compte SPRINT est prêt.',
    points: const [
      'Commandez une course en moto en quelques secondes : le prix est affiché avant de confirmer.',
      'Envoyez un colis partout à Dakar, Thiès et Mbour.',
      'Suivez votre chauffeur en direct sur la carte.',
    ],
  );
}

/// Écran affiché UNE fois, à la fin de l'inscription (quand le serveur a
/// déclenché la bienvenue) : « Bienvenue chez SPRINT ».
class BienvenueSprintPage extends StatelessWidget {
  const BienvenueSprintPage({super.key, required this.role, required this.prenom, required this.surContinuer});

  final String role;
  final String prenom;
  final VoidCallback surContinuer;

  @override
  Widget build(BuildContext context) {
    final message = messageBienvenue(role, prenom);
    return EcranStatutOnyx(
      icone: Icons.waving_hand_outlined,
      titre: message.titre,
      texte: message.accroche,
      contenu: [
        for (final point in message.points)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.check_circle_rounded, size: 18, color: AppColors.vert),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  point,
                  style: const TextStyle(fontSize: 13.5, color: AppColors.texte, height: 1.5),
                ),
              ),
            ],
          ),
      ],
      actions: [
        BoutonStatutPrincipal(
          key: const ValueKey('bienvenue-continuer'),
          label: role == 'conducteur' ? 'Compléter mon dossier' : 'Commencer',
          onPressed: surContinuer,
        ),
      ],
    );
  }
}
