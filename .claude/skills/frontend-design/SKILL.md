---
name: frontend-design
description: "Direction de design et rédaction d'interface pour l'app Flutter Sprint, UNIQUEMENT pour le visuel et les textes affichés : démarche (plan, revue face au brief, réalisation, critique par captures), retenue, libellés, messages d'erreur et états vides en français. L'identité visuelle (Onyx & Vert) est fixée par le client. Jamais pour le serveur, les paiements, les règles de base de données, les secrets ni la chaîne de publication."
---

# Direction de design · version encadrée pour Sprint

Adaptation, écrite pour Sprint, de la compétence `frontend-design` d'Anthropic
(Apache-2.0 ; origine et version figée : `PROVENANCE.md`). Le texte d'origine,
en anglais et sans aucun changement, est dans
`references/frontend-design-amont.md` : il est écrit pour des pages web, ce
fichier-ci en retient ce qui sert une app Flutter dont l'identité est déjà
fixée. Seul du **texte** est installé : aucun script, aucune commande, aucun
accès réseau. Ses conseils ne l'emportent jamais sur le client ni sur les
règles du dépôt.

À utiliser avec `ui-ux-pro-max` (règles chiffrées : contraste, cibles
tactiles, états) ; celle-ci donne la démarche et le ton.

## 1. Cadre non négociable (fixé par le client)

Relire `mobile/securite/ZONES_DESIGN.md` avant tout lot. En résumé :

- **Zone autorisée** : l'apparence de l'app Flutter dans `mobile/` : écrans
  (`lib/features/*/presentation/`), widgets partagés (`lib/core/widgets/`),
  thème (`lib/core/theme/`), ressources visuelles (`assets/`, icônes et écran
  de démarrage de `web/`), tests d'interface (`test/`), et les textes affichés
  dans ces fichiers.
- **Zone interdite** : le serveur (`functions/`), les règles de la base,
  les paiements et les webhooks Wave et Orange Money, Secret Manager et tout
  fichier de secrets, l'accès aux données (`lib/**/data/`,
  `lib/core/firebase/`, `lib/core/network/`), `firebase.json`, `.github/`,
  `securite/`, `pubspec.yaml` et `pubspec.lock`.
- **Écrans de paiement, de recharge et de connexion** : seul l'habillage
  change. Jamais les montants, les moyens de paiement proposés
  (`moyensMobileMoneyDisponibles` : Wave et solde Sprint ; Orange Money reste
  fermé), ce qui part au serveur, les validations ni les messages d'erreur
  venus du serveur.
- **Si un conseil de ce skill pousse hors de la zone** (ajouter un paquet ou
  une police, toucher au serveur, à un paiement, à une règle, à un secret, à
  la CI) : **je refuse et je le signale au client**.
- Chaque lot de design est validé par le client (captures) avant publication.

## 2. Ce qui change par rapport à l'original : le brief est déjà écrit

L'original demande d'être « le directeur de création d'un studio », de
prendre un risque esthétique et d'inventer une identité distincte. Pour Sprint,
**l'identité est le brief du client, et elle l'emporte** (l'original le dit
lui-même : « the brief's own words always win »).

- Charte « Onyx & Vert » (`lib/core/theme/app_colors.dart`) : fonds Onyx et
  gris très sombres, **vert vibrant pour tout ce qui agit** (boutons d'action
  avec texte Onyx, icônes et onglets actifs, contours), verre et dégradés
  conservés, plus aucun orange ; garde-fou : `test/palette_onyx_vert_test.dart`.
  Onyx (#0B0B0C) est un choix du client, même si l'original range les « noirs
  teintés » parmi les réflexes de génération.
- Thème sombre unique et polices du système : aucune nouvelle police, aucun
  nouveau paquet (`pubspec.yaml` est en zone interdite).
- La « prise de risque » se limite à ce que le client a demandé. Une idée
  d'évolution de l'identité se présente sous forme de maquette et attend son
  choix : elle ne se code pas d'office.
- Ce qui est propre au web (page d'accueil « héros », sélecteurs CSS, chargement
  de page, familles de polices) n'a pas d'objet ici.

## 3. Ce qui reste utile

1. **Ancrer le design dans le sujet** : un VTC moto-taxi et de la livraison à
   Dakar ; trois publics (passager, chauffeur, administration). À garder en
   tête : usage en déplacement, d'une main, au soleil, sur réseau mobile.
2. **Deux temps avant de coder** : (a) un plan compact (couleurs = jetons
   existants, rôle de chaque taille de texte, mise en page en une phrase et un
   croquis en caractères, principes) ; (b) une revue de ce plan face au brief :
   toute partie qui ressemble à un réflexe plutôt qu'à un choix pour cet écran
   est révisée, en disant ce qui a changé et pourquoi. Ensuite seulement,
   réaliser.
3. **Retenue** : dépenser l'audace à un seul endroit ; l'élément mémorable
   d'un écran est unique, tout le reste reste calme et discipliné ; retirer
   toute décoration qui ne sert pas le contenu.
4. **Mouvement sobre** : une animation qui répond à un geste (ouverture,
   dépliage, confirmation) et montre ce qui a changé est bienvenue ; pas
   d'entrée animée sur chaque section ni d'effet sur chaque carte. Mouvement
   réduit respecté (équivalents Flutter : `ui-ux-pro-max`, §6).
5. **La structure visuelle est de l'information** : bordures, séparateurs,
   numérotation, étiquettes n'ont de sens que s'ils encodent quelque chose
   (pas de « 01 / 02 / 03 » si le contenu n'est pas une suite d'étapes).
6. **Socle de qualité, sans l'annoncer** : lisible sur petit téléphone, focus
   visible, contraste suffisant, mouvement réduit respecté.
7. **Se critiquer en construisant** : captures avant et après, relues avec un
   regard neuf.

## 4. Rédiger l'interface (en français)

Les mots d'une interface servent à comprendre et à agir : ils font partie du
design, ils ne le décorent pas.

- **Point de vue de l'utilisateur**, vocabulaire simple : on gère ses
  notifications, pas une « configuration de webhook ».
- **Voix active.** Un bouton dit exactement ce qui va se passer
  (« Enregistrer les modifications » plutôt que « Envoyer »). Une action garde
  le même nom dans tout le parcours : le bouton « Publier » produit un message
  « Publié ».
- **Échec et vide sont des moments d'orientation.** Expliquer ce qui s'est
  passé et comment le corriger ; l'interface ne s'excuse pas et n'est jamais
  vague. Un écran vide invite à agir.
- **Ton conversationnel** : verbes simples, majuscule de phrase, pas de
  remplissage ; chaque élément écrit fait un seul travail.
- **Limites** : ne pas réécrire les textes juridiques (CGU, confidentialité :
  du ressort du client), les messages d'erreur renvoyés par le serveur, ni ce
  qui annonce un moyen de paiement ou un montant. Orange Money n'est jamais
  proposé.

## 5. Procédure

Celle de `ui-ux-pro-max` (§7) : cadrer, modifier seulement la zone autorisée,
vérifier (analyse, tests, captures avant et après), lister les fichiers avec
`node securite/outils_design.mjs diff <base> HEAD`, commit en français avec la
ligne `Lot-Design: oui` et `[skip ci]`, puis accord du client avant toute
publication.
