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
