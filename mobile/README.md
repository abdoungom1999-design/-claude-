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
« Position GPS du client » (lu par le chauffeur, l'Admin et les notifications). L'écran Colis n'est
pas concerné. Tests : `depart_gps_test.dart`.

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
Prochains lots : départ GPS sur l'écran Colis, puis coordonnées arrondies avant l'acceptation
(position exacte réservée au chauffeur qui accepte).

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
