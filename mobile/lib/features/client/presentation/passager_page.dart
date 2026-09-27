import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_fcfa.dart';
import '../../../core/widgets/address_search_field.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/payment_method_selector.dart';
import '../../../core/widgets/payment_method_sheet.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/trip_map.dart';
import '../../../firebase_options.dart';
import '../../courses/data/course_service.dart';
import '../../courses/data/courses_repository.dart';
import '../../courses/data/estimation_course_controller.dart';
import '../../courses/presentation/estimation_prix_card.dart';
import 'payment_processing_page.dart';

/// Écran de réservation d'une course "Passager" (moto-taxi), connecté à
/// l'API. Carte réelle (OpenStreetMap), géocodage d'adresses (Nominatim)
/// et prix estimé affiché avant la commande, qui reste impossible tant
/// qu'il n'est pas calculé (voir [EstimationCourseController]).
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
  final _estimation = EstimationCourseController(type: 'PASSAGER');
  bool _enCours = false;

  @override
  void dispose() {
    _adresseDepartController.dispose();
    _adresseArriveeController.dispose();
    _estimation.dispose();
    super.dispose();
  }

  /// La commande n'a plus de vérification de session ici : accéder à
  /// cet écran passe forcément par le shell Client, lui-même
  /// inaccessible sans connexion Firebase préalable (voir
  /// `WelcomePage`) — redemander une authentification à ce stade
  /// serait un mur redondant. À la place, valider l'adresse ouvre le
  /// choix du mode de paiement, puis le sas de paiement obligatoire
  /// (voir [PaymentProcessingPage]) qui déclenche lui-même l'écriture
  /// dans Firestore une fois la simulation de confirmation terminée.
  Future<void> _commander() async {
    if (!_formKey.currentState!.validate()) return;
    // Le bouton est désactivé tant que le prix n'est pas calculé ; ce
    // garde-fou couvre un appel qui passerait malgré tout.
    final estimation = _estimation.estimation;
    final depart = _estimation.depart;
    final arrivee = _estimation.arrivee;
    if (!_estimation.peutCommander || estimation == null || depart == null || arrivee == null) return;

    final methode = await afficherSelectionPaiementSheet(
      context,
      montantFcfa: estimation.prixFcfa,
    );
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
        final erreurPaiement = await Navigator.of(context).push<String>(
          MaterialPageRoute(
            builder: (_) => PaymentProcessingPage(
              methode: methode,
              clientId: uid,
              type: 'PASSAGER',
              adresseDepart: _adresseDepartController.text.trim(),
              adresseArrivee: _adresseArriveeController.text.trim(),
              prixFcfa: estimation.prixFcfa,
              points: PointsCourse(
                latitudeDepart: depart.latitude,
                longitudeDepart: depart.longitude,
                latitudeArrivee: arrivee.latitude,
                longitudeArrivee: arrivee.longitude,
              ),
            ),
          ),
        );
        if (erreurPaiement != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erreurPaiement)));
        }
        return;
      }

      final course = await _coursesRepository.creerCourse({
        'type': 'PASSAGER',
        'adresseDepart': _adresseDepartController.text.trim(),
        'latitudeDepart': depart.latitude,
        'longitudeDepart': depart.longitude,
        'adresseArrivee': _adresseArriveeController.text.trim(),
        'latitudeArrivee': arrivee.latitude,
        'longitudeArrivee': arrivee.longitude,
        'distanceKm': _estimation.distanceKm,
        'methodePaiement': methode.apiValue,
      });
      if (!mounted) return;
      final prixTexte = course.prixFcfa != null
          ? ' Prix estimé : ${formaterFcfa(course.prixFcfa!)}.'
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
                ListenableBuilder(
                  listenable: _estimation,
                  builder: (context, _) {
                    final depart = _estimation.depart;
                    final arrivee = _estimation.arrivee;
                    return TripMap(
                      depart: depart != null ? LatLng(depart.latitude, depart.longitude) : null,
                      arrivee: arrivee != null ? LatLng(arrivee.latitude, arrivee.longitude) : null,
                    );
                  },
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
                  onSelected: _estimation.definirDepart,
                  onEdited: _estimation.oublierDepart,
                ),
                const SizedBox(height: 12),
                AddressSearchField(
                  label: "Adresse d'arrivée",
                  controller: _adresseArriveeController,
                  prefixIcon: Icons.location_on_outlined,
                  onSelected: _estimation.definirArrivee,
                  onEdited: _estimation.oublierArrivee,
                ),
                const SizedBox(height: 24),
                EstimationPrixCard(controller: _estimation),
                const SizedBox(height: 24),
                ListenableBuilder(
                  listenable: _estimation,
                  builder: (context, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PrimaryButton(
                        label: 'Commander une moto-taxi',
                        icon: Icons.two_wheeler_rounded,
                        isLoading: _enCours,
                        onPressed: _estimation.peutCommander ? _commander : null,
                      ),
                      if (!_estimation.peutCommander) ...[
                        const SizedBox(height: 8),
                        Text(
                          _estimation.etat == EtatEstimation.calcul
                              ? 'Calcul du prix en cours…'
                              : 'Le prix doit être calculé avant de commander.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, color: AppColors.grey),
                        ),
                      ],
                    ],
                  ),
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
