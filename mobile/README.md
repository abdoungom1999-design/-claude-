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

Écrans migrés : Bienvenue/Connexion, Accueil, Compte et portefeuille,
Activité et Messages, Chauffeur (dont dossier KYC et écrans d'attente/blocage),
Admin, Centre d'aide, sous-pages du Compte, commande et support.

## Support

« Contacter le support » ouvre un fil de demande d'aide (ticket `aide_<uid>`, collection
`tickets`) pour un client ou un chauffeur, traité dans l'onglet Support de l'Admin. Un
chauffeur suspendu ou banni reste connecté sur son écran de blocage pour y écrire. L'Admin désactive le flou
(`EcranOnyxVert(flou: false)`) pour rester fluide sur les longs tableaux ;
le rouge reste réservé aux alertes critiques.
