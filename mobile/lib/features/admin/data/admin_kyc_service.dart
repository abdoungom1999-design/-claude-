import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/models/statut_compte.dart';
import '../../auth/data/auth_repository.dart';
import '../../conducteur/data/position_chauffeur_service.dart';

/// Profil Conducteur tel que lu directement depuis Firestore
/// (`users/{uid}`, `role == 'conducteur'`), pour la supervision KYC
/// côté Admin (voir [AdminKycService]). Distinct de [ConducteurAdmin]
/// (`admin_repository.dart`), qui reste alimenté par [DemoData] tant
/// qu'[AdminRepository] n'est pas migré — celui-ci lit la vraie base.
class ConducteurKycAdmin {
  ConducteurKycAdmin({
    required this.id,
    required this.nom,
    required this.telephone,
    required this.vehiculeId,
    required this.plaqueImmatriculation,
    required this.statutValidation,
    required this.statutCompte,
    required this.documents,
  });

  final String id;
  final String nom;
  final String telephone;
  final String? vehiculeId;
  final String? plaqueImmatriculation;

  /// `null` (aucun document jamais envoyé), `'en_attente'`, `'valide'`
  /// ou `'rejete'`.
  final String? statutValidation;

  /// Modération Admin, indépendante du KYC : `'actif'` (défaut, aussi
  /// pour les comptes créés avant ce champ), `'suspendu'` ou `'banni'`.
  final String statutCompte;

  bool get estBloque => StatutCompte.estBloque(statutCompte);

  /// Clés possibles : `permis`, `carteGrise`, `attestationVtc`,
  /// `photoProfil` — chacune une URL Firebase Storage ou une data URI
  /// Base64 (voir `ConducteurDocumentsService`), absente si non envoyée.
  final Map<String, dynamic> documents;

  bool get aDesDocuments => documents.keys.any(
        (cle) => cle != 'photoProfil' && (documents[cle] as String?)?.isNotEmpty == true,
      );

  factory ConducteurKycAdmin.depuisFirestore(String id, Map<String, dynamic> donnees) {
    return ConducteurKycAdmin(
      id: id,
      nom: (donnees['nom'] as String?)?.trim().isNotEmpty == true
          ? donnees['nom'] as String
          : 'Chauffeur sans nom',
      telephone: (donnees['telephone'] as String?) ?? '',
      vehiculeId: donnees['vehiculeId'] as String?,
      plaqueImmatriculation: donnees['plaqueImmatriculation'] as String?,
      statutValidation: donnees['statutValidation'] as String?,
      statutCompte: (donnees['statutCompte'] as String?) ?? StatutCompte.actif,
      documents: (donnees['documents'] as Map<String, dynamic>?) ?? {},
    );
  }
}

