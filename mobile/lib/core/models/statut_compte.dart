/// Valeurs du champ Firestore `users/{uid}.statutCompte` : modération
/// Admin, indépendante de la validation KYC. Écrit par le panneau Admin
/// (`AdminKycService`), lu par le "Gardien" de `ConducteurShellPage`.
/// Un compte sans ce champ (créé avant son introduction) est actif.
abstract final class StatutCompte {
  static const actif = 'actif';
  static const suspendu = 'suspendu';
  static const banni = 'banni';

  static bool estBloque(String? statut) => statut == suspendu || statut == banni;
}
