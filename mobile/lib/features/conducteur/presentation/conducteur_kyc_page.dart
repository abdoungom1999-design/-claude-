import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../auth/data/auth_repository.dart';
import '../data/conducteur_documents_service.dart';

const _documentsRequis = ['permis', 'carteGrise', 'attestationVtc'];

/// Page obligatoire affichée juste après la création du compte
/// Conducteur, avant tout accès au tableau de bord (voir le "Gardien"
/// dans [ConducteurShellPage], qui l'affiche tant que le document
/// Firestore de l'utilisateur n'a pas encore de champ
/// `statutValidation`, c'est-à-dire tant qu'aucun document n'a jamais
/// été envoyé).
///
/// Corrige une faille logique : cette UI ("Mes documents") vivait
/// auparavant dans l'onglet Compte, donc APRÈS connexion — rien
/// n'empêchait un chauffeur non vérifié d'ignorer cette section et
/// d'utiliser l'app normalement. Elle bloque désormais l'accès dès la
/// racine, avant [ConducteurEnAttentePage] puis le tableau de bord.
class ConducteurKYCPage extends StatefulWidget {
  const ConducteurKYCPage({
    super.key,
    required this.onDossierSoumis,
    required this.onDeconnexion,
  });

  /// Appelé une fois les 3 documents envoyés et le bouton "Soumettre
  /// mon dossier" pressé : fait passer [ConducteurShellPage] à l'écran
  /// d'attente directement, sans recharger tout le profil.
  final VoidCallback onDossierSoumis;
  final VoidCallback onDeconnexion;

  @override
  State<ConducteurKYCPage> createState() => _ConducteurKYCPageState();
}

class _ConducteurKYCPageState extends State<ConducteurKYCPage> {
  final _authRepository = AuthRepository();
  final _documentsService = ConducteurDocumentsService();
  final _imagePicker = ImagePicker();
  final Set<String> _enCoursTeleversement = {};

  /// Ouvre la galerie, compresse l'image (voir la note de
  /// [ConducteurDocumentsService]) et l'envoie sous la clé [cle]
  /// ('permis', 'carteGrise' ou 'attestationVtc').
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

  bool _envoye(String cle, Map<String, dynamic> documents) =>
      (documents[cle] as String?)?.isNotEmpty ?? false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: StreamBuilder<Map<String, dynamic>?>(
          stream: _authRepository.profilUtilisateurStream(),
          builder: (context, snapshot) {
            final documents = (snapshot.data?['documents'] as Map<String, dynamic>?) ?? {};
            final tousEnvoyes = _documentsRequis.every((cle) => _envoye(cle, documents));

            return ListView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: AppColors.orangeLight,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.folder_shared_outlined, color: AppColors.orange, size: 30),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Complétez votre dossier',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Avant de prendre votre première course, envoyez une photo lisible '
                  "de chacun de ces documents. L'équipe du Groupe Santine les vérifie "
                  "avant d'activer votre compte.",
                  style: TextStyle(fontSize: 13.5, color: AppColors.grey, height: 1.5),
                ),
                const SizedBox(height: 24),
                AppCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      _LigneDocumentKyc(
                        icon: Icons.badge_outlined,
                        label: 'Permis de conduire',
                        envoye: _envoye('permis', documents),
                        enCours: _enCoursTeleversement.contains('permis'),
                        onTap: () => _choisirEtTeleverser('permis'),
                      ),
                      const Divider(height: 1, color: AppColors.greyBorder),
                      _LigneDocumentKyc(
                        icon: Icons.description_outlined,
                        label: 'Carte grise',
                        envoye: _envoye('carteGrise', documents),
                        enCours: _enCoursTeleversement.contains('carteGrise'),
                        onTap: () => _choisirEtTeleverser('carteGrise'),
                      ),
                      const Divider(height: 1, color: AppColors.greyBorder),
                      _LigneDocumentKyc(
                        icon: Icons.shield_outlined,
                        label: 'Attestation VTC',
                        envoye: _envoye('attestationVtc', documents),
                        enCours: _enCoursTeleversement.contains('attestationVtc'),
                        onTap: () => _choisirEtTeleverser('attestationVtc'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                PrimaryButton(
                  label: 'Soumettre mon dossier',
                  onPressed: tousEnvoyes ? widget.onDossierSoumis : null,
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: widget.onDeconnexion,
                    child: const Text(
                      'Se déconnecter',
                      style: TextStyle(color: AppColors.grey, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LigneDocumentKyc extends StatelessWidget {
  const _LigneDocumentKyc({
    required this.icon,
    required this.label,
    required this.envoye,
    required this.enCours,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool envoye;
  final bool enCours;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final couleur = envoye ? AppColors.vert : AppColors.grey;
    final iconeEtat = envoye ? Icons.check_circle_rounded : Icons.upload_outlined;
    final texteEtat = envoye ? 'Envoyé' : 'Ajouter';

    return InkWell(
      onTap: enCours ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
