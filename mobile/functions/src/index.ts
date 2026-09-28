import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { setGlobalOptions } from 'firebase-functions/v2';
import { onCall } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import { coordonneesAdresse as coordonneesCore, rechercherAdresses as rechercherCore } from './adresses';
import { creerCourse as creerCourseCore, estimer } from './commandes';
import { calculDistance } from './distances';
import { ClientGoogle } from './google';

// Région la plus proche de Dakar et de Firestore (eur3, voir
// FIREBASE_SETUP.md). À garder identique dans l'app (`FonctionsCloud`).
// maxInstances : plafond de coût en cas d'abus.
setGlobalOptions({ region: 'europe-west1', maxInstances: 10 });

initializeApp();

/** Clé Google Maps Platform (Places + Routes), dans Secret Manager. */
const cleGoogle = defineSecret('GOOGLE_MAPS_API_KEY');
const options = { secrets: [cleGoogle] };

function google(): ClientGoogle | null {
  const cle = cleGoogle.value().trim();
  return cle ? new ClientGoogle(cle) : null;
}

const distance = () => calculDistance(getFirestore(), google(), () => new Date());

/** Prix d'un trajet, sur la distance par la route. */
export const estimerPrix = onCall(options, (requete) =>
  estimer(distance(), requete.auth?.uid, requete.data, new Date()),
);

/** Création d'une course, avec le prix recalculé par le serveur. */
export const creerCourse = onCall(options, (requete) =>
  creerCourseCore(getFirestore(), distance(), requete.auth?.uid, requete.data, new Date()),
);

/** Autocomplétion d'adresses (Google Places). */
export const rechercherAdresses = onCall(options, (requete) =>
  rechercherCore(google(), requete.auth?.uid, requete.data),
);

/** Coordonnées de l'adresse choisie (Google Places). */
export const coordonneesAdresse = onCall(options, (requete) =>
  coordonneesCore(google(), requete.auth?.uid, requete.data),
);
