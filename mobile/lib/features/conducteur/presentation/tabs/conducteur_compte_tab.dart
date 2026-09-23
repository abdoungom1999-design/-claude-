import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/premium_dialog.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../compte/presentation/centre_aide_page.dart';
import '../../data/conducteur_documents_service.dart';
import '../../data/conducteur_repository.dart';

enum _EtatDocument { nonEnvoye, enAttente, valide }

/// Onglet Compte : identité du conducteur (branchée en temps réel sur
/// Firestore, voir [AuthRepository.profilUtilisateurStream] — même
/// mécanisme que l'onglet Compte Client), documents KYC téléversables
/// depuis la galerie (voir [ConducteurDocumentsService]), et accès aux
/// pages annexes.
class ConducteurCompteTab extends StatefulWidget {
  const ConducteurCompteTab({
    super.key,
    required this.profil,
    required this.onDeconnexion,
  });

  final ProfilConducteur? profil;
  final VoidCallback onDeconnexion;

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
  /// [ConducteurDocumentsService]) et l'envoie sous la clé [cle]
  /// ('permis', 'carteGrise', 'attestationVtc' ou 'photoProfil').
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

  _EtatDocument _etatDocument(String cle, Map<String, dynamic> documents, String? statutValidation) {
    final present = (documents[cle] as String?)?.isNotEmpty ?? false;
    if (!present) return _EtatDocument.nonEnvoye;
    return statutValidation == 'valide' ? _EtatDocument.valide : _EtatDocument.enAttente;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _authRepository.profilUtilisateurStream(),
      builder: (context, snapshot) {
        final donnees = snapshot.data;
        final nomFirestore = (donnees?['nom'] as String?)?.trim();
        final nom = (nomFirestore != null && nomFirestore.isNotEmpty)
            ? nomFirestore
            : (widget.profil?.nom ?? 'Conducteur');
        final documents = (donnees?['documents'] as Map<String, dynamic>?) ?? {};
        final statutValidation = donnees?['statutValidation'] as String?;
        final photoProfil = documents['photoProfil'] as String?;

        return Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Compte',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                AppCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _AvatarConducteur(
                        nom: nom,
                        photoBase64: photoProfil,
                        enCours: _enCoursTeleversement.contains('photoProfil'),
                        onTap: () => _choisirEtTeleverser('photoProfil'),
                      ),
                      const SizedBox(height: 14),
                      Text(nom, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        widget.profil?.telephone ?? '',
                        style: const TextStyle(fontSize: 13, color: AppColors.grey),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.greyLight,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.two_wheeler_rounded, color: AppColors.text, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                [
                                  widget.profil?.vehiculeId,
                                  widget.profil?.plaqueImmatriculation,
                                ].where((v) => v != null && v.isNotEmpty).join(' - '),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Mes documents',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Ajoutez une photo lisible de chaque document. Ils seront vérifiés par '
                  "l'équipe du Groupe Santine.",
                  style: TextStyle(fontSize: 12, color: AppColors.grey),
                ),
                const SizedBox(height: 12),
                AppCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      _LigneDocument(
                        icon: Icons.badge_outlined,
                        label: 'Permis de conduire',
                        etat: _etatDocument('permis', documents, statutValidation),
                        enCours: _enCoursTeleversement.contains('permis'),
                        onTap: () => _choisirEtTeleverser('permis'),
                      ),
                      const Divider(height: 1, color: AppColors.greyBorder),
                      _LigneDocument(
                        icon: Icons.description_outlined,
                        label: 'Carte grise',
                        etat: _etatDocument('carteGrise', documents, statutValidation),
                        enCours: _enCoursTeleversement.contains('carteGrise'),
                        onTap: () => _choisirEtTeleverser('carteGrise'),
                      ),
                      const Divider(height: 1, color: AppColors.greyBorder),
                      _LigneDocument(
                        icon: Icons.shield_outlined,
                        label: 'Attestation VTC',
                        etat: _etatDocument('attestationVtc', documents, statutValidation),
                        enCours: _enCoursTeleversement.contains('attestationVtc'),
                        onTap: () => _choisirEtTeleverser('attestationVtc'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Plus',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
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
                      const Divider(height: 1, color: AppColors.greyBorder),
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
                      Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
                      SizedBox(width: 12),
                      Text(
                        'Se déconnecter',
                        style: TextStyle(
                          color: Colors.redAccent,
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
    required this.photoBase64,
    required this.enCours,
    required this.onTap,
  });

  final String nom;
  final String? photoBase64;
  final bool enCours;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Widget contenu;
    if (photoBase64 != null && photoBase64!.isNotEmpty) {
      try {
        final octets = base64Decode(photoBase64!.split(',').last);
        contenu = ClipOval(
          child: Image.memory(octets, width: 76, height: 76, fit: BoxFit.cover),
        );
      } catch (_) {
        contenu = _initiale(nom);
      }
    } else {
      contenu = _initiale(nom);
    }

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
              decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
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
                color: AppColors.orange,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _initiale(String nom) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.orange, AppColors.orangeDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        nom.isNotEmpty ? nom[0].toUpperCase() : '?',
        style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _LigneDocument extends StatelessWidget {
  const _LigneDocument({
    required this.icon,
    required this.label,
    required this.etat,
    required this.enCours,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final _EtatDocument etat;
  final bool enCours;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color couleur;
    final IconData iconeEtat;
    final String texteEtat;
    switch (etat) {
      case _EtatDocument.valide:
        couleur = AppColors.vert;
        iconeEtat = Icons.check_circle_rounded;
        texteEtat = 'Validé';
        break;
      case _EtatDocument.enAttente:
        couleur = AppColors.orange;
        iconeEtat = Icons.hourglass_top_rounded;
        texteEtat = 'En attente';
        break;
      case _EtatDocument.nonEnvoye:
        couleur = AppColors.grey;
        iconeEtat = Icons.upload_outlined;
        texteEtat = 'Ajouter';
        break;
    }

    return InkWell(
      onTap: enCours ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.text),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
            ),
            if (enCours)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.orange),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: couleur.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(iconeEtat, size: 13, color: couleur),
                    const SizedBox(width: 5),
                    Text(
                      texteEtat,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: couleur),
                    ),
                  ],
                ),
              ),
          ],
        ),
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
      leading: Icon(icon, color: AppColors.text, size: 21),
      title: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.grey),
      onTap: onTap,
    );
  }
}
