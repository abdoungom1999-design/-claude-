/// Réglages du tunnel d'inscription : validation du numéro par SMS et message
/// « Bienvenue chez SPRINT ». Mêmes valeurs que le serveur
/// (`functions/src/inscription.ts`) : un test les compare, car ouvrir l'un sans
/// l'autre laisserait l'app sans réponse ou le serveur sans écran.
///
/// FERMÉ à la publication qui apporte le tunnel : l'app se comporte exactement
/// comme avant (aucun écran de plus, aucun appel de plus). L'ouverture se fait
/// avec l'accord du client, une fois les réglages de la console faits
/// (FIREBASE_SETUP.md, section 13).
library;

/// État de la validation du numéro (code à 6 chiffres reçu par SMS).
enum EtatValidationTelephone {
  /// Rien : état de la publication 126.
  fermee,

  /// L'écran est proposé aux nouveaux comptes ; « Plus tard » le passe.
  facultative,

  /// L'écran bloque l'espace d'un nouveau compte tant que le numéro n'est pas validé.
  obligatoire,
}

const EtatValidationTelephone validationTelephone = EtatValidationTelephone.fermee;

/// « Bienvenue chez SPRINT » à la fin de l'inscription (écran + notification).
const bool bienvenueAutomatique = false;

/// Un compte est « nouveau » s'il a été créé à cet instant ou après (date
/// d'ouverture du compte Firebase Auth, posée par Google). Avant l'ouverture
/// elle est lointaine : aucun compte n'est nouveau, donc aucun n'est concerné.
final DateTime nouveauxComptesDepuis = DateTime.utc(2099, 1, 1);

/// Réglages lus par l'app ; injectables dans les tests.
class ReglageInscription {
  const ReglageInscription({
    this.validation = validationTelephone,
    this.bienvenue = bienvenueAutomatique,
    DateTime? depuis,
  }) : _depuis = depuis;

  final EtatValidationTelephone validation;
  final bool bienvenue;
  final DateTime? _depuis;

  DateTime get depuis => _depuis ?? nouveauxComptesDepuis;

  /// Quelque chose est ouvert : sinon l'app n'ajoute rien, pas même une lecture.
  bool get ouvert => validation != EtatValidationTelephone.fermee || bienvenue;

  /// Compte créé à l'ouverture du tunnel ou après. Date inconnue : ancien (jamais sollicité).
  bool estNouveau(DateTime? creation) => creation != null && !creation.toUtc().isBefore(depuis.toUtc());
}
