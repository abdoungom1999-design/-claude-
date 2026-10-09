import 'package:latlong2/latlong.dart';
import '../../../core/maps/geocoding_service.dart';

/// Départ d'une course pris sur le GPS du client plutôt que saisi : le champ
/// de départ est pré-rempli par « Ma position actuelle » et les coordonnées
/// exactes de l'appareil sont enregistrées avec la course.
abstract final class DepartGps {
  /// Ce que le client lit dans le champ de départ.
  static const libelleClient = 'Ma position actuelle';

  /// Ce qui est enregistré sur la course. Le chauffeur, l'Admin et les
  /// notifications lisent le même texte : « ma position » n'y voudrait rien
  /// dire, c'est celle du client.
  static const libelleCourse = 'Position GPS du client';

  /// Départ pris sur le GPS, aux coordonnées exactes de l'appareil.
  static AdresseSuggestion depuis(LatLng position) => AdresseSuggestion(
        libelle: libelleClient,
        latitude: position.latitude,
        longitude: position.longitude,
        gps: true,
      );

  /// Texte de départ à enregistrer avec la course : [libelleCourse] pour un
  /// départ GPS, sinon l'adresse telle que le client l'a saisie.
  static String pourLaCourse(AdresseSuggestion depart, String texteSaisi) =>
      depart.gps ? libelleCourse : texteSaisi.trim();

  /// Départ tel que le client le lit (historique, suivi, notation, signalement) :
  /// « Ma position actuelle » pour un départ pris sur son GPS, l'adresse sinon.
  /// Le chauffeur, l'Admin et les notifications gardent [libelleCourse].
  static String pourLeClient(String adresseDepart) => adresseDepart == libelleCourse ? libelleClient : adresseDepart;
}
