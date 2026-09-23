import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/maps/distance_utils.dart';
import '../../../core/maps/geocoding_service.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/address_search_field.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/payment_method_selector.dart';
import '../../../core/widgets/payment_method_sheet.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/trip_map.dart';
import '../../../firebase_options.dart';
import '../../courses/data/course_service.dart';
import '../../courses/data/courses_repository.dart';
import '../../courses/data/pricing_repository.dart';
import 'suivi_course_page.dart';

/// Écran d'envoi d'un colis, connecté à l'API. Carte réelle
/// (OpenStreetMap), géocodage d'adresses (Nominatim) et prix dynamique
/// (distance + temps + multiplicateur de trafic, calculé côté serveur)
/// remplacent les placeholders des itérations précédentes. Les champs
/// destinataire/description restent locaux : l'API ne les persiste pas
/// encore (hors périmètre de cette itération).
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
  final _pricingRepository = PricingRepository();
  final _courseService = CourseService();

  AdresseSuggestion? _retrait;
  AdresseSuggestion? _livraison;
  EstimationPrix? _estimation;
  bool _estimationEnCours = false;
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

  Future<void> _rafraichirEstimation() async {
    final distance = _distanceKm;
    if (distance == null) return;

    setState(() {
      _estimationEnCours = true;
      _estimation = null;
    });
    try {
      final estimation = await _pricingRepository.estimer(
        type: 'COLIS',
        distanceKm: distance,
      );
      if (mounted) setState(() => _estimation = estimation);
    } on ApiException catch (_) {
      // Prévisualisation optionnelle : en cas d'échec (ex : non connecté),
      // le prix sera de toute façon confirmé au moment de l'envoi.
    } finally {
      if (mounted) setState(() => _estimationEnCours = false);
    }
  }

  /// Pas de vérification de session ici : accéder à cet écran passe
  /// forcément par le shell Client, lui-même inaccessible sans
  /// connexion Firebase préalable (voir `WelcomePage`) — redemander une
  /// authentification à ce stade serait un mur redondant. Valider
  /// l'adresse ouvre directement le choix du mode de paiement, qui
  /// déclenche l'écriture dans Firestore.
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

    final methode = await afficherSelectionPaiementSheet(context);
    if (methode == null || !mounted) return;

    setState(() => _enCours = true);
    try {
      if (DefaultFirebaseOptions.estConfigure) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) {
          // Cas limite impossible en usage normal (voir la note de la
          // méthode) : on évite un crash plutôt que de rouvrir un mur
          // de connexion.
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Une erreur est survenue. Veuillez réessayer.')),
            );
          }
          return;
        }
        final estimation = _estimation ??
            await _pricingRepository.estimer(type: 'COLIS', distanceKm: _distanceKm!);
        final courseId = await _courseService.creerCourse(
          clientId: uid,
          type: 'COLIS',
          adresseDepart: _adresseRetraitController.text.trim(),
          adresseArrivee: _adresseLivraisonController.text.trim(),
          prixFcfa: estimation.prixFcfa,
          methodePaiement: methode.apiValue,
        );
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => SuiviCoursePage(courseId: courseId)),
        );
        return;
      }

      final course = await _coursesRepository.creerCourse({
        'type': 'COLIS',
        'adresseDepart': _adresseRetraitController.text.trim(),
        'latitudeDepart': _retrait!.latitude,
        'longitudeDepart': _retrait!.longitude,
        'adresseArrivee': _adresseLivraisonController.text.trim(),
        'latitudeArrivee': _livraison!.latitude,
        'longitudeArrivee': _livraison!.longitude,
        'distanceKm': _distanceKm,
        'methodePaiement': methode.apiValue,
      });
      if (!mounted) return;
      final prixTexte = course.prixFcfa != null
          ? ' Prix estimé : ${course.prixFcfa} FCFA.'
          : '';
      AppSnackbar.succes(
        context,
        'Votre demande a été envoyée aux chauffeurs à proximité.$prixTexte',
        icon: Icons.inventory_2_outlined,
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
                  onSelected: (suggestion) {
                    setState(() => _retrait = suggestion);
                    _rafraichirEstimation();
                  },
                ),
                const SizedBox(height: 12),
                AddressSearchField(
                  label: 'Adresse de livraison',
                  controller: _adresseLivraisonController,
                  prefixIcon: Icons.location_on_outlined,
                  onSelected: (suggestion) {
                    setState(() => _livraison = suggestion);
                    _rafraichirEstimation();
                  },
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
