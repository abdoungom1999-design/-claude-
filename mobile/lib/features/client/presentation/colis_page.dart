import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format_fcfa.dart';
import '../../../core/widgets/address_search_field.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/payment_method_selector.dart';
import '../../../core/widgets/payment_method_sheet.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../firebase_options.dart';
import '../../courses/data/course_service.dart';
import '../../portefeuille/data/portefeuille_service.dart';
import '../../courses/data/courses_repository.dart';
import '../../courses/data/estimation_course_controller.dart';
import '../../courses/presentation/estimation_prix_card.dart';
import 'payment_processing_page.dart';
import 'widgets/carte_commande.dart';
import '../../../core/widgets/onyx_vert.dart';

/// Écran d'envoi d'un colis, connecté à l'API. Carte réelle
/// (OpenStreetMap), géocodage d'adresses (Nominatim) et prix estimé
/// affiché avant l'envoi, qui reste impossible tant qu'il n'est pas
/// calculé (voir [EstimationCourseController]). Les champs
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
  final _estimation = EstimationCourseController(type: 'COLIS');
  bool _enCours = false;

  @override
  void dispose() {
    _adresseRetraitController.dispose();
    _adresseLivraisonController.dispose();
    _estimation.dispose();
    super.dispose();
  }

  /// Pas de vérification de session ici : accéder à cet écran passe
  /// forcément par le shell Client, lui-même inaccessible sans
  /// connexion Firebase préalable (voir `WelcomePage`) — redemander une
  /// authentification à ce stade serait un mur redondant. Valider
  /// l'adresse ouvre le choix du mode de paiement, puis le sas de
  /// paiement obligatoire (voir [PaymentProcessingPage]) : le serveur ne
  /// crée la course qu'une fois le paiement confirmé par l'opérateur.
  Future<void> _envoyer() async {
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
              type: 'COLIS',
              adresseDepart: _adresseRetraitController.text.trim(),
              adresseArrivee: _adresseLivraisonController.text.trim(),
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
        'type': 'COLIS',
        'adresseDepart': _adresseRetraitController.text.trim(),
        'latitudeDepart': depart.latitude,
        'longitudeDepart': depart.longitude,
        'adresseArrivee': _adresseLivraisonController.text.trim(),
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
    return SousPageOnyx(child: Scaffold(
      appBar: AppBar(title: const Text('Envoyer un colis')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CarteCommande(estimation: _estimation),
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
                  onSelected: _estimation.definirDepart,
                  onEdited: _estimation.oublierDepart,
                ),
                const SizedBox(height: 12),
                AddressSearchField(
                  label: 'Adresse de livraison',
                  controller: _adresseLivraisonController,
                  prefixIcon: Icons.location_on_outlined,
                  onSelected: _estimation.definirArrivee,
                  onEdited: _estimation.oublierArrivee,
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
                EstimationPrixCard(controller: _estimation),
                const SizedBox(height: 24),
                ListenableBuilder(
                  listenable: _estimation,
                  builder: (context, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PrimaryButton(
                        label: 'Envoyer le colis',
                        icon: Icons.inventory_2_outlined,
                        isLoading: _enCours,
                        onPressed: _estimation.peutCommander ? _envoyer : null,
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
