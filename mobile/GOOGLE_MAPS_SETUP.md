> **Mise à jour :**
> - Recherche d'adresses (Places API New) et distance par la route
>   (Routes API) : via les Cloud Functions, clé serveur dans Secret
>   Manager (`GOOGLE_MAPS_API_KEY`, voir FIREBASE_SETUP.md, étape 7).
> - Fond de carte : images Google (**Map Tiles API**) dans les cartes de
>   l'app (`lib/core/maps/fond_carte.dart`), avec une clé web distincte
>   (`sprint-carte-web`, restreinte au site
>   `https://sprint-vtc.web.app/*` et à Map Tiles API),
>   fournie à la compilation par le secret GitHub `GOOGLE_MAPS_WEB_KEY`.
>   Sans cette clé, ou si Google ne répond pas, la carte reste sur
>   OpenStreetMap. Les mentions Google sont affichées sur chaque carte.
> - Style « Sprint sombre » (`lib/core/maps/style_sprint_sombre.dart`) :
>   envoyé à la création de la session Map Tiles (terre et routes en gris
>   très sombres, noms de rues en gris clair, commerces et transports
>   masqués). Style refusé par Google : carte Google sans style (claire et
>   colorée) ; Google indisponible : OpenStreetMap passé en gris très
>   sombres dans le même esprit.
> - APK Android : clé dédiée `sprint-carte-android` (secret GitHub
>   `GOOGLE_MAPS_ANDROID_KEY`), restreinte à l'app Android
>   (`sn.groupesantine.sprint`, SHA-1
>   `6D:6B:BA:F8:1D:D1:B7:3B:DB:47:10:2F:B0:05:31:F5:25:9A:41:92`) et à
>   Map Tiles API. L'app joint son identité (en-têtes `X-Android-Package`
>   et `X-Android-Cert`) à chaque appel. La CI vérifie que cette empreinte
>   est bien celle du certificat de l'APK.
> - Vérification réelle à chaque déploiement : la CI ouvre une session
>   Google avec chaque clé (site et APK) et le style « Sprint sombre »
>   (`tool/verifier_session_carte.sh`). Un refus apparaît en
>   avertissement dans le résumé du run.
> - Le composant Google Maps officiel (Maps JavaScript API, décrit
>   ci-dessous) n'est pas utilisé.

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

### Plafonner les dépenses (configuré dans la console, pas dans le code)

Un budget Google **n'arrête rien** : il alerte seulement, et ses chiffres
arrivent avec du retard (de quelques heures à plus d'un jour). Dispositif
retenu pour le projet `sprint-vtc` :

- **A. Alertes e-mail** : Facturation > Budgets et alertes > Créer un budget,
  périmètre = projet `sprint-vtc`, montant **15 €**, seuils **50 %** (7,50 €),
  **67 %** (≈ 10 €) et **100 %** (15 €) en « Réel ». Vérifier que l'e-mail du
  propriétaire est administrateur du compte de facturation (Gestion des
  comptes).
- **B. Quotas stricts sur les API Maps** : API et services > API activées >
  (Places API (New), Routes API, Map Tiles API) > onglet **Quotas et limites
  système** > baisser les limites par jour. Au-delà, Google refuse les
  appels (la carte ou la recherche d'adresse tombe en panne) **sans
  dépense**, et le reste de l'app continue de fonctionner.
- **C. Coupure automatique de la facturation (Pub/Sub + fonction)** :
  **non retenue**. Elle arrêterait aussi les Cloud Functions (commandes,
  paiements, notifications, portefeuille) et peut se déclencher à tort.

Les libellés exacts de la console changent : en cas de différence, suivre
l'esprit de l'étape.

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
  HTTP)**, ajoute `https://sprint-vtc.web.app/*` (le domaine du site
  déployé, sur Firebase Hosting). Ajoute aussi `http://localhost:*` si tu
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
