import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../core/location/localiser.dart';
import '../../../core/maps/geocoding_service.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_fcfa.dart';
import '../../../core/widgets/address_search_field.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/payment_method_selector.dart';
import '../../../core/widgets/payment_method_sheet.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../firebase_options.dart';
import '../../courses/data/course_service.dart';
import '../../courses/data/depart_gps.dart';
import '../../portefeuille/data/portefeuille_service.dart';
import '../../courses/data/courses_repository.dart';
import '../../courses/data/estimation_course_controller.dart';
import '../../courses/data/pricing_repository.dart';
import '../../courses/presentation/estimation_prix_card.dart';
import 'payment_processing_page.dart';
import 'depart_gps_controller.dart';
import 'widgets/carte_commande.dart';
import 'widgets/champ_depart_gps.dart';
import '../../../core/widgets/onyx_vert.dart';

/// Écran de réservation d'une course "Passager" (moto-taxi), connecté à
/// l'API. Carte réelle (OpenStreetMap), géocodage d'adresses (Nominatim)
/// et prix estimé affiché avant la commande, qui reste impossible tant
/// qu'il n'est pas calculé (voir [EstimationCourseController]).
///
/// Le départ n'est pas à saisir : dès l'ouverture, l'écran prend la position
/// GPS du client et pré-remplit le champ par « Ma position actuelle » (voir
/// [DepartGps]). Le client n'a plus qu'à choisir son arrivée ; il peut
/// toujours changer le départ à la main.
class PassagerPage extends StatefulWidget {
  const PassagerPage({super.key, this.localiser, this.adresses, this.pricingRepository, this.coursesRepository});

  /// Injectables pour les tests : position de l'appareil, recherche
  /// d'adresses, calcul du prix et création de la course (mode démo).
  final Localiser? localiser;
  final ServiceAdresses? adresses;
  final PricingRepository? pricingRepository;
  final CoursesRepository? coursesRepository;

  @override
  State<PassagerPage> createState() => _PassagerPageState();
}

class _PassagerPageState extends State<PassagerPage> {
  final _formKey = GlobalKey<FormState>();
  final _adresseDepartController = TextEditingController();
  final _adresseArriveeController = TextEditingController();
  late final _coursesRepository = widget.coursesRepository ?? CoursesRepository();
  late final _estimation = EstimationCourseController(type: 'PASSAGER', pricingRepository: widget.pricingRepository);
  bool _enCours = false;

  late final _gps = DepartGpsController(
    estimation: _estimation,
    texte: _adresseDepartController,
    localiser: widget.localiser,
  );

  @override
  void initState() {
    super.initState();
    _gps.chercherPosition();
  }

  @override
  void dispose() {
    _gps.dispose();
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
  /// (voir [PaymentProcessingPage]) : le serveur ne crée la course
  /// qu'une fois le paiement confirmé par l'opérateur.
  Future<void> _commander() async {
    if (!_formKey.currentState!.validate()) return;
    // Le bouton est désactivé tant que le prix n'est pas calculé ; ce
    // garde-fou couvre un appel qui passerait malgré tout.
    final estimation = _estimation.estimation;
    final depart = _estimation.depart;
    final arrivee = _estimation.arrivee;
    if (!_estimation.peutCommander || estimation == null || depart == null || arrivee == null) return;

    final portefeuille = await PortefeuilleService().lirePourCommande();
    if (!mounted) return;
    final methode = await afficherSelectionPaiementSheet(
      context,
      montantFcfa: estimation.prixFcfa,
      portefeuille: portefeuille,
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
              type: 'PASSAGER',
              adresseDepart: DepartGps.pourLaCourse(depart, _adresseDepartController.text),
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
          // Le prix a pu changer (heure de pointe, nuit) : on le recalcule.
          _estimation.reessayer();
        }
        return;
      }

      final course = await _coursesRepository.creerCourse({
        'type': 'PASSAGER',
        'adresseDepart': DepartGps.pourLaCourse(depart, _adresseDepartController.text),
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
    return SousPageOnyx(child: Scaffold(
      appBar: AppBar(title: const Text('Réserver une course')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CarteCommande(estimation: _estimation, localiser: widget.localiser),
                const SizedBox(height: 24),
                const Text(
                  'Où allez-vous ?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                ChampDepartGps(gps: _gps, label: 'Adresse de départ', service: widget.adresses),
                const SizedBox(height: 12),
                AddressSearchField(
                  label: "Adresse d'arrivée",
                  controller: _adresseArriveeController,
                  service: widget.adresses,
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
                          style: const TextStyle(fontSize: 12, color: AppColors.texteDiscret),
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
    ));
  }
}
