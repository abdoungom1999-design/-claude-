# Configuration Google Maps Platform — projet Sprint

Ce dépôt est prêt pour Google Maps (package installé, `MapService`
écrit), mais **aucune clé API n'existe encore**. Tant que
`lib/core/config/google_maps_config.dart` contient sa valeur
placeholder, rien n'appelle Google — pas de risque de facturation
inattendue, et rien ne casse en attendant.

## 1. Créer (ou réutiliser) un projet Google Cloud

1. Va sur <https://console.cloud.google.com>.
2. Si le Groupe Santine a déjà un projet Firebase ("Sprint VTC"), **il
   existe déjà en tant que projet Google Cloud du même nom** — pas
   besoin d'en recréer un, ouvre-le directement dans la liste des
   projets (menu déroulant en haut).
3. Sinon : **Créer un projet** → nom `Sprint VTC` → Créer.

## 2. Activer la facturation (obligatoire, même pour rester dans le free tier)

Google exige un compte de facturation actif pour utiliser Maps
Platform, même si l'usage réel reste gratuit.

1. Menu ☰ → **Facturation**.
2. **Associer un compte de facturation** (ou en créer un : carte
   bancaire requise, mais rien n'est prélevé tant que le crédit
   gratuit mensuel n'est pas dépassé).
3. Google offre un crédit gratuit récurrent chaque mois qui couvre
   largement un usage de démo/lancement (plusieurs dizaines de
   milliers d'appels Geocoding/Places/Directions). Tu peux définir une
   **alerte de budget** (Facturation > Budgets et alertes) pour être
   prévenu avant tout dépassement — recommandé dès le départ.

## 3. Activer les 4 API nécessaires

Menu ☰ → **API et services** → **Bibliothèque**, puis recherche et
active chacune de ces 4 API (bouton **Activer** sur chaque page) :

1. **Maps JavaScript API** — affiche la carte interactive elle-même
   (utilisée par `google_maps_flutter` sur le Web).
2. **Places API** — recherche et autocomplétion d'adresses.
3. **Geocoding API** — convertit une adresse en coordonnées GPS, et
   inversement (coordonnées → adresse lisible).
4. **Directions API** — calcule un itinéraire réel (réseau routier),
   la distance et la durée du trajet.

## 4. Créer la clé API

1. Menu ☰ → **API et services** → **Identifiants**.
2. **Créer des identifiants** → **Clé API**. Google génère une clé
   immédiatement.
3. **Copie cette clé et envoie-la moi ici dans la conversation.**

## 5. Restreindre la clé (important, à faire dès sa création)

Contrairement à la clé Firebase, une clé Google Maps non restreinte
peut être réutilisée par n'importe qui pour consommer ton quota. Sur
la page de la clé (clique dessus dans la liste des identifiants) :

- **Restrictions d'application** : choisis **Sites Web (référents
  HTTP)**, ajoute `https://abdoungom1999-design.github.io/*` (le
  domaine du site déployé). Ajoute aussi `http://localhost:*` si tu
  comptes tester en local plus tard.
- **Restrictions d'API** : choisis **Restreindre la clé**, coche
  uniquement les 4 API activées à l'étape 3.
- Enregistre.

## Une fois que tu m'auras donné la clé

Je la colle dans `lib/core/config/google_maps_config.dart` (et dans le
script Maps JavaScript de `web/index.html`), je valide que tout
compile, je pousse. Contrairement à Firebase, **avoir une clé
configurée ne suffit pas à faire apparaître la vraie carte partout** :
il faudra ensuite, dans une étape séparée, remplacer les cartes
actuelles (OpenStreetMap via `flutter_map`, déjà fonctionnelles) par
un vrai widget `GoogleMap` écran par écran, et brancher les champs de
recherche d'adresse sur `MapService` à la place de l'actuel
`GeocodingService` (Nominatim). Je te proposerai cette étape une fois
la clé en place et testée.

## Ce qui est préparé mais pas encore branché

- `MapService` (`lib/core/maps/map_service.dart`) : recherche
  d'adresse, géocodage direct/inverse, calcul d'itinéraire réel
  (distance, durée, tracé). Prêt à l'emploi, mais aucun écran ne
  l'appelle encore — la recherche d'adresse (Passager/Colis) utilise
  toujours `GeocodingService` (Nominatim/OSM) et l'estimation de
  distance à vol d'oiseau (`DistanceUtils`), exactement comme
  aujourd'hui.
- `AdaptiveMap` (`lib/core/widgets/adaptive_map.dart`) : le widget
  carte lui-même est en revanche déjà "Google Maps-ready". Il affiche
  un vrai `GoogleMap` dès que `GoogleMapsConfig.estConfigure` devient
  vrai, et bascule sinon sur `flutter_map`/OpenStreetMap (comme avant).
  `TripMap` (recherche de trajet Passager/Colis) et le fond de carte de
  l'Accueil Conducteur s'appuient dessus : **aucun de ces écrans n'a
  besoin d'être modifié** le jour où la clé sera fournie, ils
  basculeront seuls. Volontairement PAS branché sur la carte Admin
  "Courses en direct" (hors périmètre de cette préparation).
- Le script Google Maps JavaScript dans `web/index.html` est en place
  mais avec une clé placeholder — un vrai widget `GoogleMap` étant
  désormais affiché avec cette clé placeholder (voir ci-dessus), il
  est possible que Google affiche un filigrane "For development
  purposes only" ou un message d'erreur dans la zone de la carte tant
  qu'aucune vraie clé n'est configurée ; le reste de l'app n'est pas
  affecté (dégradation gracieuse, jamais un plantage).
