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

**État : activé le 8 octobre 2026** par le client (bucket
`gs://sprint-vtc.firebasestorage.app`, mode production, région
`europe-west1`). La CI publie `storage.rules` à partir de la publication
suivante ; la migration des pièces déjà envoyées en Base64 se lance ensuite
depuis Admin > Paramètres (voir plus bas).

Les documents chauffeur (permis, carte grise, attestation VTC, photo de
profil) partent dans Firebase Storage
(`kyc_documents/{uid}/{document}.jpg`), et seule leur URL est gardée
dans Firestore. **Tant que Storage n'est pas activé, l'app retombe
automatiquement sur le stockage Base64 dans Firestore** (plafond 700 Ko
par pièce) : rien ne casse, mais la migration n'est pas effective. La CI
vérifie à chaque déploiement si le bucket existe et le signale par un
avertissement jaune « Firebase Storage » dans le job `firebase`.

À faire une seule fois, dans la Console (c'est la seule étape manuelle) :

1. Menu de gauche : **Build > Storage** > **Commencer**.
2. Plan **Blaze** (déjà actif pour les Cloud Functions). Pose une
   **alerte de budget** (Google Cloud Console > Facturation > Budgets).
3. Même région que Firestore, mode **production**.
4. C'est tout : au déploiement suivant, la CI publie `storage.rules`
   (étape « Règles Firebase Storage (documents KYC) »). Il n'y a plus
   rien à coller à la main.

Ensuite, pour les pièces déjà envoyées en Base64 : **Admin > Paramètres >
Stockage des documents KYC**. « Actualiser » compte les pièces restantes
(sans rien écrire), « Migrer vers Storage » en déplace un lot de 10
chauffeurs à la fois : on relance jusqu'à « Aucune pièce en Base64 ». La
migration est rejouable, ne touche pas les pièces déjà dans Storage, ne
remet pas en cause la validation d'un dossier, et ne remplace jamais une
pièce que le chauffeur renverrait pendant ce temps. Chaque lot est tracé
dans le journal Admin (`migration_kyc_storage`).

Règles (`storage.rules`, testées sur l'émulateur : `firestore_rules_test/storage.test.mjs`) :
seul le chauffeur lit, écrit, remplace ou supprime ses 4 pièces ; pas de
liste de fichiers ; images (jpeg, png, webp) de 5 Mo au plus ; tout le
reste est fermé.

Sécurité : l'URL de téléchargement enregistrée dans Firestore contient un
jeton secret qui donne accès à la photo à quiconque la possède. Les règles
Firestore de `users` réservent donc la lecture des documents au chauffeur
et à l'Admin. L'Admin affiche les pièces avec cette URL (pas de règle
croisée Firestore ↔ Storage, qui exigerait un droit IAM supplémentaire
impossible à accorder depuis la CI).

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
- `annuaire_telephones` (téléphone -> e-mail, pour la connexion par
  numéro) : **réservé au serveur**. Avant, une entrée était lisible par
  tous : on pouvait y tester des numéros pour savoir qui a un compte et
  récupérer son e-mail. Maintenant la connexion passe par la fonction
  `connexionTelephone` (voir section 7), qui vérifie le mot de passe et ne
  rend l'e-mail qu'à son propriétaire ; l'entrée du compte est publiée par
  `synchroniserAnnuaire`. Mise en place en deux temps, terminée le 8
  octobre 2026 : (1) fonctions et app, la lecture publique restant ouverte
  pour les anciennes versions de l'app ; (2) après validation par le client
  de la connexion par téléphone sur de vrais téléphones, fermeture des
  règles : plus aucune lecture ni écriture par l'app ; l'Admin garde la
  lecture unitaire et l'écriture pour son rattrapage. Les versions de l'app
  antérieures à la 0.1.0 (94) ne peuvent donc plus se connecter par numéro
  (par e-mail, oui) tant qu'elles ne sont pas mises à jour.
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
  Paiement 100 % mobile money (Wave) ou avec le solde du portefeuille ;
  Orange Money est **fermé** (voir « Passage à l'argent réel »).
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
  Money est refusé par le serveur tant qu'il n'a pas son propre
  fournisseur réel.
- Un numéro de téléphone n'est pas garanti unique : si quelqu'un
  revendique en premier le numéro d'un autre dans l'annuaire, ce dernier
  ne pourra se connecter que par email (aucun accès à son compte n'est
  donné pour autant). Le numéro n'est pas vérifié par SMS.
- **Connexion par téléphone** (`functions/src/connexion_telephone.ts`) :
  `connexionTelephone` (appelable sans être connecté) vérifie le mot de
  passe auprès de Firebase Auth et rend l'e-mail du compte à celui qui le
  connaît ; l'app finit la connexion avec Firebase Auth (e-mail + mot de
  passe). Numéro inconnu et mot de passe faux : même réponse, au moins
  0,8 s. Essais limités : 5 échecs par numéro (qu'il existe ou non) puis
  blocage de 15 minutes, 100 échecs par adresse réseau ; compteurs dans
  `limites_connexion` (identifiants hachés, aucun numéro ni mot de passe,
  champ `expireLe` pour une règle de durée de vie Firestore).

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
- `verifierSauvegardes` (chaque jour à 09 h 07, heure de Dakar, soit UTC) :
  contrôle des sauvegardes de la base fait par Google lui-même, sans GitHub.
  Lecture seule ; prévient les comptes Admin par notification si la dernière
  sauvegarde a plus de 36 h, si une planification manque ou si Google refuse
  la lecture (section 10.4). Fonction privée, comme `surveillerCommandes`.
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
- `itineraireCourse` (chauffeur attribué à la course, acceptée ou client à
  bord) : le tracé et la distance par la route pour rejoindre son client,
  puis la destination (Google Routes API, même clé que les adresses, sans
  trafic). Le point visé est lu dans la course, jamais envoyé par l'app ;
  seul le chauffeur de la course l'obtient ; au plus un calcul toutes les
  10 secondes par course (champ `itineraireLe`) ; à moins de 30 m du point
  visé, la distance est rendue sans tracé et sans appel à Google. Si Google
  ne répond pas, l'app se replie sur une estimation à vol d'oiseau. Pour
  rejoindre le client, le point visé est la position exacte lue dans le
  document privé de la course (`courses/{id}/prive/depart`) : jamais le
  départ arrondi de la course ; document absent ou abîmé : refus
  `failed-precondition`.
- Position du départ des courses : le document `courses/{id}` ne porte que le
  centre de la case d'environ 150 m (`arrondirPosition`) qui contient le
  départ, avec `departArrondi: true`, tant que des chauffeurs peuvent la lire
  (course en attente). La position exacte est écrite par le serveur dans la même
  transaction (`courses/{id}/prive/depart`, paiement mobile money ou solde) ;
  les règles ne la donnent qu'au client de la course, à son chauffeur tant que
  la course est acceptée ou en cours, et à l'Admin, et n'en autorisent aucune
  écriture depuis l'app. L'arrivée reste exacte. Les commandes (`commandes`,
  lues par le client seul) gardent la position exacte. Une course d'avant ce
  masquage garde sa position exacte dans son document. Un document de course
  supprimé à la main (Admin) laisse son document privé : à supprimer avec.

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
   - Pour les sauvegardes de la base (section 10, flux « Sauvegardes
     Firestore », sans effet sur le déploiement) : `roles/datastore.backupSchedulesAdmin`
     (planifications de sauvegarde) et `roles/datastore.backupsViewer`
     (lecture des sauvegardes). Dans la liste des rôles, taper l'identifiant
     dans le filtre.
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

- Notifications push (APK Android, site dans un navigateur, site installé
  sur l'iPhone) : elles arrivent même app ou site fermé.
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
  - **Site et iPhone** : même serveur, même texte. Le site enregistre un
    service worker (`web/firebase-messaging-sw.js`, servi à la racine)
    qui affiche la notification site fermé ; l'appui ouvre la bonne page
    (`/#/accueil/messages`, `/#/accueil/activite`, `/#/conducteur`, choisie
    par le serveur selon le rôle du destinataire). La clé « web push »
    est celle que Firebase fournit par défaut : rien à créer dans la
    console. Règles propres au web :
      - l'autorisation ne peut être demandée qu'à l'appui sur un bouton
        (carte « Notifications » : Compte, Messages, écran de recherche
        d'un chauffeur, accueil chauffeur) ; jamais à l'ouverture ;
      - **iPhone : seulement iOS 16.4 ou plus récent, et seulement pour
        le site installé sur l'écran d'accueil** (Safari > Partager >
        « Sur l'écran d'accueil », puis ouvrir Sprint depuis son icône).
        Dans un onglet Safari, Apple n'offre pas les notifications : la
        carte explique la marche à suivre ;
      - une notification refusée se rouvre dans les réglages du
        navigateur (ou de l'app installée) ;
      - site ouvert au premier plan, rien n'est affiché par le système :
        l'app a ses propres alertes.
    Il n'existe pas d'app iPhone native : elle demanderait un compte
    Apple Developer, une clé APNs et une publication sur l'App Store.
  - La CI vérifie que le site sert bien le service worker à la racine (en
    JavaScript, et non la page d'accueil), et que l'API Firebase Cloud
    Messaging répond (envoi « à
    blanc » vers un jeton invalide, avertissement sinon). L'arrivée d'une
    vraie notification sur un vrai téléphone ne peut être vérifiée que par
    un test réel (deux téléphones, app fermée).

### 7.1 bis Portefeuille Sprint (mode test : faux Wave)

Crédit prépayé du client, **non retirable**, utilisable uniquement pour
payer des courses. Tout passe par le serveur (`functions/src/portefeuille.ts`)
et fonctionne aujourd'hui contre le faux Wave : **aucune somme réelle ne
bouge** tant que le vrai Wave n'est pas branché (voir
« Passage à l'argent réel » plus bas).

- **Données** (jamais écrites par l'app, sauf la préférence) :
  - `portefeuilles/{uid}` : `soldeFcfa` (serveur) et `payerAvecSolde`
    (l'interrupteur « Régler mes courses avec mon solde », seul champ que
    le client peut écrire) ;
  - `portefeuilles/{uid}/mouvements/{id}` : livre de comptes en ajout
    seul (recharge, paiement_course, remboursement, ajustement_admin) avec
    le solde après chaque opération. Identifiants déterministes
    (`recharge_<id>`, `course_<commande>`, `remboursement_<commande>`) :
    rejouer un webhook ou un remboursement ne crédite ni ne débite jamais
    deux fois. La somme des mouvements est toujours égale au solde
    (contrôle visible dans la fiche Admin) ;
  - `recharges/{rch_…}` : demandes de recharge (en_attente, reussie,
    echouee, expiree, anomalie), écrites par le serveur.
- **Limites** (serveur, reprises à l'affichage) : recharge de 500 à
  100 000 FCFA, solde plafonné à 200 000 FCFA, 5 recharges en attente au
  plus par client, expiration à 20 minutes. Un remboursement n'est jamais
  bloqué par le plafond.
- **Recharge** : callable `creerRecharge` (client seulement, compte actif)
  -> lien de paiement Wave -> webhook signé (le même que
  pour les courses, référence `rch_…`) -> solde crédité dans une
  transaction. Montant ou devise différents de la demande, ou dépassement
  du plafond par deux recharges simultanées : statut `anomalie`, rien
  n'est crédité, l'Admin est prévenu par le statut (à rembourser). Un
  paiement arrivé après l'expiration est crédité (l'argent est encaissé).
- **Payer une course avec le solde** : `creerPaiement` avec
  `methodePaiement: "PORTEFEUILLE"` débite le solde, crée la commande
  (déjà `payee`) et la course dans **une seule transaction** ; solde
  insuffisant : refus net, rien d'écrit, le client choisit Wave pour le
  total (pas de paiement partiel). Dans l'app, avec
  l'interrupteur actif et un solde suffisant, « Payer avec mon solde »
  passe en premier dans le choix du mode de paiement (un appui).
- **Remboursements** (annulation client ou chauffeur, aucune réponse au
  bout de 10 min, chauffeur suspendu, remboursement Admin) : une course
  payée avec le solde est recréditée **sur le solde**, sans appel au
  fournisseur.
- **Admin** : onglet Clients, icône portefeuille : solde, cohérence du
  livre, historique, et ajustement manuel motivé (callable
  `ajusterPortefeuille`, solde entre 0 et 200 000 FCFA, journalisé dans
  `journal_admin`).

#### Passage à l'argent réel (à faire, rien n'est branché)

1. Compte Wave Business (API Checkout) : `WAVE_API_KEY` (clé API) et
   `WAVE_WEBHOOK_SECRET` dans Secret Manager, puis brancher
   `FournisseurWave` dans `functions/src/index.ts`. Le secret du webhook
   est **distinct de la clé API** : Wave le remet quand on lui communique
   l'adresse du webhook (`webhookPaiement`). Ce code n'a **jamais tourné
   contre l'API réelle** : il suit la documentation publique de Wave
   (signature `Wave-Signature` = HMAC-SHA256 de l'horodatage collé au
   corps brut, sans séparateur, plusieurs `v1` possibles) et sera à
   revalider avec le premier événement réel du bac à sable.
2. Orange Money : **fermé côté serveur et côté app** (`functions/src/methodes_paiement.ts`,
   `moyensMobileMoneyDisponibles` dans l'app) : le serveur refuse `ORANGE_MONEY`
   (course et recharge) avec « Orange Money n'est pas encore disponible », car
   il passerait par la simulation et rendrait les courses gratuites. Aucun
   fournisseur n'existe encore ; il faut le contrat marchand Sonatel et sa
   documentation. À sa réouverture : brancher son fournisseur, PUIS l'ajouter
   aux deux listes. Les anciennes courses et recharges Orange gardent leur libellé.
3. **Avant de garder l'argent des clients** : faire confirmer le cadre
   réglementaire (monnaie électronique, BCEAO).
4. Un premier test réel avec un petit montant, puis contrôle du livre.

### 7.2 Tests

```bash
cd mobile/functions
npm test                  # moteur de prix (dont parité avec l'app), validation, signatures
npm run test:emulateur    # paiement, courses, annulations, surveillance, remboursement Admin, sanctions, motos à proximité, notifications push, portefeuille (émulateur Firestore)
```


## 8. Écran de démarrage « Onyx »

Fond noir profond (`#0B0B0C`, « Onyx »), logo Sprint au centre (tuile de
marbre noir, « S » blanc de verre, liseré et point verts), rien d'autre. Un
seul dessin (`assets/logo/source-1024.jpg`), décliné par
`tool/generer_icones.cjs` à plusieurs endroits, à régénérer ensemble :
`web/index.html` (image intégrée), `assets/logo/tuile.png` (écran Flutter,
`lib/core/widgets/logo_sprint.dart`), les icônes (`web/icons/`,
`web/favicon.png`, `android/.../mipmap-*`), l'écran de démarrage Android
(`drawable-nodpi/splash_logo.png`) et les images `web/splash/ios-*.png`.
Le test `test/splash_test.dart` vérifie qu'ils restent d'accord.

- **Site (navigateur, PWA)** : l'écran est dans `index.html` lui-même
  (CSS et logo en ligne, aucun fichier à attendre) et s'affiche avant tout
  chargement. Il est retiré en fondu quand Flutter a dessiné sa première
  image, jamais avant 0,7 s (le logo doit être vu), au plus tard après 20 s.
- **App (Flutter)** : `SplashSprint` est posé sous toutes les pages
  (`MaterialApp.router(builder:)`) : tant que le routeur n'a rien à
  montrer, c'est lui qui est visible, jamais un écran blanc.
- **iPhone installé sur l'écran d'accueil** : iOS n'affiche l'écran de
  démarrage que grâce à des images (`apple-touch-startup-image`), une par
  taille d'écran ; 12 tailles d'iPhone sont fournies (iPad : non). iOS les
  garde en cache à l'installation : après une mise à jour, supprimer
  l'icône puis réinstaller le site pour les voir.
- **Android (APK)** : `launch_background.xml` (fond Onyx, logo) avant
  Android 12 ; thèmes `values-v31` et `values-night-v31` (écran de
  démarrage système) à partir d'Android 12.
- **PWA Android** : `background_color` du manifeste en Onyx ; l'icône de
  l'écran d'accueil est le même logo (tuile).

### Après la publication de la charte « Onyx & Vert » (8 octobre 2026)

- **iPhone (site installé sur l'écran d'accueil)** : fermer complètement
  l'app (la balayer vers le haut dans le sélecteur d'apps) puis la rouvrir
  pour charger la nouvelle version. iOS garde en cache l'icône et les
  images de démarrage : pour voir le nouveau logo, supprimer l'icône de
  l'écran d'accueil puis réinstaller le site depuis Safari.
- **Android (APK)** : la nouvelle version s'installe par-dessus l'ancienne
  depuis la page `/android/` ; l'icône, la couleur des notifications et
  l'écran de démarrage changent avec elle.
- **Carte** : le style « Sprint sombre » est envoyé à Google à l'ouverture
  de chaque session de carte. La CI le fait valider par Google à chaque
  déploiement (étapes « Vérifier la carte Google ») ; s'il était refusé, un
  avertissement apparaît dans le résumé du run et la carte reste sur le
  style Google standard, clair, jusqu'à correction.
- **Aucun orange** : `test/palette_onyx_vert_test.dart` refuse tout retour
  de l'orange (noms et valeurs de couleur, logo) et le texte blanc sur le
  vert ; les statuts d'alerte et d'attente restent en jaune, comme les
  étoiles de notation (choix du client).

## 9. Sécurité : contrôles automatiques, en-têtes du site, secrets

- **Contrôles de la CI** (`securite/`, voir `securite/LISEZMOI.md`) : aucun
  secret dans le dépôt, les lignes ajoutées, le site compilé (et l'APK, en
  avertissement) ; aucune dépendance vulnérable (Cloud Functions : haute ou
  critique ; outils de test : critique ; paquets Dart : tout avis). Ils
  bloquent le déploiement ; les exceptions se déclarent, motivées et datées,
  dans `securite/exceptions.json`.
- **En-têtes du site** (`firebase.json`, Hosting) : `X-Content-Type-Options:
  nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy:
  strict-origin-when-cross-origin`, `Permissions-Policy`, `Strict-Transport-Security`
  et une politique CSP limitée à `frame-ancestors 'none'; base-uri 'self';
  object-src 'none'; form-action 'self'` (anti-framing, sans effet sur le
  chargement des scripts). La CI vérifie qu'ils sont servis après le
  déploiement (avertissement sinon). Une CSP complète (`script-src`,
  `connect-src`…) reste à écrire, avec un point de collecte des violations.
- **Secrets** : le dépôt est public. Les clés de paiement (Wave, plus tard
  Orange Money) et la clé Google Maps du serveur vivent **uniquement** dans
  Secret Manager ; jamais dans le code, l'app, GitHub ni un message. À activer
  sur le dépôt GitHub : Settings > Code security > alertes Dependabot, Secret
  scanning et Push protection.

## 10. Sauvegardes de la base (automatiques)

Les sauvegardes de Firestore sont prises **par Google**, pas par GitHub :
elles continuent même si GitHub ou la CI s'arrêtent.

- **Une par jour**, gardée **14 jours**, et **une par semaine** (le
  dimanche), gardée **14 semaines** (le maximum accepté par Firestore). Les
  heures sont choisies par Google (UTC).
- Une sauvegarde contient les documents et les index de la base `(default)`.
  Elle **ne contient pas** : les règles de sécurité (elles sont dans le
  dépôt, `firestore.rules`), les comptes de connexion (Firebase Auth) ni les
  fichiers (Firebase Storage : pièces KYC des chauffeurs).
- Coût : facturé au volume stocké (par Go et par mois), donc modeste pour une
  base de cette taille. La taille et le nombre de documents de chaque
  sauvegarde sont affichés dans le résumé du contrôle (page du run, onglet
  Actions) dès que Google les communique : il ne les renseigne qu'une fois la
  sauvegarde entièrement copiée, et le contrôle écrit « non communiquée » d'ici
  là. La sauvegarde existe alors, mais seul un essai de restauration (10.3)
  prouve son contenu.

### 10.1 Mise en place (une seule fois)

1. Donner au compte `github-deploy` les deux rôles de la liste de l'étape
   7.1 : `roles/datastore.backupSchedulesAdmin` et
   `roles/datastore.backupsViewer` (page **IAM** de Google Cloud, crayon à
   droite du compte, **+ Ajouter un autre rôle**, **Enregistrer**).
2. GitHub : onglet **Actions** > **Sauvegardes Firestore** > **Run
   workflow**. Le flux vérifie les droits, crée les deux planifications si
   elles manquent (il n'en modifie aucune qui existe déjà), puis contrôle les
   sauvegardes. Il ne déploie rien.
3. La première sauvegarde est prise dans les 24 h. Le contrôle l'attend
   (simple notice) pendant 36 h, puis échoue s'il n'en voit toujours aucune.

Sans les deux rôles, le flux s'arrête au premier pas avec l'erreur « Droits
manquants pour les sauvegardes » qui nomme les droits absents.

### 10.2 Contrôle quotidien

Chaque jour à 06 h 17 (UTC), le même flux refait ces vérifications : les
droits, la présence des deux planifications (une planification supprimée par
erreur est recréée) et l'âge de la dernière sauvegarde. Il échoue, avec une
annotation rouge qui explique pourquoi, si la dernière sauvegarde a plus de
36 h, si aucune n'existe alors que les planifications ont plus de 36 h, ou si
Google refuse l'accès. Lancé par le planning, il ouvre alors un ticket GitHub
« Sauvegardes Firestore : à vérifier » (un seul tant qu'il reste ouvert).

GitHub suspend les flux planifiés d'un dépôt public sans activité pendant 60
jours : les sauvegardes de Google, elles, continuent. Une durée de
conservation modifiée à la main dans la console est signalée par un
avertissement, jamais corrigée.

### 10.3 Restaurer

Une restauration **ne remplace jamais** la base en ligne : elle crée une
**nouvelle base** à partir d'une sauvegarde, que l'on peut examiner sans rien
risquer (les règles de sécurité sont à republier sur cette base). Depuis Cloud
Shell ou un poste avec `gcloud` :

```bash
gcloud firestore backups list --project=sprint-vtc
gcloud firestore databases restore --project=sprint-vtc \
  --source-backup=projects/sprint-vtc/locations/<emplacement>/backups/<identifiant> \
  --destination-database=restauration-AAAAMMJJ
```

Pour ramener des données dans la base en ligne, on exporte la base restaurée
puis on l'importe dans `(default)` (`gcloud firestore export` / `import`), ou
l'on recopie seulement les documents nécessaires. À faire avec le
développeur, après l'avoir examiné : un import réécrit les documents de même
chemin. Un essai de restauration (restaurer, comparer le nombre de documents,
supprimer la base d'essai) est recommandé après la première sauvegarde, puis
de temps en temps : une sauvegarde jamais restaurée n'est pas prouvée.

Non couvert ici (à prévoir) : l'export des comptes de connexion (Firebase
Auth) et la copie des fichiers Storage.

### 10.4 Contrôle par une fonction Google (indépendant de GitHub)

Les flux planifiés de GitHub ne sont pas garantis : le 10 octobre 2026, celui
de 06 h 17 UTC est parti à 12 h 34 UTC, avec plus de 6 h de retard. La
fonction `verifierSauvegardes` refait donc le même contrôle de l'intérieur de
Google, chaque jour à 09 h 07 (heure de Dakar, soit UTC) :

- elle lit les planifications et les sauvegardes (lecture seule : elle ne
  crée, ne supprime et ne restaure rien) ;
- tout va bien (les deux planifications existent, la dernière sauvegarde a
  moins de 36 h) : rien n'est envoyé, sauf le dimanche, où les Admin reçoivent
  « Sauvegardes : tout va bien ». Si ce petit message cesse d'arriver, c'est le
  contrôle lui-même qu'il faut regarder ;
- sinon (sauvegarde périmée ou absente, planification manquante, ou Google qui
  refuse la lecture) : notification « Sauvegardes : à vérifier » aux appareils
  des comptes Admin, **tous les jours** tant que ça dure, et erreur dans le
  journal de la fonction (console Firebase > Functions > Journaux,
  `verifierSauvegardes`). Si aucun appareil Admin n'a les notifications
  actives, le journal le dit aussi.

**Mise en place, une seule fois.** Donner au compte qui exécute les Cloud
Functions, `671806634534-compute@developer.gserviceaccount.com` (« Compte de
service Compute Engine par défaut », lu sur la fonction `surveillerCommandes`
en ligne), les deux rôles de lecture suivants : page **IAM** de Google Cloud,
crayon à droite de ce compte, **+ Ajouter un autre rôle** (taper
l'identifiant dans le filtre), **Enregistrer**.

- `roles/datastore.backupsViewer` : lire les sauvegardes ;
- `roles/datastore.backupSchedulesViewer` : lire les planifications.

Sans eux, la fonction répond « Lecture des planifications impossible (HTTP
403) » et alerte, au lieu de laisser croire que tout va bien. Pour voir ce que
Google a réellement accordé (lecture seule, rien n'est modifié) : GitHub >
**Actions** > **Sauvegardes Firestore** > **Run workflow**, case
**diagnostic** cochée. Le journal nomme le compte qui exécute les fonctions,
dit pour chacun des deux rôles s'il est « présent » ou « ABSENT », et teste un
par un les droits du compte de déploiement pour l'essai de restauration.

Coût : une tâche Cloud Scheduler en plus (les trois premières par compte de
facturation sont gratuites, 0,10 $ par mois au-delà), une exécution par jour
(dans le quota gratuit des fonctions), notifications gratuites.

## 11. Suivi des plantages (Firebase Crashlytics, Android)

Les plantages et les erreurs imprévues de l'**APK Android** partent vers
Firebase Crashlytics (console Firebase > **Crashlytics**), avec la version de
l'app et le modèle du téléphone. L'app n'y ajoute aucun nom, numéro ni
identifiant de compte (le texte d'une erreur imprévue n'est pas filtré).

- **Couverture** : l'APK Android seulement. Crashlytics n'existe pas pour le
  web : ni le site, ni l'app installée sur l'iPhone (qui est le site) ne sont
  suivis. Pour eux, il faudrait un autre outil (à décider).
- **Dans l'app** : `lib/core/suivi/suivi_plantages.dart`, branché dans
  `main.dart` juste après le démarrage de Firebase. Les erreurs du framework
  Flutter et les erreurs non rattrapées sont transmises (l'affichage habituel de
  l'erreur est conservé) ; les plantages natifs sont captés par le SDK. Actif
  seulement dans une app en version finale (jamais en développement ni en test).
  Une panne de Crashlytics ne peut pas empêcher l'app de démarrer.
- **Vérifier que ça marche** : sur l'APK, Admin > Paramètres > carte « Suivi des
  plantages » > **Tester le suivi** > confirmer. L'app se ferme volontairement ;
  le rapport part dans la minute (Android relance l'app en arrière-plan pour
  l'envoyer) et le plantage « FirebaseCrashlyticsTestCrash » apparaît dans la
  console Crashlytics au bout de quelques minutes. Les plantages « This is a
  test crash » venus d'un appareil « sdk_gphone64_x86_64 » sont ceux de l'essai
  de la CI (ci-dessous) : normaux.
- **Alertes** : les alertes par e-mail de Crashlytics (nouveau plantage,
  régression) se règlent dans la console Firebase.
- **Choix techniques**, à relire avant toute mise à jour d'Android Gradle, de
  Firebase ou de R8 :
  - Pas de plugin Gradle Crashlytics : il ne s'entend pas encore avec Android
    Gradle 9.x (identifiant de build parfois absent) et l'app n'utilise pas
    `google-services.json`. L'identifiant de build exigé par le SDK est fourni
    dans `android/app/src/main/res/values/crashlytics.xml`. Conséquence : les
    erreurs Dart (l'essentiel) restent lisibles, mais les rares plantages
    natifs Java apparaissent obfusqués.
  - Règle R8 `android/app/proguard-rules.pro` : sans elle, R8 retire le
    constructeur des composants Firebase, Crashlytics n'est pas instancié et
    `Firebase.initializeApp` échoue : l'app démarre sans écran.
  - Dépendance `firebase_crashlytics` 4.3.x, la ligne qui va avec
    `firebase_core` 3.x : passer à la 5.x oblige à migrer tout Firebase en 4.x.
- **Essai sur émulateur** (`.github/workflows/essai-android.yml`, script
  `tool/essai_android.sh`) : onglet Actions > **Essai Android** > Run workflow.
  Compile l'app pour un émulateur, la lance, vérifie qu'elle affiche un écran
  sans exception, que Crashlytics s'initialise, qu'un plantage de test est
  capté puis accepté par le serveur de Crashlytics (HTTP 200). Ne publie rien ;
  les résultats sont les annotations du run. À lancer avant de publier toute
  mise à jour qui touche à Firebase, à Gradle, à R8 ou aux dépendances Android :
  la compilation seule ne suffit pas (c'est ce qui a révélé le défaut R8 ci-dessus).
- **À prévoir** : mentionner le suivi des plantages dans la politique de
  confidentialité de l'app (données techniques de plantage, sans identité).
