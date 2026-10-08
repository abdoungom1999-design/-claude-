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

/// Onglet Compte : identité du conducteur (branchée en temps réel sur
/// Firestore, voir [AuthRepository.profilUtilisateurStream] — même
/// mécanisme que l'onglet Compte Client) et accès aux pages annexes.
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
  });

  final ProfilConducteur? profil;
  final VoidCallback onDeconnexion;

  /// Profil Firestore de l'utilisateur ; `null` : flux réel du compte
  /// connecté. Sert aux tests et aux aperçus, sans projet Firebase.
  final Stream<Map<String, dynamic>?>? fluxProfil;

  @override
  State<ConducteurCompteTab> createState() => _ConducteurCompteTabState();
}

class _ConducteurCompteTabState extends State<ConducteurCompteTab> {
  final _authRepository = AuthRepository();
  final _documentsService = ConducteurDocumentsService();
  final _imagePicker = ImagePicker();
  final Set<String> _enCoursTeleversement = {};

  void _ouvrirPage(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
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
        final donnees = snapshot.data;
        final nomFirestore = (donnees?['nom'] as String?)?.trim();
        final nom = (nomFirestore != null && nomFirestore.isNotEmpty)
            ? nomFirestore
            : (widget.profil?.nom ?? 'Conducteur');
        final documents = (donnees?['documents'] as Map<String, dynamic>?) ?? {};
        final photoProfil = documents['photoProfil'] as String?;

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
                        photo: photoProfil,
                        enCours: _enCoursTeleversement.contains('photoProfil'),
                        onTap: () => _choisirEtTeleverser('photoProfil'),
                      ),
                      const SizedBox(height: 14),
                      Text(nom, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppColors.texte)),
                      const SizedBox(height: 4),
                      Text(
                        widget.profil?.telephone ?? '',
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
                                [
                                  widget.profil?.vehiculeId,
                                  widget.profil?.plaqueImmatriculation,
                                ].where((v) => v != null && v.isNotEmpty).join(' - '),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.texte),
                              ),
                            ),
                          ],
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
                        icon: Icons.help_outline_rounded,
                        label: 'Centre d\'aide',
                        onTap: () => _ouvrirPage(context, const CentreAidePage()),
                      ),
                      const Divider(height: 1, color: AppColors.bord),
                      _ItemMenu(
                        icon: Icons.settings_outlined,
                        label: 'Paramètres',
                        onTap: () => PremiumDialog.bientotDisponible(context, 'Paramètres'),
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
