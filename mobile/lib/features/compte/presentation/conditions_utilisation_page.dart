import 'package:flutter/material.dart';
import '../../../core/widgets/legal_page.dart';

class ConditionsUtilisationPage extends StatelessWidget {
  const ConditionsUtilisationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalPage(
      titre: 'Conditions d\'utilisation',
      icon: Icons.description_outlined,
      derniereMiseAJour: '22 septembre 2026',
      intro:
          'Les présentes Conditions Générales d\'Utilisation (« CGU ») régissent '
          'l\'accès et l\'utilisation de l\'application Sprint, éditée par Groupe '
          'Santine, mettant en relation des Clients avec des Conducteurs '
          'partenaires indépendants pour des services de transport de personnes '
          '(moto-taxi) et de livraison de colis à Dakar et dans ses environs. '
          'En créant un compte ou en utilisant l\'application, vous acceptez '
          'sans réserve les présentes CGU.',
      sections: [
        SectionJuridique(
          'Objet du service',
          'Sprint est une plateforme technologique qui met en relation, via une '
              'application mobile, des personnes souhaitant se déplacer ou '
              'expédier un colis (« Client ») avec des chauffeurs de moto-taxi '
              'indépendants (« Conducteur »). Groupe Santine n\'est ni '
              'transporteur, ni employeur des Conducteurs : elle fournit '
              'uniquement l\'outil de mise en relation, de géolocalisation, de '
              'calcul tarifaire et de paiement.',
        ),
        SectionJuridique(
          'Création de compte et éligibilité',
          'L\'utilisation de Sprint nécessite la création d\'un compte avec un '
              'numéro de téléphone valide. Le Client doit être âgé d\'au moins '
              '18 ans ou disposer de l\'autorisation d\'un représentant légal. '
              'Le Conducteur doit en outre justifier d\'un permis de conduire '
              'en cours de validité, d\'une assurance véhicule valide et de tout '
              'document exigé par la réglementation sénégalaise du transport. '
              'Les informations fournies lors de l\'inscription doivent être '
              'exactes et tenues à jour.',
        ),
        SectionJuridique(
          'Obligations du Client',
          'Le Client s\'engage à utiliser l\'application de bonne foi, à se '
              'présenter au point de prise en charge indiqué, à adopter un '
              'comportement respectueux envers le Conducteur et à régler le '
              'prix de la course selon le mode de paiement choisi (espèces, '
              'Wave, Orange Money ou solde Sprint). Toute utilisation '
              'frauduleuse, abusive ou portant atteinte à la sécurité d\'autrui '
              'peut entraîner la suspension immédiate du compte.',
        ),
        SectionJuridique(
          'Obligations du Conducteur partenaire',
          'Le Conducteur s\'engage à assurer la course dans le respect du code '
              'de la route, à maintenir son véhicule en bon état, à traiter '
              'chaque Client avec courtoisie et à ne pas facturer de montant '
              'différent de celui calculé par l\'application. Le Conducteur '
              'demeure seul responsable de ses obligations fiscales et '
              'sociales en tant que travailleur indépendant.',
        ),
        SectionJuridique(
          'Tarification et paiement',
          'Le prix de chaque course est calculé automatiquement par '
              'l\'application, sur la base de la distance estimée, de la durée '
              'du trajet et d\'un multiplicateur horaire (heures de pointe / '
              'heures creuses). Le prix affiché avant confirmation de la '
              'commande fait foi. Les paiements électroniques sont traités par '
              'nos partenaires Wave et Orange Money ; Groupe Santine ne '
              'conserve à aucun moment les identifiants de paiement du Client.',
        ),
        SectionJuridique(
          'Annulation',
          'Le Client peut annuler une course avant la prise en charge. Des '
              'annulations répétées et injustifiées après acceptation par un '
              'Conducteur peuvent donner lieu à des frais d\'annulation ou à '
              'une restriction temporaire d\'accès au service, afin de préserver '
              'l\'équité envers les Conducteurs partenaires.',
        ),
        SectionJuridique(
          'Responsabilité',
          'Groupe Santine met en œuvre les moyens raisonnables pour assurer la '
              'fiabilité de la plateforme, sans garantir l\'absence '
              'd\'interruption ou d\'erreur. Groupe Santine ne saurait être '
              'tenue responsable des actes commis par un Conducteur ou un '
              'Client en dehors du cadre strict de la mise en relation, ni des '
              'dommages indirects résultant de l\'utilisation du service.',
        ),
        SectionJuridique(
          'Suspension et résiliation',
          'Groupe Santine se réserve le droit de suspendre ou résilier tout '
              'compte en cas de violation des présentes CGU, de fraude, de '
              'comportement dangereux ou d\'usage détourné de l\'application, '
              'après notification lorsque les circonstances le permettent.',
        ),
        SectionJuridique(
          'Modification des présentes conditions',
          'Groupe Santine peut modifier les présentes CGU à tout moment pour '
              'tenir compte d\'évolutions légales, techniques ou commerciales. '
              'Les utilisateurs seront informés de toute modification '
              'substantielle via l\'application avant son entrée en vigueur.',
        ),
        SectionJuridique(
          'Droit applicable et juridiction',
          'Les présentes CGU sont soumises au droit sénégalais. Tout litige '
              'relatif à leur interprétation ou leur exécution relève de la '
              'compétence exclusive des juridictions de Dakar, sous réserve des '
              'dispositions d\'ordre public applicables.',
        ),
        SectionJuridique(
          'Contact',
          'Pour toute question relative aux présentes conditions, vous pouvez '
              'contacter Groupe Santine via le Centre d\'aide de l\'application '
              'ou à l\'adresse support@groupesantine.sn.',
        ),
      ],
    );
  }
}
