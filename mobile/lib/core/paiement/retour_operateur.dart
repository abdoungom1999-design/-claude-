import '../notifications/capacites_navigateur.dart';

/// Adresse du site Sprint et paquet de l'APK : ceux du lien d'application
/// Android (`AndroidManifest.xml`, `hebergement/assetlinks.json`) et de
/// l'adresse de retour donnée à Orange par le serveur.
const hoteSprint = 'sprint-vtc.web.app';
const paquetSprint = 'sn.groupesantine.sprint';
const cheminRetourPaiement = '/paiement/retour';

/// Faut-il demander au serveur un paiement « sans retour » ?
///
/// Oui pour le site installé sur l'écran d'accueil d'un iPhone : iOS n'ouvre
/// jamais un lien dans un site installé. Après le paiement, la page de retour
/// s'ouvrirait donc dans Safari, hors de Sprint et sans sa session, à côté
/// d'une invitation à installer l'app (signalé par le client, 12 novembre
/// 2026). Sans adresse de retour, le client reste dans Max It puis revient à
/// Sprint, resté ouvert derrière, qui suit le paiement tout seul.
///
/// Partout ailleurs, l'opérateur ramène le client dans Sprint : l'APK
/// Android (lien d'application), ou l'onglet du navigateur où il a commandé.
bool paiementSansRetour([CapacitesNavigateur? capacites]) {
  final navigateur = capacites ?? lireCapacitesNavigateur();
  return navigateur.iphone && navigateur.ecranAccueil;
}

/// À joindre à une demande de paiement ou de recharge (`creerPaiement`,
/// `creerRecharge`) : rien, ou `sansRetour: true`.
Map<String, Object> optionRetour([CapacitesNavigateur? capacites]) =>
    paiementSansRetour(capacites) ? const {'sansRetour': true} : const {};

final _reference = RegExp(r'^(rch_)?[0-9a-f]{24}$');

/// Lien qui rouvre l'APK Sprint sur la page de retour de paiement, depuis un
/// navigateur Android où cette page s'est ouverte à la place de l'app :
/// intention adressée au seul paquet Sprint (aucune autre app ne peut la
/// capter, et le lien n'a pas besoin d'avoir été vérifié par Android), avec
/// repli sur cette même page si l'APK n'est pas sur le téléphone (`app=0` :
/// la page ne réessaie pas). `null` si la référence ou l'état n'ont pas la
/// forme attendue : rien d'autre n'est jamais transmis à l'APK.
Uri? lienRetourDansLApplication({required String? reference, required String? etat}) {
  if (reference == null || !_reference.hasMatch(reference)) return null;
  if (etat != 'ok' && etat != 'annule') return null;
  final requete = 'ref=$reference&etat=$etat';
  final repli = Uri.encodeComponent('https://$hoteSprint$cheminRetourPaiement?$requete&app=0');
  return Uri.parse(
    'intent://$hoteSprint$cheminRetourPaiement?$requete'
    '#Intent;scheme=https;package=$paquetSprint;S.browser_fallback_url=$repli;end',
  );
}
