import 'package:flutter/foundation.dart';
import '../../../core/maps/distance_utils.dart';
import '../../../core/maps/geocoding_service.dart';
import '../../../core/network/api_exception.dart';
import 'course_service.dart';
import 'pricing_repository.dart';

enum EtatEstimation {
  /// Départ ou arrivée pas encore choisi dans les suggestions.
  adressesManquantes,
  calcul,
  prete,
  erreur,
}

/// Estimation du prix d'une course pendant la saisie des adresses
/// (écrans Passager et Colis) : recalculée à chaque adresse choisie,
/// oubliée dès qu'une adresse est retouchée à la main, et seule clé
/// pour commander ([peutCommander]).
///
/// Distance : estimation par la route à partir des coordonnées GPS des
/// adresses ([DistanceUtils.distanceRouteEstimeeKm]). Prix : calculé par
/// le serveur ([PricingRepository], Cloud Function `estimerPrix`) —
/// prise en charge, prix au kilomètre, majoration heure de pointe ou
/// nuit, prix minimum.
class EstimationCourseController extends ChangeNotifier {
  EstimationCourseController({required this.type, PricingRepository? pricingRepository})
      : _pricingRepository = pricingRepository ?? PricingRepository();

  /// `'PASSAGER'` ou `'COLIS'`.
  final String type;
  final PricingRepository _pricingRepository;

  /// En dessous, départ et arrivée sont considérés comme le même lieu.
  static const distanceMinimaleKm = 0.1;

  AdresseSuggestion? _depart;
  AdresseSuggestion? _arrivee;
  EstimationPrix? _estimation;
  String? _erreur;
  bool _calcul = false;
  bool _ferme = false;

  /// Numéro de la dernière demande : une réponse plus ancienne, arrivée
  /// en retard, ne doit pas écraser le prix du dernier trajet choisi.
  int _demande = 0;

  AdresseSuggestion? get depart => _depart;
  AdresseSuggestion? get arrivee => _arrivee;
  EstimationPrix? get estimation => _estimation;
  String? get erreur => _erreur;

  EtatEstimation get etat {
    if (_depart == null || _arrivee == null) return EtatEstimation.adressesManquantes;
    if (_calcul) return EtatEstimation.calcul;
    if (_estimation != null) return EtatEstimation.prete;
    return EtatEstimation.erreur;
  }

  bool get peutCommander => etat == EtatEstimation.prete;

  /// Coordonnées du trajet choisi, envoyées au serveur.
  PointsCourse? get trajet {
    final depart = _depart;
    final arrivee = _arrivee;
    if (depart == null || arrivee == null) return null;
    return PointsCourse(
      latitudeDepart: depart.latitude,
      longitudeDepart: depart.longitude,
      latitudeArrivee: arrivee.latitude,
      longitudeArrivee: arrivee.longitude,
    );
  }

  double? get distanceKm {
    final depart = _depart;
    final arrivee = _arrivee;
    if (depart == null || arrivee == null) return null;
    return DistanceUtils.distanceRouteEstimeeKm(
      latDepart: depart.latitude,
      lngDepart: depart.longitude,
      latArrivee: arrivee.latitude,
      lngArrivee: arrivee.longitude,
    );
  }

  void definirDepart(AdresseSuggestion adresse) {
    _depart = adresse;
    _recalculer();
  }

  void definirArrivee(AdresseSuggestion adresse) {
    _arrivee = adresse;
    _recalculer();
  }

  void oublierDepart() {
    if (_depart == null) return;
    _depart = null;
    _recalculer();
  }

  void oublierArrivee() {
    if (_arrivee == null) return;
    _arrivee = null;
    _recalculer();
  }

  Future<void> reessayer() => _recalculer();

  Future<void> _recalculer() async {
    final demande = ++_demande;
    _estimation = null;
    _erreur = null;
    _calcul = false;

    final distance = distanceKm;
    if (distance == null) {
      _notifier();
      return;
    }
    if (distance < distanceMinimaleKm) {
      _erreur = "L'adresse de départ et l'adresse d'arrivée sont identiques.";
      _notifier();
      return;
    }

    _calcul = true;
    _notifier();
    EstimationPrix? estimation;
    String? erreur;
    try {
      estimation = await _pricingRepository.estimer(type: type, distanceKm: distance, trajet: trajet);
      if (estimation.prixFcfa <= 0) {
        estimation = null;
        erreur = 'Le prix de ce trajet n\'a pas pu être calculé.';
      }
    } on ApiException catch (e) {
      erreur = e.message;
    } catch (_) {
      erreur = 'Le prix de ce trajet n\'a pas pu être calculé. Vérifiez votre connexion.';
    }
    if (demande != _demande) return;
    _estimation = estimation;
    _erreur = erreur;
    _calcul = false;
    _notifier();
  }

  void _notifier() {
    if (!_ferme) notifyListeners();
  }

  @override
  void dispose() {
    _ferme = true;
    super.dispose();
  }
}
