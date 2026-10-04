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

## Charte « Onyx & Light »

Fonds clairs, texte Onyx, cartes en verre dépoli. Duo de couleurs : **Bleu de Confiance**
(`AppColors.bleu`, #1E40AF) pour les accents (icônes, pastilles, menus, états) et **orange vif**
(`AppColors.orange`) exclusivement pour les boutons d'action (Commander, Soumettre,
Contacter, Payer…). Un test (`palette_bleu_orange_test.dart`) liste les fichiers autorisés
à utiliser l'orange.
Briques dans `lib/core/widgets/onyx_light.dart` (`EcranOnyxLight`, `CarteVerre`,
`ThemeOnyxLight`) et jetons dans `AppColors`.

Écrans migrés : Bienvenue/Connexion, Accueil, Compte et portefeuille,
Activité et Messages, Chauffeur (dont dossier KYC et écrans d'attente/blocage),
Admin, Centre d'aide, sous-pages du Compte, commande et support.

## Support

« Contacter le support » ouvre un fil de demande d'aide (ticket `aide_<uid>`, collection
`tickets`) pour un client ou un chauffeur, traité dans l'onglet Support de l'Admin. Un
chauffeur suspendu ou banni reste connecté sur son écran de blocage pour y écrire. L'Admin désactive le flou
(`EcranOnyxLight(flou: false)`) pour rester fluide sur les longs tableaux ;
le rouge reste réservé aux alertes critiques.
