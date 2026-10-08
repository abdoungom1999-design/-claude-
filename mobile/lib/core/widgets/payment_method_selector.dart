/// Groupe Santine est passé au 100% mobile money : les chauffeurs ne
/// gèrent plus d'espèces. Le client paie avec Wave, ou avec le solde du
/// Portefeuille Sprint [portefeuille] (lui-même rechargé par Wave) ; voir
/// `payment_method_sheet.dart` et `PaymentProcessingPage`.
///
/// [orangeMoney] reste dans l'énumération pour l'historique (courses et
/// recharges d'avant la fermeture, libellés), mais n'est plus proposé ni
/// accepté par le serveur tant que son fournisseur réel (contrat Sonatel)
/// n'est pas branché : voir [moyensMobileMoneyDisponibles].
enum PaymentMethod { wave, orangeMoney, portefeuille }

/// Moyens de mobile money proposables aujourd'hui, dans l'ordre d'affichage.
/// Le serveur applique la même liste (`functions/src/methodes_paiement.ts`) :
/// pour rouvrir Orange Money, brancher son fournisseur, l'ajouter ici ET là-bas.
const moyensMobileMoneyDisponibles = <PaymentMethod>[PaymentMethod.wave];

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
