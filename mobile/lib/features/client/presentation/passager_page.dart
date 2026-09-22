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
import '../../../core/widgets/payment_method_selector.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/trip_map.dart';
import '../../courses/data/courses_repository.dart';

/// Écran de réservation d'une course "Passager" (moto-taxi), connecté à
/// l'API. Carte réelle (OpenStreetMap) et géocodage d'adresses (Nominatim)
/// remplacent le placeholder et les coordonnées de démonstration des
/// itérations précédentes.
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

  AdresseSuggestion? _depart;
  AdresseSuggestion? _arrivee;
  PaymentMethod _methodePaiement = PaymentMethod.wave;
  bool _enCours = false;

  double? get _distanceKm {
    if (_depart == null || _arrivee == null) return null;
    return DistanceUtils.distanceKm(
      latDepart: _depart!.latitude,
      lngDepart: _depart!.longitude,
      latArrivee: _arrivee!.latitude,
      lngArrivee: _arrivee!.longitude,
    );
  }

  @override
  void dispose() {
    _adresseDepartController.dispose();
    _adresseArriveeController.dispose();
    super.dispose();
  }

  Future<void> _commander() async {
    if (!_formKey.currentState!.validate()) return;
    if (_depart == null || _arrivee == null) {
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
        'type': 'PASSAGER',
        'adresseDepart': _adresseDepartController.text.trim(),
        'latitudeDepart': _depart!.latitude,
        'longitudeDepart': _depart!.longitude,
        'adresseArrivee': _adresseArriveeController.text.trim(),
        'latitudeArrivee': _arrivee!.latitude,
        'longitudeArrivee': _arrivee!.longitude,
        'distanceKm': _distanceKm,
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
    final distance = _distanceKm;

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
                TripMap(
                  depart: _depart != null
                      ? LatLng(_depart!.latitude, _depart!.longitude)
                      : null,
                  arrivee: _arrivee != null
                      ? LatLng(_arrivee!.latitude, _arrivee!.longitude)
                      : null,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Où allez-vous ?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                AddressSearchField(
                  label: 'Adresse de départ',
                  controller: _adresseDepartController,
                  prefixIcon: Icons.my_location,
                  onSelected: (suggestion) =>
                      setState(() => _depart = suggestion),
                ),
                const SizedBox(height: 12),
                AddressSearchField(
                  label: "Adresse d'arrivée",
                  controller: _adresseArriveeController,
                  prefixIcon: Icons.location_on_outlined,
                  onSelected: (suggestion) =>
                      setState(() => _arrivee = suggestion),
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
