import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/notifications/carte_notifications.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/onyx_vert.dart';
import '../../../../core/widgets/image_document.dart';
import '../../../../core/widgets/premium_dialog.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../compte/presentation/centre_aide_page.dart';
import '../../data/conducteur_documents_service.dart';
import '../../data/conducteur_repository.dart';
import '../../data/fiche_chauffeur.dart';
import '../modifier_fiche_chauffeur_page.dart';

/// Onglet Compte : identité du conducteur (vrai prénom et nom), téléphone et
/// moto (« Bajaj Boxer 125 Noir - DK-1234-AB »), branchés en temps réel sur
/// son profil Firestore (voir [AuthRepository.profilUtilisateurStream] —
/// même mécanisme que l'onglet Compte Client) ; [profil] ne sert qu'au mode
/// démo. La fiche se modifie depuis la carte d'identité (zone cliquable et
/// bouton « Modifier mon profil »), voir [ModifierFicheChauffeurPage].
///
/// Ne gère plus l'envoi des documents KYC (Permis, Carte grise,
/// Attestation VTC) : cette UI a été déplacée vers [ConducteurKYCPage],
/// affichée obligatoirement avant tout accès à l'app (voir le
/// "Gardien" dans [ConducteurShellPage]). Un chauffeur qui atteint cet
/// onglet a donc déjà un dossier validé — inutile d'y refaire figurer
/// des boutons d'ajout de document.
class ConducteurCompteTab extends StatefulWidget {
  const ConducteurCompteTab({
    super.key,
    required this.profil,
    required this.onDeconnexion,
    this.fluxProfil,
    this.ficheService,
  });

  /// Profil du mode démo (sans Firebase) ; ignoré avec un vrai compte.
  final ProfilConducteur? profil;
  final VoidCallback onDeconnexion;

  /// Profil Firestore de l'utilisateur ; `null` : flux réel du compte
  /// connecté. Sert aux tests et aux aperçus, sans projet Firebase.
  final Stream<Map<String, dynamic>?>? fluxProfil;

  /// Enregistrement de la fiche ; injectable pour les tests.
  final FicheChauffeurService? ficheService;

  @override
  State<ConducteurCompteTab> createState() => _ConducteurCompteTabState();
}

class _ConducteurCompteTabState extends State<ConducteurCompteTab> {
  final _authRepository = AuthRepository();
  final _documentsService = ConducteurDocumentsService();
  final _imagePicker = ImagePicker();
  final Set<String> _enCoursTeleversement = {};

  late final FicheChauffeurService _ficheService = widget.ficheService ?? FicheChauffeurService();

  void _ouvrirPage(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  /// Sans Firebase (démo) : fiche tirée du profil de démonstration.
  bool get _demo => widget.fluxProfil == null && !AuthRepository.firebasePret;

  static FicheChauffeur _ficheDemo(ProfilConducteur? p) => FicheChauffeur(
        nomEnregistre: p?.nom ?? 'Conducteur',
        telephone: p?.telephone ?? '',
        vehiculeEnregistre: p?.vehiculeId ?? '',
        plaque: p?.plaqueImmatriculation ?? '',
        statutValidation: (p?.estValide ?? false) ? 'valide' : null,
      );

  Future<void> _modifierFiche(FicheChauffeur fiche) async {
    if (_demo) {
      PremiumDialog.bientotDisponible(context, 'La modification du profil');
      return;
    }
    final resultat = await Navigator.of(context).push<ResultatFiche>(
      MaterialPageRoute(builder: (_) => ModifierFicheChauffeurPage(fiche: fiche, service: _ficheService)),
    );
    if (!mounted || resultat == null) return;
    final message = switch (resultat) {
      ResultatFiche.inchange => 'Aucune modification.',
      ResultatFiche.enregistre => 'Vos informations sont enregistrées.',
      ResultatFiche.aVerifier =>
        'Modification envoyée : Sprint la vérifie avec vos pièces avant que vos clients la voient.',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _annulerDemande() async {
    try {
      await _ficheService.annulerDemande();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Annulation impossible. Vérifiez votre connexion.')),
        );
      }
    }
  }

  /// Ouvre la galerie, compresse l'image (voir la note de
  /// [ConducteurDocumentsService]) et l'envoie sous la clé [cle]. Ne
  /// sert plus qu'à la photo de profil ('photoProfil') : les documents
  /// KYC se téléversent désormais depuis [ConducteurKYCPage], avant
  /// même l'accès à cet onglet.
  Future<void> _choisirEtTeleverser(String cle) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final fichier = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 640,
      imageQuality: 35,
    );
    if (fichier == null || !mounted) return;

