# sprint

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Charte « Onyx & Vert »

Fonds noir Onyx et gris très sombres, texte clair, cartes en verre dépoli, dégradés et
halos verts. **Vert vibrant** (`AppColors.vert`) pour tout ce qui agit : boutons d'action
(Commander, Payer, Contacter…) avec du texte Onyx dessus, icônes et onglets actifs,
contours de sélection. Plus aucun orange. Un test (`palette_onyx_vert_test.dart`) vérifie
les contrastes (WCAG), l'absence d'orange (noms et valeurs de couleur) et le texte Onyx
sur le vert.
Briques dans `lib/core/widgets/onyx_vert.dart` (`EcranOnyxVert`, `CarteVerre`,
`ThemeOnyxVert`) et `lib/core/widgets/barre_navigation.dart`; jetons dans `AppColors`,
thème sombre unique dans `AppTheme.sombre`.

En-tête de l'accueil client : `lib/features/home/presentation/entete_accueil.dart`
(marque « Sprint » et slogan `EnteteAccueil.slogan` à gauche, cloche et avatar à
l'initiale du prénom à droite, icône de profil si le profil n'a pas de nom).

Écrans migrés : Bienvenue/Connexion, Accueil, Compte et portefeuille,
Activité et Messages, Chauffeur (dont dossier KYC et écrans d'attente/blocage),
Admin, Centre d'aide, sous-pages du Compte, commande et support.

## Session conservée

Un compte connecté le reste jusqu'à un appui sur « Se déconnecter » (téléphone, navigateur,
application installée sur l'écran d'accueil). À l'ouverture,
`lib/core/router/aiguillage_demarrage.dart` attend que Firebase ait relu la session, puis envoie
le compte de l'écran de Bienvenue vers son accueil : `/accueil` (client), `/conducteur`
(chauffeur) ou `/admin` (administrateur). Le rôle du compte est retenu sur l'appareil
(`lib/features/auth/data/role_du_compte.dart`, stockage sécurisé) à chaque connexion et oublié à
la déconnexion : l'arrivée n'attend pas le réseau. Ce rôle ne donne aucun droit, il choisit
seulement l'écran d'arrivée. Sans session, ou en mode démo (Firebase non configuré), l'écran de
Bienvenue s'affiche comme avant. Tests : `aiguillage_demarrage_test.dart`,
`role_du_compte_test.dart`.

## Commande par GPS et guidage du chauffeur

