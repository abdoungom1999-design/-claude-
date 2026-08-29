import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

enum PaymentMethod { wave, orangeMoney, cash }

extension PaymentMethodLabel on PaymentMethod {
  String get label {
    switch (this) {
      case PaymentMethod.wave:
        return 'Wave';
      case PaymentMethod.orangeMoney:
        return 'Orange Money';
      case PaymentMethod.cash:
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
      case PaymentMethod.cash:
        return 'CASH';
    }
  }
}

/// Sélecteur de méthode de paiement (Wave / Orange Money / Espèces) sous
/// forme de puces sélectionnables.
class PaymentMethodSelector extends StatelessWidget {
  const PaymentMethodSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final PaymentMethod value;
  final ValueChanged<PaymentMethod> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: PaymentMethod.values.map((methode) {
        final selectionne = methode == value;
        return ChoiceChip(
          label: Text(methode.label),
          selected: selectionne,
          onSelected: (_) => onChanged(methode),
          labelStyle: TextStyle(
            color: selectionne ? AppColors.background : AppColors.text,
            fontWeight: FontWeight.w600,
          ),
          selectedColor: AppColors.orange,
          backgroundColor: AppColors.greyLight,
          side: BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        );
      }).toList(),
    );
  }
}
