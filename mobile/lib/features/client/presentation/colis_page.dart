import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/maps/distance_utils.dart';
import '../../../core/maps/geocoding_service.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/token_storage.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/address_search_field.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/payment_method_selector.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/trip_map.dart';
import '../../courses/data/courses_repository.dart';

/// Écran d'envoi d'un colis, connecté à l'API. Carte réelle
/// (OpenStreetMap) et géocodage d'adresses (Nominatim) remplacent le
/// placeholder et les coordonnées de démonstration des itérations
/// précédentes. Les champs destinataire/description restent locaux :
/// l'API ne les persiste pas encore (hors périmètre de cette itération).
class ColisPage extends StatefulWidget {
  const ColisPage({super.key});

  @override
  State<ColisPage> createState() => _ColisPageState();
}

class _ColisPageState extends State<ColisPage> {
  final _formKey = GlobalKey<FormState>();
  final _adresseRetraitController = TextEditingController();
  final _adresseLivraisonController = TextEditingController();
  final _coursesRepository = CoursesRepository();

  AdresseSuggestion? _retrait;
  AdresseSuggestion? _livraison;
  PaymentMethod _methodePaiement = PaymentMethod.orangeMoney;
  bool _enCours = false;

  double? get _distanceKm {
    if (_retrait == null || _livraison == null) return null;
    return DistanceUtils.distanceKm(
      latDepart: _retrait!.latitude,
      lngDepart: _retrait!.longitude,
      latArrivee: _livraison!.latitude,
      lngArrivee: _livraison!.longitude,
    );
  }

  @override
  void dispose() {
    _adresseRetraitController.dispose();
    _adresseLivraisonController.dispose();
    super.dispose();
  }

  Future<void> _envoyer() async {
    if (!_formKey.currentState!.validate()) return;
    if (_retrait == null || _livraison == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sélectionnez une adresse dans la liste de suggestions',
          ),
        ),
      );
      return;
    }

    final token = await TokenStorage().getAccessToken();
    if (token == null) {
      if (!mounted) return;
      final connecte = await context.push<bool>(AppRoutes.clientLogin);
      if (connecte != true || !mounted) return;
    }

    setState(() => _enCours = true);
    try {
      await _coursesRepository.creerCourse({
        'type': 'COLIS',
        'adresseDepart': _adresseRetraitController.text.trim(),
        'latitudeDepart': _retrait!.latitude,
        'longitudeDepart': _retrait!.longitude,
        'adresseArrivee': _adresseLivraisonController.text.trim(),
        'latitudeArrivee': _livraison!.latitude,
        'longitudeArrivee': _livraison!.longitude,
        'distanceKm': _distanceKm,
        'methodePaiement': _methodePaiement.apiValue,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Colis envoyé avec succès !')));
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
    final distance = _distanceKm;

    return Scaffold(
      appBar: AppBar(title: const Text('Envoyer un colis')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TripMap(
                  depart: _retrait != null
                      ? LatLng(_retrait!.latitude, _retrait!.longitude)
                      : null,
                  arrivee: _livraison != null
                      ? LatLng(_livraison!.latitude, _livraison!.longitude)
                      : null,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Détails du colis',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                AddressSearchField(
                  label: 'Adresse de retrait',
                  controller: _adresseRetraitController,
                  prefixIcon: Icons.my_location,
                  onSelected: (suggestion) =>
                      setState(() => _retrait = suggestion),
                ),
                const SizedBox(height: 12),
                AddressSearchField(
                  label: 'Adresse de livraison',
                  controller: _adresseLivraisonController,
                  prefixIcon: Icons.location_on_outlined,
                  onSelected: (suggestion) =>
                      setState(() => _livraison = suggestion),
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
                            'Distance estimée',
                            style: TextStyle(color: AppColors.grey),
                          ),
                          Text(
                            distance != null
                                ? '${distance.toStringAsFixed(1)} km'
                                : '—',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Prix : calcul dynamique à venir',
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
                  isLoading: _enCours,
                  onPressed: _envoyer,
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
