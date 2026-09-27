import 'package:url_launcher/url_launcher.dart';

/// Applications de guidage proposées au chauffeur.
enum AppNavigation { googleMaps, waze }

/// Liens universels vers Google Maps et Waze : ils ouvrent l'application
/// installée sur le téléphone (Android comme iPhone), sinon le site web.
/// Plus fiables depuis une application web que les schémas `waze://`
/// ou `comgooglemaps://`, que certains navigateurs bloquent.
abstract final class NavigationGps {
  /// Itinéraire vers des coordonnées GPS, ou vers une adresse texte
  /// quand la course n'a pas de coordonnées (courses anciennes).
  static Uri lien(AppNavigation app, {double? latitude, double? longitude, String? adresse}) {
    final aDesCoordonnees = latitude != null && longitude != null;
    final coordonnees = aDesCoordonnees ? '$latitude,$longitude' : null;
    return switch (app) {
      AppNavigation.googleMaps => Uri.https('www.google.com', '/maps/dir/', {
          'api': '1',
          'destination': coordonnees ?? adresse ?? '',
          'travelmode': 'driving',
        }),
      AppNavigation.waze => Uri.https('waze.com', '/ul', {
          if (coordonnees != null) 'll': coordonnees else 'q': adresse ?? '',
          'navigate': 'yes',
        }),
    };
  }

  static Future<bool> ouvrir(Uri lien) => launchUrl(lien, mode: LaunchMode.externalApplication);
}
