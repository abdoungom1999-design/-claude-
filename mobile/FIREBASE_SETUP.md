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
