import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Position de l'appareil : `demander` à `false` n'affiche jamais de
/// demande d'autorisation (on ne localise que si elle est déjà donnée).
typedef Localiser = Future<LatLng?> Function({required bool demander});

/// Localise l'appareil, ou renvoie `null` (service coupé, autorisation
/// refusée ou absente, délai dépassé). Jamais d'exception.
Future<LatLng?> localiserAppareil({required bool demander}) async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && demander) {
      permission = await Geolocator.requestPermission();
    }
    if (permission != LocationPermission.whileInUse && permission != LocationPermission.always) return null;
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    ).timeout(const Duration(seconds: 12));
    return LatLng(p.latitude, p.longitude);
  } catch (_) {
    return null;
  }
}
