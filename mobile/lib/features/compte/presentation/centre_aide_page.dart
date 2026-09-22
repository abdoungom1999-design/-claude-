import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/premium_dialog.dart';
import '../../../core/widgets/primary_button.dart';

class _Question {
  const _Question(this.question, this.reponse);
  final String question;
  final String reponse;
}

const _questions = [
  _Question(
    'Comment réserver une course ?',
    'Depuis l\'onglet Accueil, touchez la carte "Où allez-vous ?" ou le '
        'bouton central "S" puis "Course immédiate". Saisissez votre adresse '
        'de départ et d\'arrivée : le prix est calculé automatiquement avant '
        'confirmation.',
  ),
  _Question(
    'Comment payer ma course ?',
    'Trois moyens de paiement sont disponibles : Wave, Orange Money, ou le '
        'solde de votre Portefeuille Santine, rechargeable depuis l\'onglet '
        'Compte.',
  ),
  _Question(
    'Comment annuler une course ?',
    'Vous pouvez annuler une course tant que le Conducteur n\'a pas encore '
        'récupéré le colis ou pris en charge le passager, depuis l\'écran de '
        'suivi de la course.',
  ),
  _Question(
    'Comment devenir chauffeur Sprint ?',
    'Depuis l\'écran de connexion, choisissez "Espace conducteur / admin" '
        'puis "Créer un compte" en sélectionnant le rôle Chauffeur. Votre '
        'compte est ensuite validé par un administrateur avant activation.',
  ),
  _Question(
    'Un problème est survenu pendant ma course, que faire ?',
    'Contactez immédiatement notre support via le bouton ci-dessous. '
        'Décrivez la course concernée : notre équipe vous répond dans les '
        'plus brefs délais.',
  ),
  _Question(
    'Comment envoyer un colis ?',
    'Depuis le bouton central "S", choisissez "Livraison", renseignez les '
        'adresses de retrait et de livraison ainsi que les coordonnées du '
        'destinataire.',
  ),
];

/// Centre d'aide : FAQ en accordéon + carte de contact du support.
class CentreAidePage extends StatelessWidget {
  const CentreAidePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Centre d\'aide')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Questions fréquentes',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            ..._questions.map(
              (q) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _CarteQuestion(question: q),
              ),
            ),
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.orangeLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.support_agent_outlined,
                          color: AppColors.orange,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Besoin d\'aide supplémentaire ?',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Notre équipe support est disponible 24/7 au +221 33 800 00 00 '
                    'ou support@groupesantine.sn.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.grey, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  PrimaryButton(
                    label: 'Contacter le support',
                    icon: Icons.chat_bubble_outline_rounded,
                    onPressed: () => PremiumDialog.afficher(
                      context,
                      icon: Icons.mark_email_read_outlined,
                      titre: 'Message envoyé',
                      message:
                          'Notre équipe support a bien reçu votre demande et vous '
                          'répondra très prochainement.',
                      succes: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CarteQuestion extends StatelessWidget {
  const _CarteQuestion({required this.question});

  final _Question question;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.greyBorder.withValues(alpha: 0.6)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const RoundedRectangleBorder(side: BorderSide.none),
          collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: Text(
            question.question,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
          ),
          iconColor: AppColors.orange,
          collapsedIconColor: AppColors.grey,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                question.reponse,
                style: const TextStyle(fontSize: 12.5, color: AppColors.grey, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
