import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/demo_coordinates.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/token_storage.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/map_placeholder.dart';
import '../../../core/widgets/payment_method_selector.dart';
import '../../../core/widgets/primary_button.dart';
import '../../courses/data/courses_repository.dart';

/// Écran de réservation d'une course "Passager" (moto-taxi), connecté à
/// l'API. La carte reste un placeholder ; les coordonnées envoyées sont
/// des positions de démonstration à Dakar tant que le géocodage réel
/// n'est pas intégré.
class PassagerPage extends StatefulWidget {
  const PassagerPage({super.key});

  @override
  State<PassagerPage> createState() => _PassagerPageState();
}

class _PassagerPageState extends State<PassagerPage> {
  final _formKey = GlobalKey<FormState>();
  final _adresseDepartController = TextEditingController();
  final _adresseArriveeController = TextEditingController();
  final _coursesRepository = CoursesRepository();

  PaymentMethod _methodePaiement = PaymentMethod.wave;
  bool _enCours = false;

  @override
  void dispose() {
    _adresseDepartController.dispose();
    _adresseArriveeController.dispose();
    super.dispose();
  }

  Future<void> _commander() async {
    if (!_formKey.currentState!.validate()) return;

    final token = await TokenStorage().getAccessToken();
    if (token == null) {
      if (!mounted) return;
      final connecte = await context.push<bool>(AppRoutes.clientLogin);
      if (connecte != true || !mounted) return;
    }

    setState(() => _enCours = true);
    try {
      await _coursesRepository.creerCourse({
        'type': 'PASSAGER',
        'adresseDepart': _adresseDepartController.text.trim(),
        'latitudeDepart': DemoCoordinates.plateauLatitude,
        'longitudeDepart': DemoCoordinates.plateauLongitude,
        'adresseArrivee': _adresseArriveeController.text.trim(),
        'latitudeArrivee': DemoCoordinates.almadiesLatitude,
        'longitudeArrivee': DemoCoordinates.almadiesLongitude,
        'methodePaiement': _methodePaiement.apiValue,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Course demandée avec succès !')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Réserver une course')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
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
                AppTextField(
                  label: 'Adresse de départ',
                  controller: _adresseDepartController,
                  prefixIcon: Icons.my_location,
                  validator: (valeur) => (valeur == null || valeur.trim().isEmpty)
                      ? 'Adresse requise'
                      : null,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  label: "Adresse d'arrivée",
                  controller: _adresseArriveeController,
                  prefixIcon: Icons.location_on_outlined,
                  validator: (valeur) => (valeur == null || valeur.trim().isEmpty)
                      ? 'Adresse requise'
                      : null,
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
                  isLoading: _enCours,
                  onPressed: _commander,
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
