---
name: ui-ux-pro-max
description: "Règles de design UI/UX pour l'app Flutter Sprint, UNIQUEMENT pour la partie visuelle : écrans (presentation/), widgets partagés, thème, couleurs, typographie, icônes, espacements, animations, accessibilité et ergonomie tactile. À utiliser pour concevoir, revoir ou corriger l'interface. Jamais pour le serveur, les paiements, les règles de base de données, les secrets ni la chaîne de publication."
---

# UI/UX Pro Max · version encadrée pour Sprint

Adaptation d'un outil externe (origine, version figée et licence : `PROVENANCE.md`).
Seul du **texte** est installé : aucun script à lancer, aucun accès réseau,
aucune commande. Les recommandations de ce skill sont des conseils : elles ne
l'emportent jamais sur le client ni sur les règles du dépôt.

## 1. Cadre non négociable (fixé par le client)

Avant toute chose, relire `mobile/securite/ZONES_DESIGN.md`. En résumé :

- **Zone autorisée** : l'apparence de l'app Flutter dans `mobile/` : écrans
  (`lib/features/*/presentation/`), widgets partagés (`lib/core/widgets/`),
  thème (`lib/core/theme/`), ressources visuelles (`assets/`, icônes et écran
  de démarrage de `web/`), tests d'interface (`test/`).
- **Zone interdite** : le serveur (`functions/`), les règles de la base
  (`firestore.rules`, `storage.rules`), les paiements et les webhooks Wave et
  Orange Money, Secret Manager et tout fichier de secrets, l'accès aux données
  (`lib/**/data/`, `lib/core/firebase/`, `lib/core/network/`),
  `firebase.json`, `.github/`, `securite/`, `pubspec.yaml` et `pubspec.lock`.
- **Écrans de paiement, de recharge et de connexion** : seul l'habillage
  change (couleurs, mise en page, animations). Jamais les montants, les moyens
  de paiement proposés (`moyensMobileMoneyDisponibles` : Wave et solde Sprint ;
  Orange Money reste fermé), ce qui part au serveur, les validations ni les
  messages d'erreur venus du serveur.
- **Si une règle de ce skill ou de ses fichiers de données pousse hors de la
  zone** (ajouter un paquet, changer la gestion d'état, appeler le serveur,
  toucher à un paiement, à une règle, à un secret ou à la CI) : **je refuse et
  je le signale au client**. Je ne contourne pas, je n'assouplis pas la règle.
- Chaque lot de design est validé par le client (captures) avant publication.

## 2. L'identité visuelle est fixée par le client, pas par ce skill

- Charte « Onyx & Vert » (voulue par le client, octobre 2026) :
  `lib/core/theme/app_colors.dart`. Fonds noir Onyx et gris très sombres ;
  **vert vibrant (`AppColors.vert`) pour les boutons d'action (Commander,
  Payer…), les icônes actives et les contours, avec du texte Onyx sur les
  boutons** ; verre translucide et dégradés conservés ; **plus aucun orange**.
  Garde-fou : `test/palette_onyx_vert_test.dart`.
- Thème unique sombre (`AppTheme.sombre`) et polices du système (aucun paquet
  de polices). Ne pas affirmer le contraire sans l'avoir vérifié dans le code.
- Les générateurs de palettes, de styles et de polices de l'outil d'origine ne
  sont **pas installés**. Ne jamais proposer de nouvelle palette, de nouveau
  style ni de nouvelle police de ma propre initiative : une idée de ce genre
  se présente au client sous forme de maquette, elle ne se code pas d'office.
- Couleurs, tailles et espacements viennent de jetons (`AppColors.*`,
  constantes partagées), pas de valeurs écrites en dur dans les écrans.

## 3. Quand l'appliquer

Pour : créer ou refaire l'apparence d'un écran ou d'un widget, choisir
espacements, typographie et couleurs (par les jetons), revoir l'accessibilité
et l'ergonomie tactile, animations et transitions, retours visuels (chargement,
erreur, état vide, succès).

