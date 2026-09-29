import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'proximite_service.dart';

/// Motos disponibles autour d'un point, tenues à jour tant que l'écran
/// qui les affiche est visible. Partagé par l'accueil et les écrans de
/// commande : mêmes règles d'anonymat (positions arrondies à ~150 m par
/// le serveur, aucune identité).
///
/// Un réseau coupé ou une erreur serveur ne vide jamais la carte : les
/// dernières motos connues restent affichées.
class MotosProchesController extends ChangeNotifier {
  MotosProchesController({
    ProximiteService? service,
    this.rafraichissement = const Duration(seconds: 20),
    bool Function()? actif,
  })  : _service = service ?? ProximiteService.parDefaut(),
        _actif = actif ?? (() => true) {
    _minuteur = Timer.periodic(rafraichissement, (_) => rafraichir());
  }

  final ProximiteService _service;
  final Duration rafraichissement;

  /// Écran visible ? (une carte masquée par un autre écran ne rappelle
  /// pas le serveur pour rien.)
  final bool Function() _actif;

  Timer? _minuteur;
  bool _ferme = false;

  Proximite _proximite = Proximite.vide;
  bool _chargement = true;
  LatLng? _centre;

  Proximite get proximite => _proximite;
  List<MotoProche> get motos => _proximite.motos;
  bool get chargement => _chargement;

  /// Point autour duquel les motos sont cherchées (`null` : pas encore).
  LatLng? get centre => _centre;

  /// Cherche les motos autour de [point] (et y reste centré pour les
  /// rafraîchissements suivants).
  Future<void> chercherAutour(LatLng point) {
    _centre = point;
    return _charger(point);
  }

  /// Rappelle le serveur autour du dernier point, si l'écran est visible.
  Future<void> rafraichir() {
    final point = _centre;
    if (point == null || !_actif()) return Future.value();
    return _charger(point);
  }

  Future<void> _charger(LatLng point) async {
    try {
      final resultat = await _service.chauffeursProches(point);
      // Réponse arrivée après un changement de point : on l'ignore.
      if (_ferme || point != _centre) return;
      _proximite = resultat;
    } catch (_) {
      // On garde les motos déjà affichées.
    } finally {
      if (!_ferme && point == _centre) {
        _chargement = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _ferme = true;
    _minuteur?.cancel();
    super.dispose();
  }
}
