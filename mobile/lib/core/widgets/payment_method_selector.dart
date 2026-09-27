/// Groupe Santine est passé au 100% mobile money : les chauffeurs ne
/// gèrent plus d'espèces, seuls Wave et Orange Money sont acceptés
/// (voir `payment_method_sheet.dart` et `PaymentProcessingPage`).
enum PaymentMethod { wave, orangeMoney }

extension PaymentMethodLabel on PaymentMethod {
  String get label {
    switch (this) {
      case PaymentMethod.wave:
        return 'Wave';
      case PaymentMethod.orangeMoney:
        return 'Orange Money';
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
    }
  }
}
