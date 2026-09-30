/// Groupe Santine est passé au 100% mobile money : les chauffeurs ne
/// gèrent plus d'espèces, seuls Wave et Orange Money sont acceptés
/// (voir `payment_method_sheet.dart` et `PaymentProcessingPage`), soit
/// directement, soit via le solde du Portefeuille Sprint [portefeuille]
/// (lui-même rechargé par Wave ou Orange Money).
enum PaymentMethod { wave, orangeMoney, portefeuille }

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

/// Valeur attendue par l'API NestJS (enum `MethodePaiement` Prisma).
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
