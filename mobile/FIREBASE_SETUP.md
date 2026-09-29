# Configuration Firebase — projet "Santine"

Ce dépôt est prêt pour Firebase (packages installés, `main.dart` et
`AuthRepository` câblés), mais **aucun projet Firebase n'existe encore**.
Tant que `lib/firebase_options.dart` contient ses valeurs placeholder,
l'app continue de fonctionner en mode démo (comme aujourd'hui) — rien
ne casse en attendant.

## 1. Créer le projet Firebase

1. Va sur <https://console.firebase.google.com>.
2. Clique sur **Ajouter un projet**.
3. Nomme-le `Santine` (ou `Sprint`), accepte les conditions, tu peux
   désactiver Google Analytics si tu ne comptes pas l'utiliser tout de
   suite (pas nécessaire pour l'auth/la base de données).
4. Clique sur **Créer le projet** et attends la fin de la création.

## 2. Activer l'authentification Email/Mot de passe

1. Dans le menu de gauche : **Build > Authentication**.
2. Onglet **Sign-in method** (ou **Commencer** si c'est la première
   visite).
3. Clique sur **Email/Password** dans la liste des fournisseurs.
4. Active le premier interrupteur (**Email/Password**), laisse le
   second (**Email link**) désactivé. Enregistre.

## 3. Activer Firestore

1. Dans le menu de gauche : **Build > Firestore Database**.
2. Clique sur **Créer une base de données**.
3. Choisis une région proche (ex. `eur3 (Europe)`), clique sur Suivant.
4. Pour démarrer vite : mode **Test** (règles ouvertes 30 jours). On
   verrouillera les règles avant la mise en production réelle — dis-le
   moi quand tu seras prêt, c'est une étape à ne pas oublier avant
   d'avoir de vrais utilisateurs.

## 4. Récupérer la configuration Web

1. Dans le menu de gauche, clique sur l'icône ⚙️ à côté de **Aperçu du
   projet** > **Paramètres du projet**.
2. Descends jusqu'à **Vos applications**, clique sur l'icône Web
   `</>`.
3. Donne un surnom (ex. `Sprint Web`), **ne coche pas** "Configurer
   aussi Firebase Hosting" (le site est déjà sur GitHub Pages).
4. Clique sur **Enregistrer l'application**. Firebase affiche un bloc
   `firebaseConfig = { apiKey: "...", authDomain: "...", ... }`.
5. **Copie ce bloc et envoie-le moi ici dans la conversation** (ces
   valeurs ne sont pas secrètes — c'est normal et sûr de les partager,
   voir la note dans `firebase_options.dart`).

## Une fois que tu m'auras donné ces valeurs

Je les colle dans `lib/firebase_options.dart` à la place des
`A_REMPLACER`, je valide que tout compile, je pousse, et l'app bascule
alors automatiquement sur la vraie authentification Firebase — aucune
autre action de ta part.

## Ce qui n'est pas encore migré

Cette première étape couvre l'authentification (inscription/connexion
Client, Conducteur, Admin) et le profil utilisateur (collection
Firestore `users`). Les courses, les gains, la liste des chauffeurs
côté Admin, etc. restent sur les données de démonstration
(`DemoData`) pour l'instant — ce sera l'objet d'une prochaine étape.

## 5. Activer Firebase Storage (documents KYC)

Les documents chauffeur (permis, carte grise, attestation VTC, photo de
profil) sont désormais envoyés dans Firebase Storage
(`kyc_documents/{uid}/{document}.jpg`), et seule leur URL est gardée
dans Firestore. **Tant que Storage n'est pas activé, l'app retombe
automatiquement sur l'ancien stockage Base64 dans Firestore** : rien
ne casse, mais la migration n'est pas effective.

