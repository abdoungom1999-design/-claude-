# Distribuer Sprint aux chauffeurs (phase de test)

## Android : l'APK

À chaque push, GitHub Actions compile l'APK et le publie toujours au même
lien, à envoyer tel quel sur WhatsApp :

https://github.com/abdoungom1999-design/-claude-/releases/download/sprint-android/sprint.apk

Page de la version (numéro, date, commit) :
https://github.com/abdoungom1999-design/-claude-/releases/tag/sprint-android

Installation par le chauffeur :

1. Ouvrir le lien (ou le fichier reçu sur WhatsApp) : « Télécharger ».
2. Ouvrir `sprint.apk`. La première fois, Android demande d'autoriser
   l'installation depuis Chrome (ou WhatsApp) : **Paramètres** >
   **Autoriser cette source**, puis revenir et **Installer**.
3. Si Play Protect affiche « Application inconnue » : **Plus de détails**
   > **Installer quand même** (normal pour une app hors Play Store).
4. Au premier passage « En ligne » : autoriser la localisation
   (**Lorsque vous utilisez l'application**) et les notifications.

Mises à jour : renvoyer le même lien ; la nouvelle version s'installe
par-dessus l'ancienne, sans perdre la connexion. Toutes les versions sont
signées avec la même clé, créée par la CI et gardée dans Google Secret
Manager (`ANDROID_SIGNATURE`) : ne jamais la supprimer, sinon les
chauffeurs devront désinstaller l'app avant la mise à jour suivante.

Ce que l'APK apporte par rapport au site :

- le GPS continue écran verrouillé tant que le chauffeur est en ligne
  (notification permanente « Sprint : vous êtes en ligne ») ;
- alerte « Nouvelle course » avec le son de notification du téléphone
  et des vibrations.

Limites connues de l'APK de test :

- carte OpenStreetMap (la clé Google du fond de carte est réservée au
  site) ; recherche d'adresses et prix restent fournis par Google, côté
  serveur ;
- paiement : la page de paiement s'ouvre dans le navigateur ; revenir
  ensuite dans l'app.

## iPhone : le site installé sur l'écran d'accueil

Apple n'autorise pas les APK ni l'installation d'un site en un clic : le
chauffeur ajoute le site à son écran d'accueil, une fois.

1. Ouvrir https://abdoungom1999-design.github.io/-claude-/ dans **Safari**.
2. Toucher **Partager** (carré avec une flèche), puis **« Sur l'écran
   d'accueil »**, puis **Ajouter**. Un bandeau rappelle ce geste sur
   iPhone tant que Sprint n'est pas installé.
3. Ouvrir Sprint depuis l'icône : plein écran, sans barre Safari.

Limites sur iPhone : le GPS s'arrête écran verrouillé (l'écran reste
allumé tant que le chauffeur est en ligne) ; pas de vibration, et le
bouton silencieux coupe l'alerte sonore.
