/// Coordonnées de démonstration à Dakar, utilisées tant que l'intégration
/// cartographique réelle (géocodage d'adresse, GPS embarqué) n'est pas en
/// place. Cette phase connecte la plomberie réseau ; la carte reste un
/// placeholder (voir [MapPlaceholder]).
class DemoCoordinates {
  DemoCoordinates._();

  static const double plateauLatitude = 14.6928;
  static const double plateauLongitude = -17.4467;
  static const double almadiesLatitude = 14.7358;
  static const double almadiesLongitude = -17.5106;
}
