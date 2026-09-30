// Service worker des notifications push du site (Firebase Cloud Messaging).
//
// Il reçoit les notifications quand le site est fermé ou en arrière-plan
// (navigateur, ou site installé sur l'écran d'accueil de l'iPhone) et les
// affiche : le texte vient du serveur (functions/src/notifications.ts).
// L'appui sur une notification ouvre le lien choisi par le serveur (adresse
// en « # » du site). Site ouvert au premier plan, rien n'est affiché : l'app
// a ses propres alertes.
//
// À servir à la racine du site (Firebase Hosting le fait) : c'est là que
// le plugin firebase_messaging le cherche. La version du SDK doit rester
// celle de firebase_core_web (supportedFirebaseJsSdkVersion).
importScripts('https://www.gstatic.com/firebasejs/11.9.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/11.9.1/firebase-messaging-compat.js');

// Configuration web du projet "Sprint VTC" : identifiants publics par
// conception (les mêmes que dans lib/firebase_options.dart).
firebase.initializeApp({
  apiKey: 'AIzaSyBI86kFD1rOGdm_4q49ytxm7Og9QtB26PM',
  appId: '1:671806634534:web:9c2d22682a5ebcabb6c4e7',
  messagingSenderId: '671806634534',
  projectId: 'sprint-vtc',
  authDomain: 'sprint-vtc.firebaseapp.com',
  storageBucket: 'sprint-vtc.firebasestorage.app',
});

// Sans gestionnaire personnalisé, le SDK affiche lui-même les notifications
// reçues en arrière-plan et gère l'appui (ouverture du lien).
firebase.messaging();
