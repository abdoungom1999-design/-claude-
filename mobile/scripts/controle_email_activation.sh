#!/usr/bin/env bash
# Contrôles AVANT de déployer l'e-mail d'activation des chauffeurs (Resend), lancés depuis mobile/ :
#   - par le job « firebase », juste avant « Déployer les Cloud Functions » (publication) ;
#   - par le job « controle_email », pendant un essai sans publication (rien n'est déployé).
# Fermé (EMAIL_ACTIVATION_CHAUFFEUR = false dans functions/src/email_activation.ts) : rien n'est demandé.
# Ouvert :
#   1. le secret RESEND_API_KEY existe dans Secret Manager, activé, et a la forme d'une clé Resend
#      (valeur lue pour ce contrôle seulement, masquée dans le journal dès sa lecture, jamais affichée) ;
#   2. tant que la fonction activationChauffeurEmail n'existe pas encore (premier déclencheur Firestore du
#      projet, par Eventarc), les droits que l'outil de déploiement Firebase exige alors au niveau du projet
#      (firebase-tools 15, lib/deploy/functions/checkIam.js) : « Demandeur Cloud Run » et « Destinataire
#      d'événements Eventarc » pour le compte de service Compute par défaut, « Créateur de jetons du compte
#      de service » pour l'agent Pub/Sub. Sans eux, le déploiement s'arrête (ou l'envoi échoue en silence).
# Au moindre manque : erreur claire et code de sortie 1, AVANT tout déploiement.
set -uo pipefail

projet=sprint-vtc
region=europe-west1
reglage=functions/src/email_activation.ts

if ! grep -qxF "export const EMAIL_ACTIVATION_CHAUFFEUR: boolean = true;" "$reglage"; then
  echo "E-mail d'activation fermé : aucune clé Resend requise."
  exit 0
fi

# --- 1. La clé Resend -------------------------------------------------------------------------
etat=$(gcloud secrets versions describe latest --secret=RESEND_API_KEY --project=$projet --format='value(state)' 2>/dev/null || true)
if [ "$etat" != ENABLED ]; then
  echo "::error title=Clé Resend manquante::Le secret RESEND_API_KEY est absent ou désactivé dans Secret Manager (projet $projet) : à créer par le client, voir mobile/EMAILS_DOMAINE.md, section 4. Rien n'a été déployé."
  exit 1
fi
valeur=$(gcloud secrets versions access latest --secret=RESEND_API_KEY --project=$projet 2>/dev/null || true)
[ -n "$valeur" ] && echo "::add-mask::$valeur"
if ! printf '%s' "$valeur" | grep -qE '^re_[A-Za-z0-9_]{16,}$'; then
  unset valeur
  echo "::error title=Clé Resend mal collée::RESEND_API_KEY n'a pas la forme d'une clé Resend (re_… sans espace, retour à la ligne ni autre caractère). Ajoutez une nouvelle version du secret avec la clé seule. Rien n'a été déployé."
  exit 1
fi
unset valeur
echo "Clé Resend présente et bien formée."

# --- 2. Droits du premier déclencheur Firestore -------------------------------------------------
if gcloud functions describe activationChauffeurEmail --gen2 --region=$region --project=$projet --format='value(name)' >/dev/null 2>&1; then
  echo "Fonction activationChauffeurEmail déjà en place : droits Eventarc déjà réglés."
  exit 0
fi

numero=$(gcloud projects describe $projet --format='value(projectNumber)' 2>/dev/null || true)
if [ -z "$numero" ]; then
  echo "::error title=Projet illisible::Numéro du projet $projet introuvable (droit resourcemanager.projects.get du compte github-deploy ?). Rien n'a été déployé."
  exit 1
fi
compute="${numero}-compute@developer.gserviceaccount.com"
pubsub="service-${numero}@gcp-sa-pubsub.iam.gserviceaccount.com"
requis="roles/run.invoker serviceAccount:$compute
roles/eventarc.eventReceiver serviceAccount:$compute
roles/iam.serviceAccountTokenCreator serviceAccount:$pubsub"

jeton=$(gcloud auth print-access-token)
droits=$(curl -s -X POST "https://cloudresourcemanager.googleapis.com/v1/projects/$projet:testIamPermissions" \
  -H "Authorization: Bearer $jeton" -H 'Content-Type: application/json' \
  -d '{"permissions":["resourcemanager.projects.getIamPolicy","resourcemanager.projects.setIamPolicy"]}')
peutLire=false; peutModifier=false
echo "$droits" | grep -q '"resourcemanager.projects.getIamPolicy"' && peutLire=true
echo "$droits" | grep -q '"resourcemanager.projects.setIamPolicy"' && peutModifier=true
echo "Compte github-deploy : lecture des droits du projet = $peutLire, modification = $peutModifier."

if [ "$peutLire" != true ]; then
  echo "::error title=Droits Eventarc invérifiables::Premier déclencheur Firestore : le compte github-deploy ne peut pas lire les droits du projet, et l'outil Firebase les ignorerait alors (envoi des e-mails possiblement muet). Ajoutez-lui le rôle « Navigateur » (Browser, lecture seule), puis relancez. Voir mobile/EMAILS_DOMAINE.md, section 4. Rien n'a été déployé."
  exit 1
fi

politique=$(gcloud projects get-iam-policy $projet --format=json)
manquants=""
while read -r role membre; do
  if echo "$politique" | jq -e --arg r "$role" --arg m "$membre" '[.bindings[]? | select(.role == $r) | .members[]? | select(. == $m)] | length > 0' >/dev/null; then
    echo "Présent : $role pour ${membre#serviceAccount:}"
  else
    echo "Absent  : $role pour ${membre#serviceAccount:}"
    manquants="$manquants $role(${membre#serviceAccount:})"
  fi
done <<< "$requis"

if [ -z "$manquants" ]; then
  echo "Droits Eventarc en place : le déploiement de la fonction peut se faire."
  exit 0
fi
if [ "$peutModifier" = true ]; then
  echo "Droits Eventarc manquants :$manquants ; le compte github-deploy peut les ajouter, le déploiement s'en chargera."
  exit 0
fi
echo "::error title=Droits Eventarc manquants::Premier déclencheur Firestore : à ajouter dans Google Cloud > IAM (voir mobile/EMAILS_DOMAINE.md, section 4) :$manquants. Rien n'a été déployé."
exit 1
