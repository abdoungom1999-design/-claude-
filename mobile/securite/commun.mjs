// Briques communes aux contrôles de sécurité de la CI (securite/*.mjs).
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const DOSSIER_SECURITE = path.dirname(fileURLToPath(import.meta.url));

/** Exceptions déclarées dans securite/exceptions.json (liste vide si le fichier manque). */
export function chargerExceptions(fichier = path.join(DOSSIER_SECURITE, 'exceptions.json')) {
  try {
    const contenu = JSON.parse(readFileSync(fichier, 'utf8'));
    return Array.isArray(contenu.avis) ? contenu.avis : [];
  } catch {
    return [];
  }
}

function finDeValidite(exception) {
  const fin = new Date(`${exception.jusqu_au}T23:59:59Z`);
  return Number.isNaN(fin.getTime()) ? null : fin;
}

/**
 * Une exception ne vaut que si elle vise cet avis et ce projet, explique
 * pourquoi le risque est accepté (10 caractères au moins) et n'est pas
 * échue : un avis accepté « pour toujours » finirait oublié.
 */
export function exceptionValable(exception, { avis, projet }, aujourdhui = new Date()) {
  if (!exception || exception.avis !== avis) return false;
  if (exception.projet && exception.projet !== '*' && exception.projet !== projet) return false;
  if (typeof exception.raison !== 'string' || exception.raison.trim().length < 10) return false;
  const fin = finDeValidite(exception);
  return fin !== null && fin.getTime() >= aujourdhui.getTime();
}

/** Exception qui viserait cet avis mais dont la date est passée (à signaler). */
export function exceptionEchue(exception, { avis, projet }, aujourdhui = new Date()) {
  if (!exception || exception.avis !== avis) return false;
  if (exception.projet && exception.projet !== '*' && exception.projet !== projet) return false;
  const fin = finDeValidite(exception);
  return fin === null || fin.getTime() < aujourdhui.getTime();
}

const echapperAnnotation = (texte) =>
  String(texte).replace(/%/g, '%25').replace(/\r/g, '%0D').replace(/\n/g, '%0A');

/** Annotations GitHub Actions (visibles dans le résumé du run). */
export const annoncerErreur = (titre, message) =>
  console.log(`::error title=${echapperAnnotation(titre)}::${echapperAnnotation(message)}`);
export const annoncerAvertissement = (titre, message) =>
  console.log(`::warning title=${echapperAnnotation(titre)}::${echapperAnnotation(message)}`);
export const annoncerNotice = (titre, message) =>
  console.log(`::notice title=${echapperAnnotation(titre)}::${echapperAnnotation(message)}`);
