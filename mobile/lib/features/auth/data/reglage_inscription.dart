/// Réglages du tunnel d'inscription : validation du numéro par SMS et message
/// « Bienvenue chez SPRINT ». Mêmes valeurs que le serveur
/// (`functions/src/inscription.ts`) : un test les compare, car ouvrir l'un sans
/// l'autre laisserait l'app sans réponse ou le serveur sans écran.
///
/// OUVERT à la publication 128 (go du client, 15 novembre 2026) : validation du
/// numéro FACULTATIVE (« Plus tard »), bienvenue en écran et en notification,
/// pas d'e-mail de bienvenue. Le passage à `obligatoire` se fera sur demande du
/// client, après ses essais de SMS sur les opérateurs sénégalais. Réglages de la
/// console : FIREBASE_SETUP.md, section 13. Pour tout refermer : `fermee`,
/// `false` et une date lointaine (l'app se comporte alors comme la 126).
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

const EtatValidationTelephone validationTelephone = EtatValidationTelephone.facultative;

/// « Bienvenue chez SPRINT » à la fin de l'inscription (écran + notification).
const bool bienvenueAutomatique = true;

/// Un compte est « nouveau » s'il a été créé à cet instant ou après (date
/// d'ouverture du compte Firebase Auth, posée par Google) : l'instant de la mise
/// en ligne de la publication 128. Les comptes déjà inscrits ne sont jamais concernés.
final DateTime nouveauxComptesDepuis = DateTime.utc(2026, 11, 15, 19, 28);

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
