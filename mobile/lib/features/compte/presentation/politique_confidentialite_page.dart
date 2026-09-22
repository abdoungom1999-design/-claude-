import 'package:flutter/material.dart';
import '../../../core/widgets/legal_page.dart';

class PolitiqueConfidentialitePage extends StatelessWidget {
  const PolitiqueConfidentialitePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalPage(
      titre: 'Politique de confidentialité',
      icon: Icons.privacy_tip_outlined,
      derniereMiseAJour: '22 septembre 2026',
      intro:
          'Groupe Santine attache une importance particulière à la protection '
          'de vos données personnelles. La présente politique explique quelles '
          'données sont collectées via l\'application Sprint, pourquoi, et '
          'quels droits vous pouvez exercer, conformément à la loi sénégalaise '
          'n° 2008-12 du 25 janvier 2008 relative à la protection des données '
          'à caractère personnel.',
      sections: [
        SectionJuridique(
          'Responsable du traitement',
          'Le responsable du traitement des données collectées via Sprint est '
              'Groupe Santine, dont le siège est basé à Dakar, Sénégal. Toute '
              'question relative à vos données peut être adressée à notre '
              'délégué à la protection des données via '
              'donnees@groupesantine.sn.',
        ),
        SectionJuridique(
          'Données collectées',
          'Nous collectons : les données d\'identification (nom, numéro de '
              'téléphone, email) ; les données de localisation en temps réel '
              'pendant une course (pour le suivi et la mise en relation avec '
              'un Conducteur) ; l\'historique de vos courses et livraisons ; '
              'les données techniques (type d\'appareil, adresse IP) ; et, pour '
              'les Conducteurs, les données relatives au véhicule et aux '
              'documents réglementaires.',
        ),
        SectionJuridique(
          'Finalités du traitement',
          'Ces données sont utilisées pour : permettre la mise en relation '
              'Client/Conducteur et le calcul du trajet ; traiter les '
              'paiements via nos partenaires Wave et Orange Money ; assurer la '
              'sécurité des utilisateurs et prévenir la fraude ; améliorer la '
              'qualité du service ; et respecter nos obligations légales.',
        ),
        SectionJuridique(
          'Base légale',
          'Le traitement repose sur l\'exécution du contrat de service qui '
              'vous lie à Groupe Santine lors de l\'utilisation de '
              'l\'application, sur votre consentement lorsque celui-ci est '
              'requis (ex : notifications), et sur nos obligations légales '
              '(ex : lutte contre la fraude, sécurité routière).',
        ),
        SectionJuridique(
          'Partage des données',
          'Vos données peuvent être partagées avec : le Conducteur ou le '
              'Client concerné par une course (nom, position, téléphone de '
              'contact) dans la stricte mesure nécessaire à sa bonne exécution ; '
              'nos prestataires de paiement (Wave, Orange Money) pour le '
              'traitement des transactions ; et les autorités compétentes '
              'lorsque la loi l\'exige. Groupe Santine ne vend jamais vos '
              'données personnelles à des tiers à des fins commerciales.',
        ),
        SectionJuridique(
          'Durée de conservation',
          'Les données de compte sont conservées pendant toute la durée de '
              'votre relation avec Sprint, puis archivées pour une durée '
              'limitée conforme aux obligations légales (notamment '
              'comptables), avant suppression ou anonymisation définitive.',
        ),
        SectionJuridique(
          'Sécurité des données',
          'Groupe Santine met en œuvre des mesures techniques et '
              'organisationnelles appropriées (chiffrement des mots de passe, '
              'connexions sécurisées, accès restreint) pour protéger vos '
              'données contre tout accès non autorisé, perte ou divulgation.',
        ),
        SectionJuridique(
          'Vos droits',
          'Conformément à la réglementation sénégalaise sur la protection des '
              'données personnelles, vous disposez d\'un droit d\'accès, de '
              'rectification, d\'effacement et d\'opposition sur vos données. '
              'Vous pouvez exercer ces droits directement depuis l\'écran '
              '« Informations personnelles » de l\'application, ou en '
              'contactant notre support. Vous disposez également du droit '
              'd\'introduire une réclamation auprès de la Commission de '
              'protection des données personnelles (CDP) du Sénégal.',
        ),
        SectionJuridique(
          'Cookies et traceurs',
          'La version web de Sprint peut utiliser des cookies techniques '
              'strictement nécessaires au fonctionnement du service (maintien '
              'de session, préférences). Aucun cookie publicitaire tiers '
              'n\'est utilisé à ce stade.',
        ),
        SectionJuridique(
          'Modifications de la politique',
          'Cette politique peut être mise à jour pour refléter des évolutions '
              'légales ou fonctionnelles. La date de dernière mise à jour est '
              'indiquée en haut de cette page ; toute modification '
              'substantielle vous sera signalée dans l\'application.',
        ),
        SectionJuridique(
          'Contact',
          'Pour toute question ou demande relative à vos données personnelles, '
              'contactez-nous à donnees@groupesantine.sn ou via le Centre '
              'd\'aide de l\'application.',
        ),
      ],
    );
  }
}
