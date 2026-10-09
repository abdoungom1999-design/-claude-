import 'package:flutter/material.dart';
import '../../../core/location/localiser.dart';
import '../../../core/maps/geocoding_service.dart';
import '../../courses/data/depart_gps.dart';
import '../../courses/data/estimation_course_controller.dart';
import 'widgets/depart_gps_etat.dart';

/// Départ pris sur le GPS du client pour un écran de commande (course moto ou
/// colis) : à l'ouverture, prend la position de l'appareil et en fait le départ
/// (« Ma position actuelle », voir [DepartGps]) ; le client peut ensuite choisir
/// une autre adresse, retoucher le texte, ou reprendre sa position.
///
/// Ne touche à rien de ce que le client a choisi lui-même : une position qui
/// arrive après qu'il a commencé à saisir ou choisi une adresse est ignorée.
class DepartGpsController extends ChangeNotifier {
  DepartGpsController({required this.estimation, required this.texte, Localiser? localiser})
      : _localiser = localiser ?? localiserAppareil;

  /// Estimation du trajet, dont le départ est mis à jour.
  final EstimationCourseController estimation;

  /// Champ de texte du départ.
  final TextEditingController texte;
  final Localiser _localiser;

  EtatDepartGps _etat = EtatDepartGps.recherche;
  EtatDepartGps get etat => _etat;

  /// Numéro de la dernière recherche de position : une réponse arrivée en
  /// retard, ou après que le client a choisi lui-même son départ, est ignorée.
  int _recherche = 0;

  /// Change quand le texte du départ est remplacé de l'extérieur : le champ est
  /// alors reconstruit, ses suggestions de saisie disparaissent.
  int _versionChamp = 0;
  int get versionChamp => _versionChamp;

  bool _ferme = false;

  /// Prend la position GPS du client et en fait le départ. À appeler à
  /// l'ouverture de l'écran, puis par « Utiliser ma position actuelle ».
  Future<void> chercherPosition() async {
    final recherche = ++_recherche;
    if (_etat != EtatDepartGps.recherche) {
      _etat = EtatDepartGps.recherche;
      _versionChamp++;
      notifyListeners();
    }
    final position = await _localiser(demander: true);
    if (_ferme || recherche != _recherche) return;
    if (position == null) {
      _etat = EtatDepartGps.indisponible;
      notifyListeners();
      return;
    }
    final depart = DepartGps.depuis(position);
    texte.text = depart.libelle;
    estimation.definirDepart(depart);
    _etat = EtatDepartGps.actif;
    notifyListeners();
  }

  /// Le client a choisi une adresse dans la liste : elle remplace le GPS.
  void departChoisi(AdresseSuggestion adresse) {
    _recherche++;
    estimation.definirDepart(adresse);
    _etat = EtatDepartGps.manuel;
    notifyListeners();
  }

  /// Le client retouche le texte du départ : le point enregistré ne correspond
  /// plus, il doit choisir une adresse (ou reprendre le GPS).
  void departModifie() {
    _recherche++;
    estimation.oublierDepart();
    if (_etat == EtatDepartGps.manuel) return;
    _etat = EtatDepartGps.manuel;
    notifyListeners();
  }

  /// Toucher le champ quand il porte « Ma position actuelle » sélectionne tout
  /// le texte : la première lettre tapée le remplace.
  void departTouche() {
    if (_etat != EtatDepartGps.actif) return;
    texte.selection = TextSelection(baseOffset: 0, extentOffset: texte.text.length);
  }

  @override
  void dispose() {
    _ferme = true;
    super.dispose();
  }
}
