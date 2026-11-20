/// Écran à montrer à l'entrée de l'espace chauffeur, d'après le profil
/// `users/{uid}` du compte connecté (lu sur le serveur).
///
/// Deux cas n'ont rien à faire sur « Complétez votre dossier », car les règles
/// Firestore y refusent l'envoi des pièces (« firestore/permission-denied ») :
/// - [profilAbsent] : le compte de connexion existe, mais son profil n'a
///   jamais été enregistré (inscription interrompue juste après la création
///   du compte, par exemple) ; le chauffeur termine alors son inscription ;
/// - [compteClient] : un compte CLIENT connecté dans l'espace chauffeur ; un
///   même compte ne peut pas être à la fois Client et Chauffeur.
enum EtapeDossierChauffeur { profilAbsent, compteClient, nonEnvoye, enAttente, valide }

EtapeDossierChauffeur etapeDossierChauffeur(Map<String, dynamic>? profil) {
  if (profil == null) return EtapeDossierChauffeur.profilAbsent;
  if (profil['role'] == 'client') return EtapeDossierChauffeur.compteClient;
  return switch (profil['statutValidation']) {
    'valide' => EtapeDossierChauffeur.valide,
    'en_attente' => EtapeDossierChauffeur.enAttente,
    _ => EtapeDossierChauffeur.nonEnvoye,
  };
}
