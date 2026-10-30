/// Groupe Santine est passé au 100% mobile money : les chauffeurs ne
/// gèrent plus d'espèces. Le client paie avec Wave, ou avec le solde du
/// Portefeuille Sprint [portefeuille] (lui-même rechargé par Wave) ; voir
/// `payment_method_sheet.dart` et `PaymentProcessingPage`.
///
/// [orangeMoney] reste dans l'énumération pour l'historique (courses et
/// recharges, libellés). Son fournisseur réel est branché côté serveur, mais
/// il n'est proposé que selon [accesOrangeMoney] : voir
/// [moyensMobileMoneyPour].
enum PaymentMethod { wave, orangeMoney, portefeuille }

/// Qui peut payer avec Orange Money (décisions du client, 29 octobre 2026).
enum AccesOrangeMoney {
  /// Personne : ni proposé, ni accepté par le serveur.
  ferme,

  /// Seulement les comptes clients marqués « Testeur Orange Money » par un
  /// Admin (essai réel de bout en bout) ; les autres clients ne voient rien.
  testeurs,

  /// Tous les clients (ouverture officielle).
  tous,
}

/// Réglage en service. Ne change qu'avec le go du client, en même temps que
/// son jumeau du serveur (`ACCES_ORANGE_MONEY`,
/// `functions/src/methodes_paiement.ts`) : un test du serveur vérifie qu'ils
/// sont d'accord.
const accesOrangeMoney = AccesOrangeMoney.testeurs;

/// Où Orange Money encaisse (décision du client).
enum EnvironnementOrangeMoney {
  /// Bac à sable d'Orange : données de test, aucun argent réel.
  bacASable,

  /// Production : argent réel, versé sur le compte marchand de Groupe Santine.
  production,
}

/// Réglage en service. Ne change qu'avec le go du client, en même temps que
/// son jumeau du serveur (`ENVIRONNEMENT_ORANGE_MONEY`,
/// `functions/src/methodes_paiement.ts`) : un test du serveur vérifie qu'ils
/// sont d'accord.
const environnementOrangeMoney = EnvironnementOrangeMoney.bacASable;

/// Le profil (`users/{uid}`) porte-t-il la marque « Testeur Orange Money »,
/// posée par un Admin ? Seul `true` compte, comme pour le serveur.
bool estTesteurOrangeMoney(Map<String, dynamic>? profil) => profil?['testeurOrangeMoney'] == true;

/// Moyens de mobile money proposés à ce client, dans l'ordre d'affichage. Le
/// serveur applique la même règle (`methodesPour`, functions/src/methodes_paiement.ts).
List<PaymentMethod> moyensMobileMoneyPour({required bool testeur, AccesOrangeMoney acces = accesOrangeMoney}) => [
      PaymentMethod.wave,
      if (acces == AccesOrangeMoney.tous || (acces == AccesOrangeMoney.testeurs && testeur)) PaymentMethod.orangeMoney,
    ];

/// Ce moyen débite-t-il vraiment le client ? Wave passe encore par le faux
/// opérateur du serveur (aucune somme débitée) ; Orange Money, en production.
extension PaymentMethodArgentReel on PaymentMethod {
  bool argentReel({EnvironnementOrangeMoney environnement = environnementOrangeMoney}) => switch (this) {
        PaymentMethod.orangeMoney => environnement == EnvironnementOrangeMoney.production,
        PaymentMethod.wave || PaymentMethod.portefeuille => false,
      };
}

/// Mention sous les [moyens] proposés : lesquels débitent vraiment le client.
String mentionPaiement(List<PaymentMethod> moyens, {EnvironnementOrangeMoney environnement = environnementOrangeMoney}) {
  final reels = [for (final m in moyens) if (m.argentReel(environnement: environnement)) m.label];
  final simules = [for (final m in moyens) if (!m.argentReel(environnement: environnement)) m.label];
  if (reels.isEmpty) return 'Paiement sécurisé — mode test, aucun débit réel';
  if (simules.isEmpty) return 'Paiement sécurisé';
  return 'Paiement sécurisé — ${reels.join(', ')} : argent réel · ${simules.join(', ')} : mode test, aucun débit réel';
}

extension PaymentMethodLabel on PaymentMethod {
  String get label {
    switch (this) {
      case PaymentMethod.wave:
        return 'Wave';
      case PaymentMethod.orangeMoney:
        return 'Orange Money';
      case PaymentMethod.portefeuille:
        return 'Solde Sprint';
    }
  }
}

/// Ce que le client fait une fois la page de l'opérateur ouverte (sas de
/// paiement et de recharge). Orange Money s'ouvre dans Max It ou Orange
/// Money, où seul le client tape son code secret.
extension PaymentMethodConsigne on PaymentMethod {
  String get consignePaiement => switch (this) {
        PaymentMethod.orangeMoney =>
          'Validez le paiement dans Max It ou Orange Money avec votre code secret '
              '(Sprint ne vous le demandera jamais)',
        _ => "Payez sur la page $label qui vient de s'ouvrir",
      };
}

/// Valeur attendue par le serveur (callables `creerPaiement` et `creerRecharge`).
extension PaymentMethodApi on PaymentMethod {
  String get apiValue {
    switch (this) {
      case PaymentMethod.wave:
        return 'WAVE';
      case PaymentMethod.orangeMoney:
        return 'ORANGE_MONEY';
      case PaymentMethod.portefeuille:
        return 'PORTEFEUILLE';
    }
  }
}
