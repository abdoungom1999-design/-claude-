/// Groupe Santine est passé au 100% mobile money : les chauffeurs ne
/// gèrent plus d'espèces. Le client paie avec Wave, ou avec le solde du
/// Portefeuille Sprint [portefeuille] (lui-même rechargé par Wave) ; voir
/// `payment_method_sheet.dart` et `PaymentProcessingPage`.
///
/// [orangeMoney] reste dans l'énumération pour l'historique (courses et
/// recharges, libellés). Son fournisseur réel est branché côté serveur, mais
/// il n'est proposé ni accepté tant que [orangeMoneyOuvert] est faux : voir
/// [moyensMobileMoneyDisponibles].
enum PaymentMethod { wave, orangeMoney, portefeuille }

/// Orange Money proposé aux clients. Ne passe à `true` qu'avec le go du
/// client, en même temps que son jumeau du serveur (`ORANGE_MONEY_OUVERT`,
/// `functions/src/methodes_paiement.ts`) : un test du serveur vérifie qu'ils
/// sont d'accord.
const bool orangeMoneyOuvert = false;

/// Moyens de mobile money proposables aujourd'hui, dans l'ordre d'affichage.
/// Le serveur applique la même liste (`functions/src/methodes_paiement.ts`).
const moyensMobileMoneyDisponibles = <PaymentMethod>[
  PaymentMethod.wave,
  if (orangeMoneyOuvert) PaymentMethod.orangeMoney,
];

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
