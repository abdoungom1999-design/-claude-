import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/ecran_statut_onyx.dart';
import '../../../core/widgets/onyx_light.dart';
import '../../../core/widgets/premium_dialog.dart';

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

/// Centre d'aide : FAQ en accordéon + carte de contact du support, en
/// charte « Onyx & Light » (cartes verre, accents orange).
class CentreAidePage extends StatelessWidget {
  const CentreAidePage({super.key});

  @override
  Widget build(BuildContext context) {
    return EcranOnyxLight(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          foregroundColor: AppColors.onyx,
          title: const Text(
            "Centre d'aide",
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3, color: AppColors.onyx),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  const Text('Questions fréquentes', style: styleTitreSection),
                  const SizedBox(height: 12),
                  ..._questions.map(
                    (q) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _CarteQuestion(question: q),
                    ),
                  ),
                  const SizedBox(height: 14),
                  CarteVerre(
                    rayon: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppColors.onyx,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(Icons.support_agent_outlined, color: AppColors.orange, size: 22),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                "Besoin d'aide supplémentaire ?",
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.onyx),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Notre équipe support est disponible 24/7 au +221 33 800 00 00 '
                          'ou support@groupesantine.sn.',
                          style: TextStyle(fontSize: 13, color: AppColors.texteDiscret, height: 1.5),
                        ),
                        const SizedBox(height: 16),
                        BoutonStatutPrincipal(
                          label: 'Contacter le support',
                          icone: Icons.chat_bubble_outline_rounded,
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
          ),
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
    return CarteVerre(
      rayon: 20,
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
        ),
        child: ExpansionTile(
          backgroundColor: Colors.transparent,
          collapsedBackgroundColor: Colors.transparent,
          shape: const RoundedRectangleBorder(side: BorderSide.none),
          collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
          tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          title: Text(
            question.question,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.onyx),
          ),
          iconColor: AppColors.orange,
          collapsedIconColor: AppColors.onyx,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                question.reponse,
                style: const TextStyle(fontSize: 13, color: AppColors.texteDiscret, height: 1.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