/// Supervision KYC côté Admin : liste en temps réel des chauffeurs
/// (collection Firestore `users`, `role == 'conducteur'`) et
/// approbation/rejet de leur dossier. Écrit directement dans le même
/// document que [ConducteurDocumentsService] (téléversement) et que le
/// "Gardien" de [ConducteurShellPage] (lecture de `statutValidation`) :
/// aucun nouveau schéma, cette classe ne fait que lire/écrire les
/// champs déjà en place.
class AdminKycService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  /// Un seul filtre d'égalité (`role`), sans tri : ne nécessite pas
  /// d'index composite Firestore, contrairement à `courses`/`chats`
  /// ailleurs dans l'app.
  Stream<List<ConducteurKycAdmin>> streamConducteurs() {
    return _firestore
        .collection('users')
        .where('role', isEqualTo: 'conducteur')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ConducteurKycAdmin.depuisFirestore(doc.id, doc.data()))
              .toList(),
        );
  }

  /// Suivi en temps réel d'un seul chauffeur, pour que le Dossier
  /// Chauffeur reflète immédiatement les décisions prises dessus.
  Stream<ConducteurKycAdmin?> streamConducteur(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      final donnees = doc.data();
      return donnees == null ? null : ConducteurKycAdmin.depuisFirestore(doc.id, donnees);
    });
  }

  /// Suspend, bannit ou réactive un compte ([StatutCompte]). Le chauffeur
  /// connecté est éjecté en direct (voir [ConducteurShellPage]).
  Future<void> definirStatutCompte(String uid, String statut) async {
    await _firestore.collection('users').doc(uid).update({'statutCompte': statut});
    await _publierProfilPublic(uid);
    // Retire aussitôt le chauffeur sanctionné de la carte en direct.
    if (StatutCompte.estBloque(statut)) {
      await _firestore.collection(PositionChauffeurService.collection).doc(uid).delete();
    }
  }

  /// Approuve le dossier : `statutValidation` passe à `'valide'`.
  /// Met aussi à jour `estValide` (booléen legacy toujours écrit à
  /// l'inscription, voir [AuthRepository.inscrireConducteur]) pour
  /// rester cohérent, même si le "Gardien" ne se base plus que sur
  /// `statutValidation` en Firebase réel.
  Future<void> approuverConducteur(String uid) async {
    await _firestore.collection('users').doc(uid).update({
      'statutValidation': 'valide',
      'estValide': true,
    });
    await _publierProfilPublic(uid);
  }

  /// Rejette le dossier : `statutValidation` passe à `'rejete'`. Côté
  /// chauffeur, le "Gardien" de [ConducteurShellPage] ne reconnaît que
  /// `'valide'` et `'en_attente'` : `'rejete'` retombe donc sur
  /// [ConducteurKYCPage] (ses documents déjà envoyés y restent
  /// visibles), lui permettant de corriger et resoumettre son dossier.
  Future<void> rejeterConducteur(String uid) async {
    await _firestore.collection('users').doc(uid).update({
      'statutValidation': 'rejete',
      'estValide': false,
    });
    await _publierProfilPublic(uid);
  }

  /// Rattrapage des comptes créés avant les règles de sécurité : publie
  /// pour chaque client et chauffeur son profil public (avec la
  /// disponibilité des chauffeurs) et son entrée d'annuaire téléphone,
  /// que l'utilisateur ne publie lui-même qu'à sa prochaine connexion
  /// (voir `AuthRepository`). Idempotent, lancé à l'ouverture du tableau
  /// de bord Admin. Retourne le nombre de comptes traités.
  Future<int> synchroniserProfilsPublics() async {
    final utilisateurs = await _firestore.collection('users').get();
    var traites = 0;
    for (final doc in utilisateurs.docs) {
      final donnees = doc.data();
      final role = donnees['role'];
      if (role != 'client' && role != 'conducteur') continue;
      await _publierProfilPublic(doc.id, donnees);
      final email = donnees['email'];
      final cle = AuthRepository.cleAnnuaire(role as String, donnees['telephone'] as String? ?? '');
      if (cle != null && email is String) {
        final entree = _firestore.collection('annuaire_telephones').doc(cle);
        // Ne jamais réattribuer un numéro déjà revendiqué par un autre compte.
        final existante = (await entree.get()).data();
        if (existante == null || existante['uid'] == doc.id) {
          await entree.set({'uid': doc.id, 'email': email});
        }
      }
      traites++;
    }
    return traites;
  }

  /// Recopie nom, téléphone et rôle de `users/{uid}` (privé) vers
  /// `profils_publics/{uid}`, ainsi que `disponible` pour un chauffeur :
  /// dossier validé et compte ni suspendu ni banni. Seul l'Admin peut
  /// écrire `disponible` (voir `firestore.rules`).
  Future<void> _publierProfilPublic(String uid, [Map<String, dynamic>? donnees]) async {
    donnees ??= (await _firestore.collection('users').doc(uid).get()).data();
    if (donnees == null) return;
    final role = donnees['role'];
    await _firestore.collection('profils_publics').doc(uid).set({
      'nom': donnees['nom'] as String? ?? '',
      'telephone': donnees['telephone'] as String? ?? '',
      'role': role,
      if (role == 'conducteur')
        'disponible': donnees['statutValidation'] == 'valide' &&
            !StatutCompte.estBloque(donnees['statutCompte'] as String?),
    }, SetOptions(merge: true));
  }
}
