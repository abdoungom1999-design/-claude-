/// Modes de paiement d'une course (voir `payment_method_sheet.dart` et
/// `PaymentProcessingPage`). Espèces : le client paie le chauffeur, qui
/// doit la commission à la plateforme. Wave / Orange Money : la
/// plateforme encaisse et reverse sa part au chauffeur (voir
/// `CompteChauffeur`).
enum PaymentMethod { wave, orangeMoney, especes }

extension PaymentMethodLabel on PaymentMethod {
  String get label {
    switch (this) {
      case PaymentMethod.wave:
        return 'Wave';
      case PaymentMethod.orangeMoney:
        return 'Orange Money';
      case PaymentMethod.especes:
        return 'Espèces';
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
      case PaymentMethod.especes:
        return 'ESPECES';
    }
  }
}
