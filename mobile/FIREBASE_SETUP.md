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
l'émulateur Firestore : `firestore_rules_test/`, 75 cas). Elles
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
- `profils_publics/{uid}` : nom, téléphone et rôle, lisibles par les
  utilisateurs connectés ; `disponible` (chauffeur validé et non
  sanctionné) n'est écrit que par l'Admin.
- `annuaire_telephones` : lecture d'une entrée précise possible avant
  connexion (connexion par téléphone), mais aucun listage possible.
- `courses` : un client ne crée et ne liste que ses propres demandes,
  sans pouvoir s'attribuer un chauffeur ni antidater ; seuls les chauffeurs validés
  et non sanctionnés voient et acceptent les courses en attente.
- `chats` : lecture et écriture réservées aux deux participants, sans
  usurpation d'expéditeur.
- `evaluations` : une par course, laissée par le client d'une course
  terminée, jamais modifiable ; la note moyenne du chauffeur (profil
  public) est mise à jour dans la même écriture et ne peut augmenter que
  de la note donnée.
- `positions_chauffeurs` : position GPS des chauffeurs en ligne, publiée
  par le chauffeur validé lui-même, lisible par l'Admin (carte "Courses
  en direct") et par le client uniquement pendant SA course avec ce
  chauffeur (suivi d'approche) ; effacée quand il passe hors ligne.
- Seul le chauffeur attribué fait avancer sa course (client à bord, puis
  course terminée), sans pouvoir sauter d'étape ni toucher au prix. Il
  peut aussi l'annuler avec un motif (client introuvable, panne, autre),
  montré au client.
- Finances : à la fin d'une course, la commission de la plateforme (15 %
  du prix) est figée et vérifiée par les règles. Les règlements entre un
  chauffeur et la plateforme (`reglements`) ne sont saisis que par
  l'Admin ; le temps en ligne (`temps_en_ligne`) ne peut augmenter que
  d'une minute par minute.
- Toute autre collection : refusée.

### Limites connues (à traiter avant le lancement)

- Suivi GPS : l'app étant une application web, le navigateur coupe la
  géolocalisation quand l'écran du chauffeur se verrouille ou que
  l'onglet passe en arrière-plan. L'app garde l'écran allumé tant que le
  chauffeur est en ligne, et la carte Admin affiche "Signal perdu" au
  bout de 2 minutes sans nouvelle. Un vrai suivi en arrière-plan exige
  l'application Android native.

- Le prix et l'identifiant de paiement d'une course sont fournis par
  l'app cliente : les règles vérifient la forme de la demande, pas le
  montant. La commission (15 % de ce prix) en dépend donc aussi. Un calcul et une vérification de paiement côté serveur
  (Cloud Functions) restent nécessaires.
- Un numéro de téléphone n'est pas garanti unique : si quelqu'un
  revendique en premier le numéro d'un autre dans l'annuaire, ce dernier
  ne pourra se connecter que par email (aucun accès à son compte n'est
  donné pour autant).