    setState(() => _enCoursTeleversement.add(cle));
    try {
      final octets = await fichier.readAsBytes();
      await _documentsService.televerserDocument(uid: uid, cle: cle, octets: octets);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document envoyé pour vérification.')),
        );
      }
    } on DocumentTropVolumineuxException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cette photo est trop volumineuse. Choisissez-en une plus légère.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Échec de l'envoi. Réessayez.")),
        );
      }
    } finally {
      if (mounted) setState(() => _enCoursTeleversement.remove(cle));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: widget.fluxProfil ?? _authRepository.profilUtilisateurStream(),
      builder: (context, snapshot) {
        final fiche = _demo ? _ficheDemo(widget.profil) : FicheChauffeur.depuis(snapshot.data);
        final nom = fiche.nomComplet.isNotEmpty ? fiche.nomComplet : 'Chauffeur Sprint';
        final demande = fiche.modificationDemandee;

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text('Compte', style: styleTitreEcran),
                const SizedBox(height: 20),
                const CarteNotifications(raison: 'les nouvelles courses et les messages, même quand Sprint est fermé'),
                const SizedBox(height: 20),
                AppCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _AvatarConducteur(
                        nom: nom,
                        photo: fiche.photo,
                        enCours: _enCoursTeleversement.contains('photoProfil'),
                        onTap: () => _choisirEtTeleverser('photoProfil'),
                      ),
                      const SizedBox(height: 14),
                      // Zone cliquable : nom, téléphone et moto ouvrent la fiche.
                      Semantics(
                        button: true,
                        label: 'Modifier mon profil',
                        child: InkWell(
                          key: const ValueKey('zone-fiche'),
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _modifierFiche(fiche),
                          child: Column(
                            children: [
                              Text(
                                nom,
                                key: const ValueKey('nom-chauffeur'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4,
                                  color: AppColors.texte,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                fiche.telephone,
                                style: const TextStyle(fontSize: 13, color: AppColors.texteDiscret),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: AppColors.carteHaute,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.two_wheeler_rounded, color: AppColors.vert, size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        fiche.motoEtPlaque.isNotEmpty ? fiche.motoEtPlaque : 'Ajoutez votre moto et sa plaque',
                                        key: const ValueKey('moto-chauffeur'),
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: fiche.motoEtPlaque.isNotEmpty ? AppColors.texte : AppColors.texteDiscret,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (demande != null) ...[
                        const SizedBox(height: 12),
                        _DemandeEnAttente(demande: demande, onAnnuler: _annulerDemande),
                      ] else if (fiche.modificationRefuseeLe != null) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Votre dernière modification n\'a pas été validée par Sprint. Corrigez-la, ou écrivez au '
                          'support depuis le Centre d\'aide.',
                          key: ValueKey('modification-refusee'),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12.5, color: AppColors.alerte, height: 1.4),
                        ),
                      ],
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          key: const ValueKey('bouton-modifier-profil'),
                          onPressed: () => _modifierFiche(fiche),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Modifier mon profil', style: TextStyle(fontWeight: FontWeight.w700)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.texte,
                            minimumSize: const Size.fromHeight(48),
                            side: const BorderSide(color: AppColors.vert, width: 1.2),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                const Text('Plus', style: styleTitreSection),
                const SizedBox(height: 12),
                AppCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      _ItemMenu(
                        icon: Icons.badge_outlined,
                        label: 'Mes informations et ma moto',
                        onTap: () => _modifierFiche(fiche),
                      ),
                      const Divider(height: 1, color: AppColors.bord),
                      _ItemMenu(
                        icon: Icons.help_outline_rounded,
                        label: 'Centre d\'aide',
                        onTap: () => _ouvrirPage(context, const CentreAidePage()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                AppCard(
                  onTap: widget.onDeconnexion,
                  child: const Row(
                    children: [
                      Icon(Icons.logout_rounded, color: AppColors.danger, size: 20),
                      SizedBox(width: 12),
                      Text(
                        'Se déconnecter',
                        style: TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Modification envoyée (dossier validé), en attente de Sprint.
class _DemandeEnAttente extends StatelessWidget {
  const _DemandeEnAttente({required this.demande, required this.onAnnuler});

  final ModificationDemandee demande;
  final VoidCallback onAnnuler;

  static String _date(DateTime d) {
    String deux(int n) => n.toString().padLeft(2, '0');
    return '${deux(d.day)}/${deux(d.month)}';
  }

  @override
  Widget build(BuildContext context) {
    final le = demande.demandeLe;
    return Container(
      key: const ValueKey('demande-en-attente'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
      decoration: BoxDecoration(
        color: AppColors.alerte.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.alerte.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.hourglass_top_rounded, size: 18, color: AppColors.alerte),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Modification envoyée${le == null ? '' : ' le ${_date(le)}'}, en vérification par Sprint : '
                  '${demande.nomComplet} · ${demande.motoEtPlaque}',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.texte, height: 1.4),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: onAnnuler, child: const Text('Annuler la demande')),
          ),
        ],
      ),
    );
  }
}

class _AvatarConducteur extends StatelessWidget {
  const _AvatarConducteur({
    required this.nom,
    required this.photo,
    required this.enCours,
    required this.onTap,
  });

  final String nom;
  final String? photo;
  final bool enCours;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final contenu = ClipOval(
      child: ImageDocument(
        source: photo,
        width: 76,
        height: 76,
        placeholder: _initiale(nom),
      ),
    );

    return GestureDetector(
      onTap: enCours ? null : onTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(width: 76, height: 76, child: contenu),
          if (enCours)
            Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(color: AppColors.shadow, shape: BoxShape.circle),
              child: const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                ),
              ),
            ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: AppColors.vert,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.onyx, width: 2),
              ),
              child: const Icon(Icons.camera_alt_rounded, color: AppColors.onyx, size: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _initiale(String nom) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.onyx,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.vert, width: 3),
      ),
      alignment: Alignment.center,
      child: Text(
        nom.isNotEmpty ? nom[0].toUpperCase() : '?',
        style: const TextStyle(color: AppColors.texte, fontSize: 30, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _ItemMenu extends StatelessWidget {
  const _ItemMenu({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.vert, size: 21),
      title: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.texte)),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.texteDiscret),
      onTap: onTap,
    );
  }
}
