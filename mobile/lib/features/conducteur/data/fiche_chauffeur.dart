import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../auth/data/auth_repository.dart';

/// Moto du chauffeur (Sprint est 100 % moto) : marque, modèle, couleur.
class MotoChauffeur {
  const MotoChauffeur({this.marque = '', this.modele = '', this.couleur = ''});

  final String marque;
  final String modele;
  final String couleur;

  /// « Bajaj Boxer 125 Noir » ; vide si rien n'est renseigné.
  String get description => [marque, modele, couleur].map((e) => e.trim()).where((e) => e.isNotEmpty).join(' ');

  bool get complete => marque.trim().isNotEmpty && modele.trim().isNotEmpty && couleur.trim().isNotEmpty;

  Map<String, String> versFirestore() => {'marque': marque.trim(), 'modele': modele.trim(), 'couleur': couleur.trim()};

  static MotoChauffeur depuis(Object? valeur) {
    if (valeur is! Map) return const MotoChauffeur();
    String texte(String cle) => (valeur[cle] as String?)?.trim() ?? '';
    return MotoChauffeur(marque: texte('marque'), modele: texte('modele'), couleur: texte('couleur'));
  }

  @override
  bool operator ==(Object other) =>
      other is MotoChauffeur &&
      other.marque.trim() == marque.trim() &&
      other.modele.trim() == modele.trim() &&
      other.couleur.trim() == couleur.trim();

  @override
  int get hashCode => Object.hash(marque.trim(), modele.trim(), couleur.trim());
}

/// Demande de modification d'un chauffeur validé (identité, moto, plaque),
/// en attente de vérification par l'Admin avec ses pièces.
class ModificationDemandee {
  const ModificationDemandee({
    required this.prenom,
    required this.nomDeFamille,
    required this.moto,
    required this.plaque,
    this.demandeLe,
  });

  final String prenom;
  final String nomDeFamille;
  final MotoChauffeur moto;
  final String plaque;
  final DateTime? demandeLe;

  String get nomComplet => nomCompletDe(prenom, nomDeFamille);

  /// « Bajaj Boxer 125 Noir - DK-1234-AB ».
  String get motoEtPlaque => [moto.description, plaque].where((v) => v.trim().isNotEmpty).join(' - ');

  static ModificationDemandee? depuis(Object? valeur) {
    if (valeur is! Map) return null;
    String texte(String cle) => (valeur[cle] as String?)?.trim() ?? '';
    final demandeLe = valeur['demandeLe'];
    return ModificationDemandee(
      prenom: texte('prenom'),
      nomDeFamille: texte('nomDeFamille'),
      moto: MotoChauffeur(marque: texte('marque'), modele: texte('modele'), couleur: texte('couleur')),
      plaque: texte('plaque'),
      demandeLe: demandeLe is Timestamp ? demandeLe.toDate() : null,
    );
  }
}

/// Fiche du chauffeur telle que lue dans `users/{uid}` : identité (prénom et
/// nom, comme sur ses pièces), contact, moto et plaque, état du dossier.
/// Les comptes créés avant le prénom et le nom séparés n'ont que `nom`.
class FicheChauffeur {
  const FicheChauffeur({
    this.prenom = '',
    this.nomDeFamille = '',
    this.nomEnregistre = '',
    this.telephone = '',
    this.email = '',
    this.moto = const MotoChauffeur(),
    this.vehiculeEnregistre = '',
    this.plaque = '',
    this.statutValidation,
    this.photo,
    this.modificationDemandee,
    this.modificationRefuseeLe,
  });

  final String prenom;
  final String nomDeFamille;

  /// Champ `nom` (« Prénom Nom ») : seul présent sur les anciens comptes.
  final String nomEnregistre;
  final String telephone;
  final String email;
  final MotoChauffeur moto;

  /// Champ `vehiculeId` : seul présent sur les anciens comptes (« Marque Modèle (Année) »).
  final String vehiculeEnregistre;
  final String plaque;
  final String? statutValidation;
  final String? photo;
  final ModificationDemandee? modificationDemandee;

  /// Dernière demande refusée par l'Admin (à corriger ou voir avec le support).
  final DateTime? modificationRefuseeLe;

  bool get estValide => statutValidation == 'valide';

  /// Vrai prénom et nom, en majuscules initiales : « Moussa Diop ».
  String get nomComplet {
    final structure = nomCompletDe(prenom, nomDeFamille);
    return structure.isNotEmpty ? structure : capitaliserNom(nomEnregistre);
  }

  /// Prénom et nom séparés, déduits de l'ancien `nom` si besoin (pour
  /// préremplir la modification).
  (String, String) get prenomEtNom {
    if (prenom.isNotEmpty || nomDeFamille.isNotEmpty) return (capitaliserNom(prenom), capitaliserNom(nomDeFamille));
    final mots = nomEnregistre.trim().split(RegExp(r'\s+')).where((m) => m.isNotEmpty).toList();
    if (mots.isEmpty) return ('', '');
    return (capitaliserNom(mots.first), capitaliserNom(mots.skip(1).join(' ')));
  }