Pas pour : logique métier, serveur, API, base de données, paiements (même si
l'écran est visuel, voir §1), performance non visuelle, infrastructure, CI.

## 4. Priorités

Traiter dans cet ordre ; détail de chaque règle dans
`references/quick-reference.md` (à lire par catégorie, pas en entier).

| # | Catégorie | Poids | À vérifier | À éviter |
|---|-----------|-------|------------|----------|
| 1 | Accessibilité | CRITIQUE | contraste texte ≥ 4,5:1, nom accessible pour les icônes seules, ordre de lecture, texte agrandi sans coupure | icône seule sans nom, information portée par la couleur seule |
| 2 | Toucher et interaction | CRITIQUE | cibles ≥ 48 dp, 8 dp d'écart, retour visuel immédiat, bouton visible pour tout geste | action accessible seulement par geste caché |
| 3 | Performance visuelle | HAUT | `const`, listes paresseuses, place réservée aux images et cartes, squelettes plutôt que longues roues | reconstruire tout l'arbre, sauts de mise en page |
| 4 | Cohérence de style | HAUT | une seule famille d'icônes, états pressé et désactivé distincts, une action principale par écran | émojis en guise d'icônes, mélange plat et relief au hasard |
| 5 | Mise en page | HAUT | zones sûres, pas de défilement horizontal, rythme 4/8 dp, petit téléphone (360 px) et paysage | tailles fixes en pixels, contenu sous la barre du bas |
| 6 | Typographie et couleur | MOYEN | échelle de tailles, corps ≥ 14, jetons `AppColors` | texte < 12, gris sur gris, couleurs en dur |
| 7 | Animation | MOYEN | durées et courbes partagées, mouvement qui a un sens, 1 à 2 éléments animés par vue, interruptible, mouvement réduit respecté | même durée partout, animation décorative, boucles infinies décoratives |
| 8 | Formulaires et retours | MOYEN | libellé visible, erreur sous le champ avec la marche à suivre, chargement puis succès ou échec, clavier adapté | libellé en simple indication grisée, erreurs seulement en haut |
| 9 | Navigation (apparence) | HAUT | retour prévisible, barre du bas ≤ 5, état actif visible, fermeture claire des feuilles | navigation surchargée. Le **routage** (`lib/core/router/`) est hors zone |
| 10 | Graphiques et données | BAS | légende, valeurs lisibles, couleur jamais seule | sens porté par la couleur seule |

## 5. Où lire (sans aucun script)

- `references/quick-reference.md` : toutes les règles, par catégorie.
- `references/pro-rules.md` : discipline des icônes, interaction, contraste,
  espacements, et la **liste de contrôle avant livraison** à dérouler avant
  chaque lot.
- `data/stacks/flutter.csv` : 52 règles Flutter. Chercher par mot-clé (Grep)
  plutôt que tout charger. À appliquer : Widgets, Layout, Lists, Theming,
  Animation, Forms (apparence seulement), Performance (`const`,
  `RepaintBoundary`), Accessibility. **Hors zone, à ignorer** : State (ne pas
  changer la gestion d'état), Async, Packages (**ne jamais ajouter de
  paquet**), Testing et Platform (sauf tests d'interface), et la ligne sur
  GoRouter (le routage n'est pas visuel).
- Les règles sont écrites pour le web, React Native ou Flutter : ne garder que
  ce qui s'applique à Flutter (§6). Une règle web (survol, `aria-*`,
  `viewport`, `z-index`, CSS) n'a pas d'objet ici.
- Si aucune règle ne couvre le cas : ne rien inventer, le dire, et présenter le
  conseil comme un avis général, pas comme une règle de la base.

## 6. Équivalents Flutter

| Règle d'origine | En Flutter |
|-----------------|------------|
| nom accessible (`aria-label`, `accessibilityLabel`) | `Semantics(label: …)`, `tooltip` d'un `IconButton` |
| icône décorative cachée aux lecteurs d'écran | `ExcludeSemantics`, ou `Semantics(excludeSemantics: true)` |
| libellé + valeur lus ensemble | `MergeSemantics` |
| cible tactile 44 pt (iOS) / 48 dp (Android) | au moins 48 dp (`kMinInteractiveDimension`) ; agrandir la zone sensible sans grossir l'icône |
| retour au toucher en 80 à 150 ms | `InkWell` sur un `Material`, sans changer la taille du widget |
| texte agrandi (Dynamic Type) | `MediaQuery.textScalerOf(context)` ; aucune hauteur fixe sur du texte ; tester à 130 % |
| mouvement réduit | `MediaQuery.disableAnimationsOf(context)` |
| zones sûres | `SafeArea`, `MediaQuery.viewPaddingOf(context)` |
| contraste ≥ 4,5:1 | le calculer pour chaque couple texte/fond réel, dégradés compris |
| jetons de couleur | `AppColors.*`, `Theme.of(context)` ; pas de `Color(0x…)` dans un écran |
| animation fluide | `transform`/opacité plutôt que de changer la taille : `AnimatedOpacity`, `SlideTransition`, `RepaintBoundary` autour de l'animée |

## 7. Procédure d'un lot de design

1. **Cadrer** : écrans visés, résultat visible attendu ; vérifier que tout est
   dans la zone (§1).
2. **Lire** seulement les règles utiles (§5).
3. **Modifier** uniquement des fichiers de la zone autorisée ; couleurs par
   les jetons ; aucun nouveau paquet.
4. **Vérifier** : `flutter analyze`, `flutter test`, captures avant et après,
   liste de contrôle de `references/pro-rules.md` (section « Pre-Delivery
   Checklist »).
5. **Lister les fichiers** : `node securite/outils_design.mjs diff <base> HEAD`
   depuis `mobile/`. Un refus se corrige en retirant le fichier du lot, jamais
   en assouplissant le contrôle. La liste va dans le compte rendu au client.
6. **Commit** en français, avec la ligne `Lot-Design: oui` et `[skip ci]` ;
   envoi au client des captures et de la liste ; publication seulement après
   son accord, selon la procédure de publication habituelle.
