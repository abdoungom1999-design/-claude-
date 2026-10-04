import { randomUUID } from 'node:crypto';
import { FieldValue, Timestamp, type Firestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { HttpsError } from 'firebase-functions/v2/https';
import { verifierAdmin } from './admin';

/**
 * Migration des pièces KYC des chauffeurs (permis, carte grise, attestation
 * VTC, photo de profil) du repli « image Base64 dans Firestore » vers
 * Firebase Storage.
 *
 * Les documents déjà dans Storage (valeur `https://…`) ne sont jamais
 * touchés. Chaque document Base64 est : décodé, envoyé dans Storage à
 * l'emplacement attendu par l'app (`kyc_documents/{uid}/{cle}.jpg`), puis
 * remplacé dans `users/{uid}.documents.{cle}` par son URL de téléchargement
 * — c'est ce remplacement qui supprime l'image encodée de Firestore. Le
 * remplacement n'a lieu que si la valeur n'a pas changé entre-temps (un
 * chauffeur qui renvoie une pièce pendant la migration garde la sienne).
 */

export const CLES_DOCUMENTS = ['permis', 'carteGrise', 'attestationVtc', 'photoProfil'] as const;

/** Même plafond que les règles Storage (`storage.rules`). */
export const TAILLE_MAX_OCTETS = 5 * 1024 * 1024;

/** Chauffeurs traités par appel : l'Admin relance jusqu'à « restants : 0 ». */
export const LOT_CHAUFFEURS = 10;

/** Accès au bucket Storage, remplaçable dans les tests. */
export interface StockageKyc {
  /** Écrit le fichier avec son jeton de téléchargement. */
  enregistrer(chemin: string, octets: Buffer, typeMime: string, jeton: string): Promise<void>;
  /** Même forme que `getDownloadURL()` côté client. */
  urlTelechargement(chemin: string, jeton: string): string;
}

/** Bucket par défaut du projet (celui que l'app utilise côté client). */
export class StockageFirebase implements StockageKyc {
  private nomBucket(): string {
    const configuration = JSON.parse(process.env.FIREBASE_CONFIG ?? '{}') as { storageBucket?: string; projectId?: string };
    const projet = process.env.GCLOUD_PROJECT ?? configuration.projectId;
    return process.env.STORAGE_BUCKET ?? configuration.storageBucket ?? `${projet}.firebasestorage.app`;
  }

  async enregistrer(chemin: string, octets: Buffer, typeMime: string, jeton: string): Promise<void> {
    await getStorage()
      .bucket(this.nomBucket())
      .file(chemin)
      .save(octets, {
        resumable: false,
        contentType: typeMime,
        metadata: { metadata: { firebaseStorageDownloadTokens: jeton } },
      });
  }

  urlTelechargement(chemin: string, jeton: string): string {
    return `https://firebasestorage.googleapis.com/v0/b/${this.nomBucket()}/o/${encodeURIComponent(chemin)}?alt=media&token=${jeton}`;
  }
}

export interface DocumentDecode {
  octets: Buffer;
  typeMime: string;
}

/** Décode une image `data:image/…;base64,…`, ou `null` si la valeur n'en est pas une. */
export function decoderDataUri(valeur: unknown): DocumentDecode | null {
  if (typeof valeur !== 'string') return null;
  const m = /^data:(image\/[a-z0-9.+-]+);base64,([A-Za-z0-9+/=\s]+)$/i.exec(valeur);
  if (!m) return null;
  const octets = Buffer.from(m[2].replace(/\s/g, ''), 'base64');
  return octets.length === 0 ? null : { octets, typeMime: m[1].toLowerCase() };
}

export function cheminDocument(uid: string, cle: string): string {
  return `kyc_documents/${uid}/${cle}.jpg`;
}

/** Documents encore en Base64 d'un profil : clé -> valeur d'origine. */
export function documentsBase64(profil: Record<string, unknown>): Record<string, string> {
  const documents = profil.documents;
  const trouves: Record<string, string> = {};
  if (typeof documents !== 'object' || documents === null) return trouves;
  for (const cle of CLES_DOCUMENTS) {
    const valeur = (documents as Record<string, unknown>)[cle];
    if (typeof valeur === 'string' && valeur.startsWith('data:')) trouves[cle] = valeur;
  }
  return trouves;
}

export interface BilanMigration {
  /** Documents encore en Base64 avant l'appel. */
  documentsABMigrer: number;
  chauffeursConcernes: number;
  /** Documents déplacés dans Storage par cet appel. */
  migres: number;
  /** Documents illisibles ou trop gros, laissés tels quels. */
  ignores: number;
  /** Documents encore en Base64 après l'appel. */
  restants: number;
  apercu: boolean;
}

/**
 * Callable `migrerDocumentsKyc` (Admin). `apercu: true` : compte seulement,
 * sans rien écrire (ne demande pas que Storage soit activé).
 */
export async function migrerDocumentsKyc(
  db: Firestore,
  stockage: StockageKyc,
  uid: string | undefined,
  donnees: unknown,
  maintenant: Date,
  genererJeton: () => string = randomUUID,
): Promise<BilanMigration> {
  const adminId = await verifierAdmin(db, uid);
  const d = (typeof donnees === 'object' && donnees !== null ? donnees : {}) as Record<string, unknown>;
  const apercu = d.apercu === true;

  // Un seul filtre d'égalité : pas d'index composite.
  const chauffeurs = await db.collection('users').where('role', '==', 'conducteur').get();
  const concernes = chauffeurs.docs
    .map((doc) => ({ ref: doc.ref, uid: doc.id, documents: documentsBase64(doc.data()) }))
    .filter((c) => Object.keys(c.documents).length > 0);
  const total = concernes.reduce((n, c) => n + Object.keys(c.documents).length, 0);

  const bilan: BilanMigration = {
    documentsABMigrer: total,
    chauffeursConcernes: concernes.length,
    migres: 0,
    ignores: 0,
    restants: total,
    apercu,
  };
  if (apercu || total === 0) return bilan;

  for (const chauffeur of concernes.slice(0, LOT_CHAUFFEURS)) {
    for (const [cle, valeur] of Object.entries(chauffeur.documents)) {
      const decode = decoderDataUri(valeur);
      if (decode === null || decode.octets.length > TAILLE_MAX_OCTETS) {
        bilan.ignores++;
        continue;
      }
      const chemin = cheminDocument(chauffeur.uid, cle);
      const jeton = genererJeton();
      try {
        await stockage.enregistrer(chemin, decode.octets, decode.typeMime, jeton);
      } catch (e) {
        // Storage absent ou refusé : rien n'a été modifié dans Firestore.
        throw new HttpsError(
          'failed-precondition',
          "Firebase Storage n'est pas utilisable (activé dans la Console ? règles publiées ?) : aucune pièce n'a été modifiée.",
          String(e),
        );
      }
      const remplace = await db.runTransaction(async (tx) => {
        const actuel = await tx.get(chauffeur.ref);
        if (actuel.get(`documents.${cle}`) !== valeur) return false;
        tx.update(chauffeur.ref, { [`documents.${cle}`]: stockage.urlTelechargement(chemin, jeton) });
        return true;
      });
      if (remplace) bilan.migres++;
    }
  }
  bilan.restants = total - bilan.migres;

  await db.collection('journal_admin').add({
    action: 'migration_kyc_storage',
    adminId,
    documentsMigres: bilan.migres,
    documentsIgnores: bilan.ignores,
    restants: bilan.restants,
    le: Timestamp.fromDate(maintenant),
    enregistreLe: FieldValue.serverTimestamp(),
  });
  return bilan;
}
