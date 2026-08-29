import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/map_placeholder.dart';
import '../../../core/widgets/payment_method_selector.dart';
import '../../../core/widgets/primary_button.dart';

/// Écran d'envoi d'un colis. Design uniquement pour cette itération :
/// aucun appel API, données affichées à titre d'exemple.
class ColisPage extends StatefulWidget {
  const ColisPage({super.key});

  @override
  State<ColisPage> createState() => _ColisPageState();
}

class _ColisPageState extends State<ColisPage> {
  PaymentMethod _methodePaiement = PaymentMethod.orangeMoney;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Envoyer un colis')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MapPlaceholder(),
              const SizedBox(height: 24),
              const Text(
                'Détails du colis',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              const AppTextField(
                label: 'Adresse de retrait',
                prefixIcon: Icons.my_location,
              ),
              const SizedBox(height: 12),
              const AppTextField(
                label: 'Adresse de livraison',
                prefixIcon: Icons.location_on_outlined,
              ),
              const SizedBox(height: 12),
              const AppTextField(
                label: 'Nom du destinataire',
                prefixIcon: Icons.person_outline,
              ),
              const SizedBox(height: 12),
              const AppTextField(
                label: 'Téléphone du destinataire',
                prefixIcon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              const AppTextField(
                label: 'Description du colis',
                hint: 'Ex : documents, petit carton...',
                prefixIcon: Icons.inventory_2_outlined,
                maxLines: 3,
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
                label: 'Envoyer le colis',
                icon: Icons.inventory_2_outlined,
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Envoi disponible à la Phase 4 (connexion API)',
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
