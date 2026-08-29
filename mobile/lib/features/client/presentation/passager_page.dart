import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/map_placeholder.dart';
import '../../../core/widgets/payment_method_selector.dart';
import '../../../core/widgets/primary_button.dart';

/// Écran de réservation d'une course "Passager" (moto-taxi).
/// Design uniquement pour cette itération : aucun appel API, données
/// affichées à titre d'exemple (prix estimé, etc.).
class PassagerPage extends StatefulWidget {
  const PassagerPage({super.key});

  @override
  State<PassagerPage> createState() => _PassagerPageState();
}

class _PassagerPageState extends State<PassagerPage> {
  PaymentMethod _methodePaiement = PaymentMethod.wave;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Réserver une course')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MapPlaceholder(),
              const SizedBox(height: 24),
              const Text(
                'Où allez-vous ?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              const AppTextField(
                label: 'Adresse de départ',
                prefixIcon: Icons.my_location,
              ),
              const SizedBox(height: 12),
              const AppTextField(
                label: "Adresse d'arrivée",
                prefixIcon: Icons.location_on_outlined,
              ),
              const SizedBox(height: 24),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Prix estimé',
                          style: TextStyle(color: AppColors.grey),
                        ),
                        const Text(
                          '—',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Calculé une fois le trajet renseigné',
                      style: TextStyle(fontSize: 12, color: AppColors.grey),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Méthode de paiement',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.grey,
                      ),
                    ),
                    const SizedBox(height: 10),
                    PaymentMethodSelector(
                      value: _methodePaiement,
                      onChanged: (methode) =>
                          setState(() => _methodePaiement = methode),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Commander une moto-taxi',
                icon: Icons.two_wheeler_rounded,
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Réservation disponible à la Phase 4 (connexion API)',
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
