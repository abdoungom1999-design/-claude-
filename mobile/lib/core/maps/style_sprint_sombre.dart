/// Style « Sprint sombre » des images Google (Map Tiles API, paramètre
/// `styles` de `createSession`, même format que les cartes stylées Google
/// Maps), version « Onyx & Vert » : uniquement des gris très sombres (terre,
/// routes) et des gris moyens (noms de rues), sans le vert des parcs, le
/// jaune ou l'orange des grands axes ni le bleu de la mer ; commerces et
/// transports masqués, pour que les motos et le trajet verts ressortent.
/// Un test garde la palette sans couleur.
///
/// Si Google refusait ce style, [FondCarte] redemande une session sans
/// style avant de repasser sur OpenStreetMap : la carte ne reste jamais
/// vide à cause de lui.
const styleSprintSombre = <Map<String, Object>>[
  {
    'elementType': 'geometry',
    'stylers': [
      {'color': '#131316'},
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
      {'color': '#8f8f98'},
    ],
  },
  {
    'elementType': 'labels.text.stroke',
    'stylers': [
      {'color': '#0b0b0c'},
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
      {'color': '#18181b'},
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
      {'color': '#2b2b31'},
    ],
  },
  {
    'featureType': 'road',
    'elementType': 'geometry.stroke',
    'stylers': [
      {'color': '#19191d'},
    ],
  },
  {
    'featureType': 'road.highway',
    'elementType': 'geometry.fill',
    'stylers': [
      {'color': '#3b3b43'},
    ],
  },
  {
    'featureType': 'road.highway',
    'elementType': 'geometry.stroke',
    'stylers': [
      {'color': '#1f1f24'},
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
      {'color': '#08080a'},
    ],
  },
  {
    'featureType': 'water',
    'elementType': 'labels.text.fill',
    'stylers': [
      {'color': '#55555e'},
    ],
  },
  {
    'featureType': 'administrative',
    'elementType': 'geometry.stroke',
    'stylers': [
      {'color': '#34343b'},
    ],
  },
];
