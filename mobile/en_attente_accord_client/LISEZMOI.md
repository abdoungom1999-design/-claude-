# Modifications prêtes, en attente de l'accord du client

Ce dossier ne change rien à l'application : ce sont des fichiers « patch »
(modifications préparées et testées, non appliquées). Ils concernent des
fichiers **hors de la zone de design** (`securite/ZONES_DESIGN.md`) : ils ne
s'appliquent qu'après l'accord explicite du client, un paquet à la fois.
Une fois appliqué, un paquet est commité à part (sans `Lot-Design: oui`),
puis son fichier est supprimé d'ici ; le dossier disparaît avec le dernier.

Les trois paquets ont été appliqués ensemble sur la branche (commit
f874cbf) : `flutter analyze` sans alerte, 368 tests sur 368 réussis.
Appliquer : `git apply en_attente_accord_client/<paquet>.patch` depuis le
dossier `mobile/`.

| Paquet | Contenu | Pourquoi il faut l'accord |
|---|---|---|
| `B1-habillage-navigation-notifications-theme.patch` | `lib/app.dart` (thème sombre de l'app), `lib/core/navigation/home_shell_page.dart` (barre du bas du client, bouton central, feuille d'actions rapides), `lib/core/notifications/carte_notifications.dart` (carte de notifications) | Fichiers hors zone. Sans eux, la barre du bas du client est illisible (icônes Onyx sur fond sombre) et le test « aucun orange » échoue : la publication est bloquée tant que ce paquet n'est pas appliqué. Habillage seulement : aucune logique de navigation ni de notification n'est modifiée. |
| `B2-carte-sombre.patch` | Style de carte « Sprint sombre » (`lib/core/maps/style_sprint_sombre.dart`, remplace `style_sprint_clair.dart`), filtre sombre pour le secours OpenStreetMap, mentions de carte en sombre, outil et script de vérification Google, notice `GOOGLE_MAPS_SETUP.md`, test `fond_carte_test.dart` | `lib/core/maps/` et `tool/` sont hors zone. Sans ce paquet, la carte reste claire sur une app noire. À la publication, la CI fait valider le style par Google (avertissement s'il le refuse : la carte retombe alors sur le style Google standard). |
| `B3-orange-restant-android-hebergement.patch` | Couleur des notifications Android (`colors.xml`, orange vers vert), page de téléchargement Android et son icône (`hebergement/android/`), pages de redirection, test `splash_test.dart` | `android/…/values/` et `hebergement/` sont hors zone. Sans ce paquet, il reste de l'orange (notifications, page de téléchargement de l'APK). |

Rien de ce dossier n'est publié : les commits qui l'ont créé portent
`[skip ci]`.