**Départ automatique** : à l'ouverture de « Réserver une course »
(`lib/features/client/presentation/passager_page.dart`), l'écran demande la position GPS du client
(`localiserAppareil`, avec la demande d'autorisation) et pré-remplit le départ par « Ma position
actuelle » (`lib/features/courses/data/depart_gps.dart`) : les coordonnées exactes de l'appareil sont
enregistrées avec la course. Le client n'a plus qu'à choisir son arrivée ; il peut retoucher le
départ à la main ou reprendre sa position (« Utiliser ma position actuelle »). Position introuvable
(GPS coupé, autorisation refusée) : message et « Réessayer ». La course enregistre le libellé
« Position GPS du client » (lu par le chauffeur, l'Admin et les notifications). L'écran Colis
fonctionne de la même façon (« Adresse de retrait » pré-remplie, message adapté) : le contrôleur
`DepartGpsController` et le champ `ChampDepartGps` (`lib/features/client/presentation/`) sont
partagés par les deux écrans. Tests : `depart_gps_test.dart`, `depart_gps_controller_test.dart`,
`depart_gps_colis_test.dart`.

**Guidage du chauffeur** : dès qu'il accepte, l'Accueil du chauffeur devient un écran de guidage
(`widgets/guidage_course.dart`, `data/guidage_controller.dart`) : repère du client au point GPS
exact, position du chauffeur, itinéraire, distance et temps d'approche (22 km/h, comme l'attente
affichée au client). Une fois le client à bord, le même écran guide vers la destination. L'itinéraire
vient de la Cloud Function `itineraireCourse` (Google Routes, clé sur le serveur, réservée au
chauffeur de la course) : un calcul à l'acceptation, un au changement de point visé, puis seulement
si le chauffeur quitte son itinéraire (plus de 120 m) ; le reste à parcourir se déduit de sa position
sur le tracé. Sans réponse du serveur : estimation à vol d'oiseau en pointillés, jamais de retour en
arrière sur un itinéraire déjà obtenu. La proposition de course affiche « À ~1,2 km de vous ».
Tests : `trace_utils_test.dart`, `guidage_controller_test.dart`, `guidage_course_test.dart`,
`itineraire_chauffeur_test.dart`, et côté serveur `functions/test/itineraire.emulateur.test.ts`.

**Libellé du départ** : la course enregistre « Position GPS du client », que lisent le chauffeur,
l'Admin et les notifications ; le client lit « Ma position actuelle » partout (historique, détail,
suivi, courses à noter, signalement, page de paiement simulée) grâce à
`CourseFirestore.adresseDepartPourLeClient`. La politique de confidentialité (mise à jour du
9 octobre 2026) mentionne le suivi technique des erreurs et la position GPS transmise au chauffeur.
**Position exacte réservée au chauffeur qui accepte** : tant qu'une course attend un chauffeur, tous
les chauffeurs actifs la lisent ; son départ n'y figure donc qu'au centre d'une case d'environ 150 m
(même arrondi que les motos montrées au client, `arrondirPosition` dans `functions/src/proximite.ts`),
avec `departArrondi: true`. La position exacte est écrite par le serveur, dans la même transaction que la
course, sous `courses/{id}/prive/depart` (`functions/src/paiements.ts`) ; les règles Firestore ne la
donnent qu'au client, au chauffeur de la course tant qu'elle est acceptée ou en cours, et à l'Admin.
L'app la lit à part (`CourseService.streamDepartExact`) et complète la course avec
`completerDepartExact` (`lib/features/courses/data/depart_exact.dart`) : côté chauffeur (guidage,
navigation) et côté client (carte de recherche, suivi d'approche). En attendant la position exacte, le
guidage montre la zone du client (cercle) sans itinéraire ; `itineraireCourse` lit lui-même le document
privé. L'arrivée reste exacte. Tests : `depart_exact_test.dart`, `suivi_depart_exact_test.dart`,
`guidage_controller_test.dart`, `guidage_course_test.dart`, règles Firestore
(`firestore_rules_test`), `functions/test/paiements.emulateur.test.ts` et `itineraire.emulateur.test.ts`.
Limites connues : l'adresse écrite par le client et son `clientId` restent visibles des chauffeurs
avant l'acceptation ; une course créée avant ce masquage garde sa position exacte dans le document ; le
document privé d'une course supprimée par l'Admin n'est pas supprimé avec elle.

Mise en ligne le 9 octobre 2026 (run #102), avec l'écran Colis par GPS et la correction du contrôle des
secrets de l'APK (`securite/garde_fuites.mjs apk`). Après la mise en ligne, l'app installée doit être
rouverte (PWA) et l'APK réinstallé : une ancienne version ne lit pas la position exacte et montrerait au
chauffeur la zone au lieu du point.

## Suivi des plantages et sauvegardes

**Plantages** : les erreurs imprévues de l'APK Android partent vers Firebase Crashlytics
(`lib/core/suivi/suivi_plantages.dart`, branché dans `main.dart`, actif seulement en version
finale). Le web, donc l'app installée sur l'iPhone, n'est pas couvert (Crashlytics n'existe
pas pour le web). Carte « Suivi des plantages » avec le bouton « Tester le suivi » dans
Admin > Paramètres, sur l'APK. La règle R8 `android/app/proguard-rules.pro` est
indispensable (sans elle l'APK démarre sans écran) ; avant de publier une mise à jour qui
touche à Firebase, à Gradle ou à R8, lancer l'essai sur émulateur (Actions > Essai Android).

**Sauvegardes** : la base Firestore est sauvegardée par Google chaque jour (14 jours) et chaque
semaine (14 semaines) ; le flux « Sauvegardes Firestore » les met en place et vérifie chaque
jour qu'une sauvegarde récente existe (`securite/sauvegardes.mjs`).

Détails, restauration et choix techniques : `FIREBASE_SETUP.md`, sections 10 et 11.

## Support

« Contacter le support » ouvre un fil de demande d'aide (ticket `aide_<uid>`, collection
`tickets`) pour un client ou un chauffeur, traité dans l'onglet Support de l'Admin. Un
chauffeur suspendu ou banni reste connecté sur son écran de blocage pour y écrire. L'Admin désactive le flou
(`EcranOnyxVert(flou: false)`) pour rester fluide sur les longs tableaux ;
le rouge reste réservé aux alertes critiques.