1. Menu de gauche : **Build > Storage** > **Commencer**.
2. Firebase demande de passer au **plan Blaze** (paiement à l'usage) :
   c'est obligatoire pour Storage. Un quota gratuit couvre la phase de
   lancement ; pose une **alerte de budget** (Google Cloud Console >
   Facturation > Budgets et alertes) dès l'activation.
3. Choisis la même région que Firestore, puis mode **production**.
4. Onglet **Règles** : remplace le contenu par celui du fichier
   `storage.rules` de ce dépôt, puis **Publier**.

Aucune modification de code n'est nécessaire ensuite : le bucket
(`sprint-vtc.firebasestorage.app`) est déjà déclaré dans
`lib/firebase_options.dart`.

Sécurité : l'URL de téléchargement enregistrée dans Firestore donne
accès à la photo à quiconque la possède. Les règles Firestore de la
collection `users` doivent donc réserver la lecture des documents
chauffeur au chauffeur lui-même et à l'Admin.

## 6. Sécurité Firestore et rôle Admin

Les règles de sécurité sont dans `firestore.rules` (testées sur
l'émulateur Firestore : `firestore_rules_test/`, 73 cas). Elles
remplacent les règles "mode Test" de l'étape 3, qui laissent n'importe
qui lire et modifier toute la base.

**L'ordre compte** : l'app doit être déployée *avant* de publier les
règles (l'ancienne version de l'app lisait des données que ces règles
interdisent désormais).

### 6.1 Te donner le rôle Admin (une seule fois)

Aucun écran de l'app ne permet de devenir Admin, et les règles
interdisent à quiconque de s'attribuer ce rôle : il se pose uniquement
depuis la Console.

1. **Authentication > Users** : repère ton compte Admin (le créer avec
   **Ajouter un utilisateur** s'il n'existe pas) et copie son
   **UID utilisateur**.
2. **Firestore Database > Données** > collection `users` :
   - si un document portant exactement cet UID existe, ouvre-le et
     modifie le champ `role` en `admin` (type string) ;
   - sinon, **Ajouter un document**, ID du document = l'UID copié,
     champ `role` (string) = `admin`, champ `email` (string) = ton
     email Admin.
3. Connecte-toi sur `/admin/connexion` : un compte sans ce rôle est
   désormais refusé ("Ce compte n'a pas les droits administrateur").

### 6.2 Publier les règles

1. Vérifie que le dernier déploiement GitHub Pages est terminé.
2. **Firestore Database > Règles** : remplace tout le contenu par celui
   du fichier `firestore.rules` de ce dépôt, puis **Publier**.
3. Ouvre une fois le tableau de bord Admin : il publie automatiquement
   le profil public (nom, téléphone) et l'entrée d'annuaire téléphone
   de tous les comptes existants, nécessaires au chat, aux appels et à
   la connexion par numéro de téléphone.

### Ce que garantissent ces règles

- `users/{uid}` (identité, pièces KYC, statuts) : lisible uniquement par
  son propriétaire et l'Admin. À l'inscription, un utilisateur ne peut
  créer que ses informations de base (impossible de se créer Admin,
  validé ou avec un statut de modération). Ensuite il ne peut modifier
  que son nom, son téléphone et ses pièces ; envoyer une pièce remet son
  dossier "en attente", sans jamais pouvoir le passer à "validé".
  `statutValidation` (validé / rejeté), `statutCompte`, `estValide` et
  `role` ne sont modifiables que par l'Admin.
- `profils_publics/{uid}` : nom, téléphone, rôle, véhicule et plaque.
  Lecture **document par document** : par son propriétaire, l'Admin, ou
  l'autre partie d'une course en cours (voir `liaisons`). **Aucun
  listage** : un client ne peut pas énumérer les chauffeurs, ni un
  chauffeur les clients. `disponible` (chauffeur validé et non
  sanctionné) n'est écrit que par l'Admin.
- `liaisons/{clientId}_{chauffeurId}` : preuve qu'un chauffeur a accepté
  la course d'un client. Écrite par le chauffeur dans la transaction
  d'acceptation, et acceptée par les règles seulement si la course
  correspondante (`getAfter`) est bien à lui, pour ce client, `acceptee`
  ou `en_cours`. Sert de clé aux règles de profils, de chat et de suivi
  GPS. Lecture Admin uniquement. Un client ne voit et ne contacte que le
  chauffeur de sa course active (l'identité reste lisible 1 jour après
  la course, pour la noter).
- `annuaire_telephones` : lecture d'une entrée précise possible avant
  connexion (connexion par téléphone), mais aucun listage possible.
- `courses` : un client ne crée et ne liste que ses propres demandes,
  sans pouvoir s'attribuer un chauffeur ni antidater ; seuls les chauffeurs validés
  et non sanctionnés voient et acceptent les courses en attente.
- `appareils/{uid}/jetons/{jeton}` : jetons des notifications push (voir
  section 7) ; écrits et supprimés par leur propriétaire, jamais lisibles
  par un utilisateur.
- `chats` : lecture réservée aux deux participants ; création et envoi
  de messages seulement pendant leur course en cours (`liaisons`), sans
  usurpation d'expéditeur. Après la course, la conversation reste
  lisible mais plus rien ne peut être envoyé.
- `evaluations` : une par course, laissée par le client d'une course
  terminée, jamais modifiable ; la note moyenne du chauffeur (profil
  public) est mise à jour dans la même écriture et ne peut augmenter que
  de la note donnée.
- `positions_chauffeurs` : position GPS des chauffeurs en ligne, publiée
  par le chauffeur validé lui-même, lisible par l'Admin (carte "Courses
  en direct") et par le client uniquement pendant SA course avec ce
  chauffeur (suivi d'approche), dès l'acceptation (via `liaisons`, sans
  attendre que le téléphone du chauffeur ait republié sa position) ;
  effacée quand il passe hors ligne. **La position lue par le client de
  la course est exacte (jamais arrondie)** ; le chauffeur publie toutes
  les ~2 s pendant une course (un point tous les 3 m, et un battement
  toutes les 5 s même à l'arrêt) ; hors course : 5 s / 10 m. Seule la
  carte d'accueil (motos anonymes, autres clients) passe par l'arrondi
  à ~150 m de `chauffeursProches`, qui exclut d'ailleurs les chauffeurs
  en course.
  L'accueil client ne la lit jamais directement : la Cloud Function
  `chauffeursProches` ne renvoie que des positions arrondies à ~150 m,
  sans identité.
- Seul le chauffeur attribué fait avancer sa course (client à bord, puis
  course terminée), sans pouvoir sauter d'étape ni toucher au prix.
- Courses : aucune course ne peut être créée depuis l'app, même par
  l'Admin. Seul le serveur les crée (étape 7), une fois le paiement
  confirmé par l'opérateur, avec le prix qu'il calcule lui-même.
  Paiement 100 % mobile money (Wave ou Orange Money).
- Annulations (client tant que la course est en attente, chauffeur avec
  un motif) : uniquement par la Cloud Function `annulerCourse`, qui
  rembourse le client ; jamais directement depuis l'app.
- `tickets/{courseId}` (support, un signalement par course) : ouvert par
  le client de la course, lisible par lui et l'Admin ; la conversation
  (`messages`) n'accepte que le client et l'Admin, sans usurpation
  d'auteur ni modification après envoi. Seul l'Admin clôt ou rouvre un
  ticket. Les messages "système" (remboursement effectué) sont écrits
  par le serveur.
- `journal_admin` : trace de chaque remboursement et de chaque sanction
  (qui, quoi, motif), écrite par le serveur seul, lisible par l'Admin.
- `commandes` (demandes de paiement) : écrites par le serveur seul,
  lisibles par leur client et l'Admin. `config` (secrets du serveur) :
  fermée à l'app.
- Finances : à la fin d'une course, la commission de la plateforme (15 %
  du prix) est figée et vérifiée par les règles. Sprint encaisse chaque
  course et doit au chauffeur sa part (85 %) ; les versements de Sprint
  au chauffeur (`reglements`) ne sont saisis que par l'Admin, dans ce
  seul sens. Une course remboursée au client (marquée `rembourseeLe` par
  le serveur, marque que ni le chauffeur ni le client ne peuvent effacer)
  sort des comptes : ni chiffre d'affaires, ni commission, ni part pour le
  chauffeur. Le temps en ligne (`temps_en_ligne`) ne peut augmenter que
  d'une minute par minute.
- Toute autre collection : refusée.

### Limites connues (à traiter avant le lancement)

- Suivi GPS : sur le site (et l'iPhone, qui n'a que le site), le
  navigateur coupe la géolocalisation quand l'écran du chauffeur se
  verrouille ou que l'app passe en arrière-plan. L'app garde l'écran
  allumé tant que le chauffeur est en ligne, et la carte Admin affiche
  "Signal perdu" au bout de 2 minutes sans nouvelle. L'APK Android
  (voir DISTRIBUTION_TEST.md) continue, lui, écran verrouillé.

- Paiement en mode test : tout le parcours passe par le serveur, mais
  l'opérateur est simulé (« faux Wave », page de paiement
  `pagePaiementSimule`, aucune somme débitée ; `modePaiement:
  "simulation"` sur la course). Pour passer au vrai Wave : ranger
  `WAVE_API_KEY` et `WAVE_WEBHOOK_SECRET` dans Secret Manager et brancher
  `FournisseurWave` (déjà écrit) dans `functions/src/index.ts`. Orange
  Money passe aujourd'hui par la même simulation ; en réel, il lui
  faudra son propre fournisseur.
- Un numéro de téléphone n'est pas garanti unique : si quelqu'un
  revendique en premier le numéro d'un autre dans l'annuaire, ce dernier
  ne pourra se connecter que par email (aucun accès à son compte n'est
  donné pour autant).

## 7. Cloud Functions : prix, paiement et courses (plan Blaze)

Le dossier `functions/` (TypeScript) contient ces fonctions, déployées
en `europe-west1` (même région que Firestore `eur3`) :

- `estimerPrix` : calcule le prix d'un trajet à partir des coordonnées :
  distance **par la route** (Google Routes API, mise en cache 30 jours
  dans la collection `distances`, réservée au serveur), majoration heure
  de pointe / nuit, minimum. Si Google ne répond pas, la distance est
  estimée (vol d'oiseau + 10 %) pour ne jamais bloquer une commande.
  C'est ce prix que l'app affiche avant la commande.
- `rechercherAdresses` et `coordonneesAdresse` : recherche d'adresses
  Google Places (API New) pour l'app, limitée au Sénégal, Dakar en
  priorité. Si elles échouent, l'app bascule sur OpenStreetMap.
- `creerPaiement` : recalcule ce prix, enregistre une commande en
  attente (`commandes`) et renvoie le lien de paiement de l'opérateur.
  Si le prix a changé depuis son affichage (passage en heure de
  pointe…), rien n'est créé et l'app affiche le nouveau prix.
- `webhookPaiement` : reçoit la confirmation **signée** de l'opérateur
  (en-tête `Wave-Signature`, HMAC-SHA256, 5 minutes de validité). Paiement
  réussi et montant exact : la course est créée (une seule, même si la
  confirmation arrive plusieurs fois). Refus : commande échouée. Montant
  différent : commande en anomalie, aucune course. Paiement arrivé après
  expiration : remboursé.
- `pagePaiementSimule` : la page de paiement du faux Wave (boutons
  « Payer » / « Refuser »), qui envoie au webhook un événement signé
  exactement comme Wave. Son secret de signature est créé
  automatiquement dans `config/paiementSimule`.
- `annulerCourse` : annulation par le client (course en attente) ou par
  le chauffeur attribué (avec un motif), puis remboursement.
- `surveillerCommandes` (toutes les 5 minutes) : paiement non finalisé
  au bout de 20 minutes → commande expirée ; course sans chauffeur au
  bout de 10 minutes → annulée et remboursée. Un remboursement refusé par
  l'opérateur laisse la commande en `remboursement_echoue`, à traiter à
  la main.
- `rembourserCourseAdmin` (Admin, depuis un ticket du support) :
  remboursement intégral d'une course terminée ou annulée, avec un motif
  obligatoire. Refusé si la course est encore en cours ou déjà
  remboursée. Le client en est informé dans son ticket. Le chauffeur n'est
  pas payé pour une course remboursée : sa part (85 %) sort de ce que
  Sprint lui doit (`partChauffeurRetireeFcfa` sur la course et dans le
  journal) ; si elle lui avait déjà été versée, elle est déduite de ses
  prochains gains.
- `sanctionnerCompte` (Admin) : suspension, bannissement ou réactivation
  d'un compte, avec un motif obligatoire. Pour un chauffeur sanctionné :
  retiré des chauffeurs disponibles, position effacée, et sa course en
  cours (acceptée ou client à bord) annulée et remboursée au client.

- `chauffeursProches` (client connecté ; accueil et écrans de commande
  course moto / colis) : motos disponibles
  dans un rayon de 3 km (position de moins de 2 minutes, chauffeur sans
  course en cours). Chaque position est ramenée au centre d'une case
  d'environ 150 m, une case n'apparaît qu'une fois, jamais d'identifiant ;
  cap arrondi à 45° pour orienter l'icône ; au plus 15 motos, plus une
  estimation d'approche en minutes. Une fois la course acceptée, le
  client voit l'identité de SON chauffeur (nom, véhicule, plaque), lue
  dans son profil public : ce n'est pas passé par cette fonction.

### 7.1 Déploiement automatique (GitHub Actions)

À chaque push, GitHub Actions teste le backend puis déploie les Cloud
Functions, **puis** les règles Firestore (l'ordre compte : les règles
interdisent la création directe des courses), et enfin l'app web. Si un
test échoue, rien n'est déployé.

Pour cela, GitHub a besoin d'une clé de **compte de service** Google,
rangée dans un secret du dépôt. À faire une seule fois, entièrement
depuis le navigateur, connecté avec le compte Google du projet Firebase :

1. Ouvrir
   https://console.cloud.google.com/iam-admin/serviceaccounts?project=sprint-vtc
   puis **+ Créer un compte de service**. Nom : `github-deploy`, puis
   **Créer et continuer**.
2. **Rôles** (bouton **+ Ajouter un autre rôle** pour chacun), puis
   **Continuer** et **OK** :
   - Administrateur Firebase (*Firebase Admin*)
   - Administrateur Cloud Functions (*Cloud Functions Admin*)
   - Administrateur Cloud Run (*Cloud Run Admin*)
   - Utilisateur du compte de service (*Service Account User*)
   - Administrateur Artifact Registry (*Artifact Registry Administrator*)
   - Administrateur Service Usage (*Service Usage Admin*)
   - Administrateur Secret Manager (*Secret Manager Admin*)
   - Administrateur Cloud Scheduler (*Cloud Scheduler Admin*) : pour
     `surveillerCommandes`. Sans lui, le pipeline s'arrête **avant**
     tout déploiement avec l'erreur « Rôle manquant ».
   (Pour un compte déjà créé : page **IAM**, crayon à droite de
   `github-deploy`, **+ Ajouter un autre rôle**, **Enregistrer**.)
3. Cliquer sur le compte `github-deploy` créé, onglet **Clés** >
   **Ajouter une clé** > **Créer une clé** > **JSON** > **Créer** : un
   fichier `.json` est téléchargé.
4. Sur GitHub : dépôt > **Settings** > **Secrets and variables** >
   **Actions** > **New repository secret**. Name :
   `FIREBASE_SERVICE_ACCOUNT` ; Secret : **tout** le contenu du fichier
   `.json` (l'ouvrir avec le Bloc-notes, tout sélectionner, copier,
   coller). **Add secret**.
5. Supprimer le fichier `.json` de l'ordinateur. Ne jamais l'envoyer par
   message : quiconque le possède peut déployer sur le projet.
6. Relancer le déploiement : onglet **Actions** > **Build & déployer
   Sprint Web** > **Run workflow** (ou pousser un commit).

Tant que le secret n'existe pas, le pipeline publie l'app web mais
affiche l'avertissement "Firebase non déployé" : les fonctions et les
règles ne sont alors pas mises à jour.

Le premier déploiement active quelques services Google Cloud (Cloud
Functions, Cloud Build, Artifact Registry, Cloud Run) et peut prendre
plusieurs minutes. S'il échoue avec une erreur de permission, le journal
de GitHub Actions nomme la permission manquante : ajouter le rôle
correspondant au compte `github-deploy` (page **IAM**), puis relancer.

Alternative sans GitHub (depuis un ordinateur, CLI Firebase 15 ou plus) :
`cd mobile && npm --prefix functions install && firebase deploy --only
functions --project sprint-vtc && firebase deploy --only firestore:rules
--project sprint-vtc`.

### Clé Google Maps Platform

Places API (New) et Routes API utilisent la clé rangée dans Secret
Manager sous le nom `GOOGLE_MAPS_API_KEY` (restreinte à ces deux API,
jamais présente dans l'app ni dans GitHub). Le compte `github-deploy`
doit avoir le rôle **Administrateur Secret Manager** pour que le
déploiement donne aux fonctions l'accès à ce secret. Pour changer de
clé : ajouter une nouvelle version du secret dans Secret Manager, puis
relancer le déploiement (onglet Actions > Run workflow).

- Notifications push (APK Android ; web et iPhone dans un autre lot) :
  elles arrivent même app fermée.
  - Chaque téléphone enregistre son jeton dans
    `appareils/{uid}/jetons/{jeton}` (règles : chacun écrit et supprime
    les siens, **personne ne les lit**, pas même leur propriétaire ; seul
    le serveur les lit). L'app le supprime à la déconnexion, le serveur
    supprime ceux que Google déclare morts.
  - `notifierMessage` (l'expéditeur l'appelle après chaque message) : le
    serveur relit le message enregistré (le texte n'est jamais fourni par
    l'appelant), vérifie qu'une course est en cours entre les deux, et ne
    notifie qu'une fois par message. **Le texte du message s'affiche dans
    la notification, donc sur l'écran verrouillé** (choix du client).
  - `notifierAcceptation` (appelée par le chauffeur après avoir accepté) :
    « Chauffeur trouvé ! Nom · moto · plaque » au client.
  - Nouvelle course : à la confirmation du paiement, les chauffeurs en
    ligne, validés, non sanctionnés et sans course en cours sont prévenus
    (100 au plus). Course annulée par le chauffeur, ou faute de chauffeur :
    le client est prévenu.
  - Une notification qui échoue ne fait jamais échouer le paiement ou
    l'annulation qui l'a déclenchée. Quand l'app est ouverte, Android
    n'affiche pas la notification : l'app a ses propres alertes.
  - La CI vérifie que l'API Firebase Cloud Messaging répond (envoi « à
    blanc » vers un jeton invalide, avertissement sinon). L'arrivée d'une
    vraie notification sur un vrai téléphone ne peut être vérifiée que par
    un test réel (deux téléphones, app fermée).

### 7.2 Tests

```bash
cd mobile/functions
npm test                  # moteur de prix (dont parité avec l'app), validation, signatures
npm run test:emulateur    # paiement, courses, annulations, surveillance, remboursement Admin, sanctions, motos à proximité, notifications push (émulateur Firestore)
```

