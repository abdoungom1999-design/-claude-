import 'package:flutter/material.dart';
import '../../../core/widgets/legal_page.dart';

class PolitiqueConfidentialitePage extends StatelessWidget {
  const PolitiqueConfidentialitePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalPage(
      titre: 'Politique de confidentialité',
      icon: Icons.privacy_tip_outlined,
      derniereMiseAJour: '9 octobre 2026',
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
              'téléphone, email) ; les données de localisation (votre position '
              'GPS lorsque vous choisissez « Ma position actuelle » comme point '
              'de départ, et la position en temps réel pendant une course, pour '
              'le suivi et la mise en relation avec un Conducteur) ; '
              'l\'historique de vos courses et livraisons ; les données '
              'techniques (type d\'appareil, adresse IP) ainsi que les rapports '
              'techniques d\'erreur de l\'application Android (voir « Suivi '
              'technique des erreurs ») ; et, pour les Conducteurs, les données '
              'relatives au véhicule et aux documents réglementaires.',
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
              'requis (ex : notifications, position GPS de votre téléphone), '
              'sur nos obligations légales (ex : lutte contre la fraude, '
              'sécurité routière) et sur notre intérêt légitime à assurer la '
              'stabilité et la sécurité du service (ex : suivi technique des '
              'erreurs).',
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
          'Position GPS et mise en relation',
          'Lorsque vous commandez une course avec « Ma position actuelle », '
              'l\'application relève la position GPS de votre téléphone, avec '
              'votre autorisation, et l\'enregistre avec votre demande afin que '
              'le Conducteur vous retrouve. Les Conducteurs disponibles ont accès '
              'aux demandes en attente (point de départ, y compris votre position '
              'GPS lorsque vous l\'avez choisie, destination et prix). Une fois '
              'la course acceptée, votre position s\'affiche sur la carte du '
              'Conducteur qui l\'accepte, avec l\'itinéraire pour vous rejoindre ; '
              'pour calculer cet itinéraire, la position du Conducteur et le '
              'point de rendez-vous sont transmis à notre prestataire Google '
              '(Google Maps Platform). Votre position n\'est pas utilisée à des '
              'fins publicitaires. Vous pouvez refuser ou retirer l\'autorisation '
              'de localisation dans les réglages de votre téléphone : vous '
              'saisissez alors votre adresse de départ à la main.',
        ),
        SectionJuridique(
          'Suivi technique des erreurs',
          'Lorsque l\'application Android Sprint rencontre une erreur imprévue '
              'ou se ferme brutalement, un rapport technique est envoyé '
              'automatiquement à notre prestataire Google (service Firebase '
              'Crashlytics) afin que nous puissions corriger le problème '
              'rapidement. Ce rapport contient uniquement des informations '
              'techniques : version de l\'application, modèle et version '
              'Android du téléphone, état de l\'application au moment de '
              'l\'incident, message technique de l\'erreur et un identifiant '
              'technique propre à l\'installation. Sprint n\'y ajoute ni votre '
              'nom, ni votre numéro de téléphone, ni votre adresse e-mail, ni '
              'l\'identifiant de votre compte. Ces rapports servent uniquement '
              'à améliorer la stabilité et la sécurité de l\'application ; ils '
              'ne sont pas utilisés à des fins publicitaires.',
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