  /// « Bajaj Boxer 125 Noir » (ou l'ancien libellé).
  String get descriptionMoto => moto.description.isNotEmpty ? moto.description : vehiculeEnregistre.trim();

  /// « Bajaj Boxer 125 Noir - DK-1234-AB » ; vide si rien n'est renseigné.
  String get motoEtPlaque => [descriptionMoto, plaque].where((v) => v.trim().isNotEmpty).join(' - ');

  static FicheChauffeur depuis(Map<String, dynamic>? donnees) {
    if (donnees == null) return const FicheChauffeur();
    String texte(String cle) => (donnees[cle] as String?)?.trim() ?? '';
    final documents = donnees['documents'];
    final refusee = donnees['modificationRefuseeLe'];
    return FicheChauffeur(
      prenom: texte('prenom'),
      nomDeFamille: texte('nomDeFamille'),
      nomEnregistre: texte('nom'),
      telephone: texte('telephone'),
      email: texte('email'),
      moto: MotoChauffeur.depuis(donnees['moto']),
      vehiculeEnregistre: texte('vehiculeId'),
      plaque: texte('plaqueImmatriculation'),
      statutValidation: donnees['statutValidation'] as String?,
      photo: documents is Map ? documents['photoProfil'] as String? : null,
      modificationDemandee: ModificationDemandee.depuis(donnees['modificationDemandee']),
      modificationRefuseeLe: refusee is Timestamp ? refusee.toDate() : null,
    );
  }
}

/// « moussa » → « Moussa », « N'DIAYE » → « N'Diaye », « ba-sow » → « Ba-Sow » ;
/// un nom déjà écrit en casse mixte (« McDonald ») est gardé tel quel.
String capitaliserNom(String saisie) {
  final nettoye = saisie.trim().replaceAll(RegExp(r'\s+'), ' ');
  return nettoye.split(' ').map((mot) {
    if (mot.isEmpty) return mot;
    final casseUnique = mot == mot.toLowerCase() || mot == mot.toUpperCase();
    if (!casseUnique) return mot;
    final minuscule = mot.toLowerCase();
    final buffer = StringBuffer();
    var debut = true;
    for (final rune in minuscule.runes) {
      final car = String.fromCharCode(rune);
      buffer.write(debut ? car.toUpperCase() : car);
      debut = car == '-' || car == "'" || car == '’';
    }
    return buffer.toString();
  }).join(' ');
}

/// « Prénom Nom » capitalisés ; vide si les deux le sont.
String nomCompletDe(String prenom, String nomDeFamille) =>
    [capitaliserNom(prenom), capitaliserNom(nomDeFamille)].where((v) => v.isNotEmpty).join(' ');

/// Plaque en majuscules, espaces réduits : « dk 1234 ab » → « DK 1234 AB ».
String normaliserPlaque(String saisie) => saisie.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();

/// Prénom ou nom : 2 à 40 caractères, lettres (accents compris), espaces,
/// tirets et apostrophes. `null` si valide, sinon le message.
String? validerNomPropre(String? saisie, {required String champ}) {
  final v = (saisie ?? '').trim();
  if (v.length < 2) return '$champ requis (2 lettres au moins).';
  if (v.length > 40) return '$champ trop long (40 caractères au plus).';
  if (!RegExp(r"^[A-Za-zÀ-ÖØ-öø-ÿ][A-Za-zÀ-ÖØ-öø-ÿ '’-]*$").hasMatch(v)) {
    return '$champ : lettres, espaces, tirets et apostrophes seulement.';
  }
  return null;
}

/// Marque, modèle ou couleur : 1 à 30 caractères.
String? validerChampMoto(String? saisie, {required String champ}) {
  final v = (saisie ?? '').trim();
  if (v.isEmpty) return '$champ requis.';
  if (v.length > 30) return '$champ trop long (30 caractères au plus).';
  return null;
}

/// Plaque : 4 à 15 caractères, lettres, chiffres, espaces et tirets.
String? validerPlaque(String? saisie) {
  final v = normaliserPlaque(saisie ?? '');
  if (v.length < 4 || v.length > 15 || !RegExp(r'^[A-Z0-9][A-Z0-9 -]*$').hasMatch(v)) {
    return 'Plaque invalide (ex : DK-1234-AB).';
  }
  return null;
}

/// Ce qu'a produit l'enregistrement de la fiche.
enum ResultatFiche {
  /// Rien n'a changé.
  inchange,

  /// Enregistré tel quel (téléphone, ou dossier pas encore validé).
  enregistre,

  /// Identité ou moto envoyées à Sprint pour vérification (dossier validé),
  /// le téléphone éventuel étant déjà enregistré.
  aVerifier,
}

