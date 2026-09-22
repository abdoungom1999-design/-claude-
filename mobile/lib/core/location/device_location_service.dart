import 'package:geolocator/geolocator.dart';

/// Accès à la position GPS réelle de l'appareil. Nécessite les
/// permissions natives Android/iOS — voir la checklist de configuration
/// fournie avec cette intégration (fichiers de plateforme non générés
/// dans ce dépôt, `flutter create .` à lancer au préalable).
class DeviceLocationService {
  Future<bool> permissionAccordee() async {
    final serviceActif = await Geolocator.isLocationServiceEnabled();
    if (!serviceActif) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  Future<Position> positionActuelle() {
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }
}
