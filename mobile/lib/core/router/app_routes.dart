class AppRoutes {
  AppRoutes._();

  static const String welcome = '/';
  static const String home = '/accueil';
  static const String activiteTab = '/accueil/activite';
  static const String messagesTab = '/accueil/messages';
  static const String compteTab = '/accueil/compte';
  static const String clientPassager = '/client/passager';
  static const String clientColis = '/client/colis';
  static const String clientLogin = '/client/login';
  static const String clientRegister = '/client/inscription';
  static const String espacePro = '/espace-pro';
  static const String conducteur = '/conducteur';
  static const String conducteurLogin = '/conducteur/connexion';
  static const String conducteurRegister = '/conducteur/inscription';
  static const String admin = '/admin';
  static const String adminLogin = '/admin/connexion';

  /// Retour de Max It après un paiement Orange Money (adresse donnée à Orange
  /// par le serveur : `URL_RETOUR_PAIEMENT`, functions/src/index.ts).
  static const String retourPaiement = '/paiement/retour';
}