/// Ce qu'il faut écrire pour une modification de la fiche (logique pure).
class PlanFiche {
  const PlanFiche({
    required this.resultat,
    this.ecritureDirecte,
    this.nomDirect,
    this.telephone,
    this.demande,
  });

  final ResultatFiche resultat;

  /// Dossier pas encore validé : champs écrits tels quels dans `users/{uid}`.
  final Map<String, Object>? ecritureDirecte;

  /// Dossier pas encore validé : nom (« Prénom Nom ») à écrire et publier.
  final String? nomDirect;

  /// Nouveau téléphone, s'il a changé (écrit aussitôt dans tous les cas).
  final String? telephone;

  /// Dossier validé : demande à vérifier par l'Admin (sans sa date, posée par le serveur).
  final Map<String, String>? demande;
}

/// Décide quoi écrire : téléphone aussitôt ; identité et moto aussitôt tant
/// que le dossier n'est pas validé, sinon en demande vérifiée par l'Admin.
/// La comparaison se fait avec ce que montrait le formulaire (ancien compte :
/// prénom et nom déduits de `nom`, moto à compléter).
PlanFiche planifierFiche({
  required FicheChauffeur avant,
  required String prenom,
  required String nomDeFamille,
  required String telephone,
  required MotoChauffeur moto,
  required String plaque,
}) {
  final (prenomAvant, nomAvant) = avant.prenomEtNom;
  final p = capitaliserNom(prenom);
  final n = capitaliserNom(nomDeFamille);
  final pl = normaliserPlaque(plaque);
  final m = MotoChauffeur(marque: moto.marque.trim(), modele: moto.modele.trim(), couleur: moto.couleur.trim());
  final identiteOuMoto = p != prenomAvant || n != nomAvant || m != avant.moto || pl != avant.plaque;
  final tel = telephone.trim();
  final nouveauTelephone = tel != avant.telephone ? tel : null;
  if (!identiteOuMoto) {
    return PlanFiche(
      resultat: nouveauTelephone == null ? ResultatFiche.inchange : ResultatFiche.enregistre,
      telephone: nouveauTelephone,
    );
  }
  if (!avant.estValide) {
    return PlanFiche(
      resultat: ResultatFiche.enregistre,
      ecritureDirecte: {
        'prenom': p,
        'nomDeFamille': n,
        'moto': m.versFirestore(),
        'vehiculeId': m.description,
        'plaqueImmatriculation': pl,
      },
      nomDirect: nomCompletDe(p, n),
      telephone: nouveauTelephone,
    );
  }
  return PlanFiche(
    resultat: ResultatFiche.aVerifier,
    telephone: nouveauTelephone,
    demande: {
      'prenom': p,
      'nomDeFamille': n,
      'marque': m.marque,
      'modele': m.modele,
      'couleur': m.couleur,
      'plaque': pl,
    },
  );
}

/// Modification de la fiche par le chauffeur (`users/{uid}`, règles
/// Firestore), selon [planifierFiche].
class FicheChauffeurService {
  FicheChauffeurService({FirebaseFirestore? firestore, AuthRepository? authRepository})
      : _firestoreInjecte = firestore,
        _authInjecte = authRepository;

  final FirebaseFirestore? _firestoreInjecte;
  final AuthRepository? _authInjecte;
  FirebaseFirestore get _firestore => _firestoreInjecte ?? FirebaseFirestore.instance;
  AuthRepository get _auth => _authInjecte ?? AuthRepository();

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  Future<ResultatFiche> enregistrer({
    required FicheChauffeur avant,
    required String prenom,
    required String nomDeFamille,
    required String telephone,
    required MotoChauffeur moto,
    required String plaque,
  }) async {
    final plan = planifierFiche(
      avant: avant,
      prenom: prenom,
      nomDeFamille: nomDeFamille,
      telephone: telephone,
      moto: moto,
      plaque: plaque,
    );
    if (plan.resultat == ResultatFiche.inchange) return plan.resultat;
    final uid = _uid;
    if (uid == null) throw StateError('Aucun chauffeur connecté.');
    final users = _firestore.collection('users').doc(uid);
    if (plan.ecritureDirecte case final champs?) {
      await users.update(champs);
      // Nom et téléphone, puis profil public et annuaire de connexion.
      await _auth.mettreAJourProfil(nom: plan.nomDirect!, telephone: plan.telephone ?? avant.telephone);
      return plan.resultat;
    }
    if (plan.telephone case final tel?) await _auth.mettreAJourTelephone(tel);
    if (plan.demande case final demande?) {
      await users.update({
        'modificationDemandee': {...demande, 'demandeLe': FieldValue.serverTimestamp()},
      });
    }
    return plan.resultat;
  }

  /// Retire la demande en attente (le chauffeur change d'avis).
  Future<void> annulerDemande() async {
    final uid = _uid;
    if (uid == null) return;
    await _firestore.collection('users').doc(uid).update({'modificationDemandee': FieldValue.delete()});
  }
}
