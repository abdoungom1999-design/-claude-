/// Clé API Google Maps (Maps JavaScript API, Places API, Geocoding API,
/// Directions API — voir `GOOGLE_MAPS_SETUP.md` pour la marche à suivre
/// exacte côté Google Cloud Console).
///
/// PLACEHOLDER tant que le Groupe Santine n'a pas créé de clé : voir la
/// même logique que [DefaultFirebaseOptions] (`firebase_options.dart`)
/// — [MapService] et [estConfigure] permettent au reste du code de
/// détecter l'absence de configuration et de dégrader proprement
/// plutôt que de planter, le temps que la clé soit fournie.
///
/// Remarque : contrairement à la clé Firebase, une clé Google Maps
/// DOIT être restreinte côté Google Cloud Console (référents HTTP pour
/// le Web, restriction par API) avant sa mise en production — voir le
/// guide. Ce n'est pas un secret à cacher absolument, mais une clé non
/// restreinte peut être utilisée par n'importe qui et consommer le
/// quota/la facturation du projet.
class GoogleMapsConfig {
  GoogleMapsConfig._();

  static const String _placeholder = 'A_REMPLACER';

  static const String apiKey = _placeholder;

  static bool get estConfigure => apiKey != _placeholder;
}
