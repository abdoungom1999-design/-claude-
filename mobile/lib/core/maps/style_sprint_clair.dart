/// Style « Sprint clair » des images Google (Map Tiles API, paramètre
/// `styles` de `createSession`, même format que les cartes stylées Google
/// Maps), version « Silver » de la charte Onyx & Light : uniquement des gris
/// et du blanc (plus de vert des parcs, de jaune/orange des grands axes ni de
/// bleu franc de la mer), commerces et transports masqués, pour que les
/// motos et le trajet ressortent. Un test garde la palette sans couleur.
///
/// Si Google refusait ce style, [FondCarte] redemande une session sans
/// style avant de repasser sur OpenStreetMap : la carte ne reste jamais
/// vide à cause de lui.
const styleSprintClair = <Map<String, Object>>[
  {
    'elementType': 'geometry',
    'stylers': [
      {'color': '#f1f2f4'},
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
      {'color': '#8a8d93'},
    ],
  },
  {
    'elementType': 'labels.text.stroke',
    'stylers': [
      {'color': '#f1f2f4'},
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
      {'color': '#e9ebee'},
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
      {'color': '#e2e4e8'},
    ],
  },
  {
    'featureType': 'road.highway',
    'elementType': 'geometry.fill',
    'stylers': [
      {'color': '#ffffff'},
    ],
  },
  {
    'featureType': 'road.highway',
    'elementType': 'geometry.stroke',
    'stylers': [
      {'color': '#d9dce1'},
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
      {'color': '#dde2e8'},
    ],
  },
  {
    'featureType': 'water',
    'elementType': 'labels.text.fill',
    'stylers': [
      {'color': '#9aa1ab'},
    ],
  },
  {
    'featureType': 'administrative',
    'elementType': 'geometry.stroke',
    'stylers': [
      {'color': '#d3d6db'},
    ],
  },
];
