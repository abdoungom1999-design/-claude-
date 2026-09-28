import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { setGlobalOptions } from 'firebase-functions/v2';
import { onCall } from 'firebase-functions/v2/https';
import { creerCourse as creerCourseCore, estimer } from './commandes';

// Région la plus proche de Dakar et de Firestore (eur3, voir
// FIREBASE_SETUP.md). À garder identique dans l'app (`CloudFunctions`).
// maxInstances : plafond de coût en cas d'abus.
setGlobalOptions({ region: 'europe-west1', maxInstances: 10 });

initializeApp();

/** Prix d'un trajet, calculé par le serveur à partir des coordonnées. */
export const estimerPrix = onCall((requete) => estimer(requete.auth?.uid, requete.data, new Date()));

/** Création d'une course, avec le prix recalculé par le serveur. */
export const creerCourse = onCall((requete) =>
  creerCourseCore(getFirestore(), requete.auth?.uid, requete.data, new Date()),
);
