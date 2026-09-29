/// Style « Sprint clair » des images Google (Map Tiles API, paramètre
/// `styles` de `createSession`, même format que les cartes stylées Google
/// Maps) : fonds très clairs, routes blanches, commerces et transports
/// masqués, pour que les motos et le trajet ressortent.
///
/// Si Google refusait ce style, [FondCarte] redemande une session sans
/// style avant de repasser sur OpenStreetMap : la carte ne reste jamais
/// vide à cause de lui.
const styleSprintClair = <Map<String, Object>>[
  {
    'elementType': 'geometry',
    'stylers': [
      {'color': '#f6f5f2'},
    ],
  },
  {
    'elementType': 'labels.icon',
    'stylers': [
      {'visibility': 'off'},
    ],
  },
  {
    'elementType': 'labels.text.fill',
    'stylers': [
      {'color': '#7c7c7c'},
    ],
  },
  {
    'elementType': 'labels.text.stroke',
    'stylers': [
      {'color': '#f6f5f2'},
    ],
  },
  {
    'featureType': 'poi',
    'stylers': [
      {'visibility': 'off'},
    ],
  },
  {
    'featureType': 'poi.park',
    'elementType': 'geometry',
    'stylers': [
      {'visibility': 'on'},
      {'color': '#e3eedc'},
    ],
  },
  {
    'featureType': 'transit',
    'stylers': [
      {'visibility': 'off'},
    ],
  },
  {
    'featureType': 'road',
    'elementType': 'geometry.fill',
    'stylers': [
      {'color': '#ffffff'},
    ],
  },
  {
    'featureType': 'road',
    'elementType': 'geometry.stroke',
    'stylers': [
      {'color': '#e7e4de'},
    ],
  },
  {
    'featureType': 'road.highway',
    'elementType': 'geometry.fill',
    'stylers': [
      {'color': '#fde9d7'},
    ],
  },
  {
    'featureType': 'road.highway',
    'elementType': 'geometry.stroke',
    'stylers': [
      {'color': '#f4d3b5'},
    ],
  },
  {
    'featureType': 'road.local',
    'elementType': 'labels',
    'stylers': [
      {'visibility': 'simplified'},
    ],
  },
  {
    'featureType': 'water',
    'elementType': 'geometry',
    'stylers': [
      {'color': '#cfe3ef'},
    ],
  },
  {
    'featureType': 'water',
    'elementType': 'labels.text.fill',
    'stylers': [
      {'color': '#8aa9bd'},
    ],
  },
  {
    'featureType': 'administrative',
    'elementType': 'geometry.stroke',
    'stylers': [
      {'color': '#dcd8d0'},
    ],
  },
];
