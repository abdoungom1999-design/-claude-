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
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/payment_method_selector.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/trip_map.dart';
import '../../courses/data/courses_repository.dart';
import '../../courses/data/pricing_repository.dart';

/// Écran de réservation d'une course "Passager" (moto-taxi), connecté à
/// l'API. Carte réelle (OpenStreetMap), géocodage d'adresses (Nominatim)
/// et prix dynamique (distance + temps + multiplicateur de trafic,
/// calculé côté serveur) remplacent les placeholders des itérations
/// précédentes.
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
  final _pricingRepository = PricingRepository();

  AdresseSuggestion? _depart;
  AdresseSuggestion? _arrivee;
  PaymentMethod _methodePaiement = PaymentMethod.wave;
  EstimationPrix? _estimation;
  bool _estimationEnCours = false;
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

  Future<void> _rafraichirEstimation() async {
    final distance = _distanceKm;
    if (distance == null) return;

    setState(() {
      _estimationEnCours = true;
      _estimation = null;
    });
    try {
      final estimation = await _pricingRepository.estimer(
        type: 'PASSAGER',
        distanceKm: distance,
      );
      if (mounted) setState(() => _estimation = estimation);
    } on ApiException catch (_) {
      // Prévisualisation optionnelle : en cas d'échec (ex : non connecté),
      // le prix sera de toute façon confirmé au moment de la commande.
    } finally {
      if (mounted) setState(() => _estimationEnCours = false);
    }
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
      await _rafraichirEstimation();
    }

    setState(() => _enCours = true);
    try {
      final course = await _coursesRepository.creerCourse({
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
      final prixTexte = course.prixFcfa != null
          ? ' Prix estimé : ${course.prixFcfa} FCFA.'
          : '';
      AppSnackbar.succes(
        context,
        'Votre demande a été envoyée aux chauffeurs à proximité.$prixTexte',
        icon: Icons.two_wheeler_rounded,
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
                  onSelected: (suggestion) {
                    setState(() => _depart = suggestion);
                    _rafraichirEstimation();
                  },
                ),
                const SizedBox(height: 12),
                AddressSearchField(
                  label: "Adresse d'arrivée",
                  controller: _adresseArriveeController,
                  prefixIcon: Icons.location_on_outlined,
                  onSelected: (suggestion) {
                    setState(() => _arrivee = suggestion);
                    _rafraichirEstimation();
                  },
                ),
                const SizedBox(height: 24),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Distance estimée',
                            style: TextStyle(color: AppColors.grey),
                          ),
                          Text(
                            distance != null
                                ? '${distance.toStringAsFixed(1)} km'
                                : '—',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Prix estimé',
                            style: TextStyle(color: AppColors.grey),
                          ),
                          _estimationEnCours
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  _estimation != null
                                      ? '${_estimation!.prixFcfa} FCFA'
                                      : '—',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.orange,
                                  ),
                                ),
                        ],
                      ),
                      if (_estimation != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '≈ ${_estimation!.dureeEstimeeMin} min'
                          '${_estimation!.multiplicateurTrafic > 1 ? ' · trafic x${_estimation!.multiplicateurTrafic.toStringAsFixed(1)}' : ''}',
                          style: const TextStyle(fontSize: 12, color: AppColors.grey),
                        ),
                      ],
                      const SizedBox(height: 16),
                      const Text(
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
